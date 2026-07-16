import Foundation
import os

/// Manages the bundled `gigastt` sidecar server (GigaAM v3, ONNX Runtime).
///
/// Lifecycle: `ensureModelDownloaded` runs `gigastt download` once,
/// `start` launches `gigastt serve` on a loopback port and waits for `/ready`,
/// `transcribe` POSTs a WAV payload to `/v1/transcribe`.
/// The actor serializes all operations; the server process is torn down
/// on `stop()` and when the app exits (via `Process` lifetime + terminate).
actor GigaSTTEngine {
    static let port = 49876

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "sotto",
        category: "gigastt"
    )

    /// Expected download size used for directory-size-based progress (~850 MB
    /// FP32 download; INT8 quantization happens afterwards).
    private static let expectedDownloadBytes: Int64 = 850_000_000

    private var serverProcess: Process?

    /// Mirror of the running server process for synchronous teardown from
    /// `applicationWillTerminate`, where awaiting the actor is not possible.
    private static let activeProcess = OSAllocatedUnfairLock<Process?>(initialState: nil)

    /// Synchronously terminates the sidecar. Safe to call from any thread;
    /// used as the app-exit safety net so the server never outlives Sotto.
    nonisolated static func emergencyShutdown() {
        activeProcess.withLock { process in
            if let process, process.isRunning {
                process.terminate()
            }
            process = nil
        }
    }

    // MARK: - Paths

    static var modelDirectory: URL {
        URL.cachesDirectory
            .appendingPathComponent("gigastt")
            .appendingPathComponent("models")
    }

    /// Locates the gigastt binary: bundled Resources first, then dev fallbacks.
    static func binaryURL() -> URL? {
        var candidates: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("gigastt"))
        }
        candidates.append(URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Projects/MLX/gigastt/target/release/gigastt"))
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/gigastt"))
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/gigastt"))

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    // MARK: - Model download / presence

    /// Whether a usable model snapshot exists locally (any .onnx weights present).
    nonisolated static func isModelDownloaded() -> Bool {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: modelDirectory,
            includingPropertiesForKeys: nil
        ) else { return false }
        return files.contains { $0.pathExtension == "onnx" }
    }

    /// Runs `gigastt download` if no local snapshot exists.
    /// Progress is estimated from the model directory size.
    func ensureModelDownloaded(
        updateHandler: (@MainActor @Sendable (ModelLoadUpdate) -> Void)? = nil
    ) async throws {
        guard !Self.isModelDownloaded() else { return }

        guard let binary = Self.binaryURL() else {
            throw GigaSTTError.binaryNotFound
        }

        try FileManager.default.createDirectory(
            at: Self.modelDirectory, withIntermediateDirectories: true
        )

        await updateHandler?(.downloading(progress: 0))

        let process = Process()
        process.executableURL = binary
        process.arguments = ["download", "--model-dir", Self.modelDirectory.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()

        // Poll directory size for coarse progress while the download runs.
        let progressTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                let size = Self.directorySize(Self.modelDirectory)
                let fraction = min(Double(size) / Double(Self.expectedDownloadBytes), 0.98)
                await updateHandler?(.downloading(progress: fraction))
            }
        }

        defer { progressTask.cancel() }

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                process.terminationHandler = { _ in continuation.resume() }
            }
        } onCancel: {
            // Interrupt a half-finished download when the user switches models.
            process.terminate()
        }
        progressTask.cancel()

        if Task.isCancelled {
            // Cooperative cancellation: kill a half-finished download so a
            // stale partial snapshot doesn't pass the presence check later.
            try? FileManager.default.removeItem(at: Self.modelDirectory)
            throw CancellationError()
        }

        guard process.terminationStatus == 0, Self.isModelDownloaded() else {
            try? FileManager.default.removeItem(at: Self.modelDirectory)
            throw GigaSTTError.downloadFailed(exitCode: process.terminationStatus)
        }

        await updateHandler?(.downloading(progress: 1))
    }

    func deleteLocalModel() throws {
        stop()
        guard FileManager.default.fileExists(atPath: Self.modelDirectory.path) else { return }
        try FileManager.default.removeItem(at: Self.modelDirectory)
    }

    // MARK: - Server lifecycle

    var isRunning: Bool {
        serverProcess?.isRunning ?? false
    }

    /// Launches `gigastt serve` and waits until `/ready` returns 200.
    func start() async throws {
        if isRunning { return }

        guard let binary = Self.binaryURL() else {
            throw GigaSTTError.binaryNotFound
        }

        let process = Process()
        process.executableURL = binary
        process.arguments = [
            "serve",
            "--port", String(Self.port),
            "--model-dir", Self.modelDirectory.path,
            "--punct-model-dir", Self.modelDirectory.appendingPathComponent("punct").path,
            "--pool-size", "1",
            "--punctuation", "on",
            "--itn", "on",
        ]
        // Silence child output; errors surface via /ready polling timeout.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { proc in
            Self.logger.info("gigastt server exited with status \(proc.terminationStatus)")
        }

        try process.run()
        serverProcess = process
        Self.activeProcess.withLock { $0 = process }

        do {
            try await waitUntilReady(process: process)
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        guard let process = serverProcess else { return }
        serverProcess = nil
        Self.activeProcess.withLock { $0 = nil }
        guard process.isRunning else { return }
        process.terminationHandler = nil
        process.terminate()
    }

    private func waitUntilReady(process: Process, timeout: TimeInterval = 60) async throws {
        let readyURL = URL(string: "http://127.0.0.1:\(Self.port)/ready")!
        let deadline = ContinuousClock.now + .seconds(timeout)

        while ContinuousClock.now < deadline {
            try Task.checkCancellation()

            guard process.isRunning else {
                throw GigaSTTError.serverExited(exitCode: process.terminationStatus)
            }

            var request = URLRequest(url: readyURL)
            request.timeoutInterval = 2
            if let (_, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                return
            }

            try await Task.sleep(for: .milliseconds(300))
        }

        throw GigaSTTError.serverNotReady
    }

    // MARK: - Transcription

    /// Transcribe Float32 16kHz mono samples via the sidecar REST API.
    func transcribe(audio: [Float]) async throws -> String {
        guard isRunning else {
            throw GigaSTTError.serverNotRunning
        }

        let wavData = Self.encodeWAV(samples: audio, sampleRate: 16_000)

        var request = URLRequest(
            url: URL(string: "http://127.0.0.1:\(Self.port)/v1/transcribe")!
        )
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = wavData
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw GigaSTTError.transcriptionFailed(statusCode: code)
        }

        struct TranscribeResponse: Decodable {
            let text: String
        }

        let decoded = try JSONDecoder().decode(TranscribeResponse.self, from: data)
        return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Helpers

    /// Minimal PCM16 WAV encoder for Float32 mono samples.
    static func encodeWAV(samples: [Float], sampleRate: Int) -> Data {
        let pcm: [Int16] = samples.map { sample in
            let clamped = max(-1.0, min(1.0, sample))
            return Int16(clamped * Float(Int16.max))
        }

        let dataSize = pcm.count * MemoryLayout<Int16>.size
        var data = Data(capacity: 44 + dataSize)

        func append(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))                        // fmt chunk size
        append(UInt16(1))                         // PCM
        append(UInt16(1))                         // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))            // byte rate
        append(UInt16(2))                         // block align
        append(UInt16(16))                        // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataSize))
        pcm.withUnsafeBytes { data.append(contentsOf: $0) }

        return data
    }

    private static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }
}

enum GigaSTTError: LocalizedError {
    case binaryNotFound
    case downloadFailed(exitCode: Int32)
    case serverExited(exitCode: Int32)
    case serverNotReady
    case serverNotRunning
    case transcriptionFailed(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "gigastt binary not found in app bundle"
        case .downloadFailed(let code):
            return "GigaAM model download failed (exit \(code))"
        case .serverExited(let code):
            return "gigastt server exited unexpectedly (exit \(code))"
        case .serverNotReady:
            return "gigastt server did not become ready in time"
        case .serverNotRunning:
            return "gigastt server is not running"
        case .transcriptionFailed(let code):
            return "GigaSTT transcription failed (HTTP \(code))"
        }
    }
}
