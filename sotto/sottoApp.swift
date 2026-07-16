import AppKit
import AVFoundation
import os
import ServiceManagement
import SwiftUI

/// Ensures the gigastt sidecar server never outlives the app.
final class SottoAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        GigaSTTEngine.emergencyShutdown()
    }
}

@main
struct SottoApp: App {
    @NSApplicationDelegateAdaptor(SottoAppDelegate.self) private var appDelegate
    private static let sharedTranscriptionService = TranscriptionService()
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "sotto",
        category: "startup"
    )

    @State private var appState = AppState()
    @State private var overlayManager = OverlayManager()
    @State private var audioRecorder = AudioRecorder()
    private let transcriptionService = sharedTranscriptionService
    @State private var hotkeyMonitor = ModifierHotkeyMonitor()
    @State private var modelLoadTask: Task<Void, Never>?
    @State private var modelLoadGeneration: UInt64 = 0
    @State private var hasLaunched = false
    @State private var recordingTimeoutTask: Task<Void, Never>?

    private static let maxRecordingDurationSeconds = AudioRecorder.defaultMaximumDuration
    private static let minimumSpeechDurationSeconds = 0.2
    private static let transcriptionSampleRate = 16_000.0

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                appState: appState,
                onModelSelect: { model in selectModel(model) },
                onDeleteLocalModel: { model in Task { @MainActor in await deleteLocalModel(model) } },
                onHotkeyPresetSelect: { preset in updateHotkeyPreset(preset) },
                runOnStartupEnabled: appState.runOnStartupEnabled,
                onRunOnStartupToggle: { toggleRunOnStartup() },
                onRequestMicrophonePermission: { Task { @MainActor in await requestMicrophonePermissionFromMenu() } },
                onRequestAccessibilityPermission: { requestAccessibilityPermissionFromMenu() },
                onRecheckPermissions: { refreshPermissionState() },
                onQuit: { NSApplication.shared.terminate(nil) }
            )
        } label: {
            let icon = menuBarNSImage(symbolName: appState.menuBarIcon, size: 18)
            Image(nsImage: icon)
                .task {
                    guard !hasLaunched else { return }
                    hasLaunched = true
                    await onLaunch()
                }
        }
        .menuBarExtraStyle(.window)
    }

    private func menuBarNSImage(symbolName: String, size: CGFloat) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = true
        return image
    }

    // MARK: - Launch

    @MainActor
    private func onLaunch() async {
        let defaultRepoID = UserDefaults.standard.string(forKey: "selectedModelID")
            ?? STTModelDefinition.default.repoID

        appState.selectedModelID = defaultRepoID
        syncRunOnStartupState()
        configureHotkeyFromDefaults()
        await requestPermissions()
        await refreshDownloadedModels()
        await loadModel(repoID: defaultRepoID)
        setupHotkey()
    }

    // MARK: - Startup Login Item

    @MainActor
    private func toggleRunOnStartup() {
        let service = SMAppService.mainApp
        let statusBefore = service.status
        let shouldDisable = isRunOnStartupEnabled(statusBefore)
        let action = shouldDisable ? "disable" : "enable"

        do {
            if shouldDisable { try service.unregister() }
            else { try service.register() }
            appState.runOnStartupError = nil
        } catch {
            appState.runOnStartupError = "Could not \(action) Run on Startup: \(error.localizedDescription)"
        }
        appState.runOnStartupEnabled = isRunOnStartupEnabled(service.status)
    }

    @MainActor
    private func syncRunOnStartupState() {
        appState.runOnStartupEnabled = isRunOnStartupEnabled(SMAppService.mainApp.status)
    }

    private func isRunOnStartupEnabled(_ status: SMAppService.Status) -> Bool {
        status == .enabled || status == .requiresApproval
    }

    // MARK: - Hotkey Handling

    @MainActor
    private func setupHotkey() {
        hotkeyMonitor.preset = appState.hotkeyPreset
        hotkeyMonitor.onKeyDown = { Task { @MainActor in await handleHotkeyToggle() } }
        hotkeyMonitor.onKeyUp = {}
        hotkeyMonitor.start()
    }

    @MainActor
    private func configureHotkeyFromDefaults() {
        let (preset, fallbackMessage) = ModifierHotkeyPreset.load()
        appState.hotkeyPreset = preset
        appState.hotkeySettingsMessage = fallbackMessage
    }

    @MainActor
    private func updateHotkeyPreset(_ preset: ModifierHotkeyPreset) {
        appState.hotkeyPreset = preset
        appState.hotkeySettingsMessage = nil
        hotkeyMonitor.preset = preset
        preset.save()
    }

    // ЛОГИКА ПАУЗЫ
    @MainActor
    private func togglePause() {
        if appState.phase == .recording {
            audioRecorder.pause()
            _ = appState.transition(to: .paused)
        } else if appState.phase == .paused {
            audioRecorder.resume()
            _ = appState.transition(to: .recording)
        }
    }

    // ЛОГИКА ОТМЕНЫ (СБРОС)
    @MainActor
    private func cancelRecording() {
        guard appState.phase == .recording || appState.phase == .paused else { return }
        cancelRecordingTimeout()
        _ = audioRecorder.stop() // Выключаем микрофон, результаты игнорируем
        appState.audioLevel = 0
        overlayManager.hide()
        _ = appState.transition(to: .idle)
    }

    @MainActor
    private func handleHotkeyToggle() async {
        refreshPermissionState()

        if appState.phase == .idle {
            guard appState.modelStatus == .loaded else { return }
            guard appState.hasRequiredPermissions else {
                _ = appState.transition(to: .error("Missing \(appState.missingPermissionSummary). Open the menu to grant access."))
                resetAfterDelay(seconds: 4)
                return
            }

            _ = appState.transition(to: .recording)
            
            overlayManager.show(
                appState: appState,
                onPauseResume: { self.togglePause() },
                onStopAndTranscribe: { Task { await self.stopRecordingAndTranscribe() } },
                onCancel: { self.cancelRecording() } // 👈 Привязываем крестик
            )
            startRecordingTimeout()

            do {
                try audioRecorder.start { [appState] (level: Float) in
                    Task { @MainActor in appState.audioLevel = level }
                }
            } catch {
                cancelRecordingTimeout()
                _ = appState.transition(to: .error(error.localizedDescription))
                overlayManager.hide()
                resetAfterDelay()
            }
        } else if appState.phase == .recording || appState.phase == .paused {
            await stopRecordingAndTranscribe()
        }
    }

    @MainActor
    private func startRecordingTimeout() {
        cancelRecordingTimeout()
        recordingTimeoutTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(Self.maxRecordingDurationSeconds))
            } catch { return }

            guard appState.phase == .recording || appState.phase == .paused else { return }
            recordingTimeoutTask = nil
            await stopRecordingAndTranscribe(cancelTimeoutTask: false)
        }
    }

    @MainActor
    private func cancelRecordingTimeout() {
        recordingTimeoutTask?.cancel()
        recordingTimeoutTask = nil
    }

    @MainActor
    private func stopRecordingAndTranscribe(cancelTimeoutTask: Bool = true) async {
        guard appState.phase == .recording || appState.phase == .paused else { return }

        if cancelTimeoutTask { cancelRecordingTimeout() }

        let samples = audioRecorder.stop()
        appState.audioLevel = 0

        let minimumSamples = Int(Self.minimumSpeechDurationSeconds * Self.transcriptionSampleRate)
        guard samples.count >= minimumSamples else {
            overlayManager.hide()
            _ = appState.transition(to: .error("Recording too short."))
            resetAfterDelay(seconds: 2)
            return
        }

        _ = appState.transition(to: .transcribing)
        
        // Во время перевода кнопки отключаются
        overlayManager.show(
            appState: appState,
            onPauseResume: {},
            onStopAndTranscribe: {},
            onCancel: {}
        )

        do {
            let text = try await transcriptionService.transcribe(audio: samples)
            _ = appState.transition(to: .pasting)
            try await PasteController.paste(text)
            overlayManager.hide()
            _ = appState.transition(to: .idle)
        } catch {
            _ = appState.transition(to: .error(error.localizedDescription))
            overlayManager.hide()
            resetAfterDelay()
        }
    }

    // MARK: - Model Management
    @MainActor
    private func selectModel(_ model: STTModelDefinition) {
        switch appState.phase {
        case .recording, .transcribing, .pasting: return
        default: break
        }
        appState.selectedModelID = model.repoID
        UserDefaults.standard.set(model.repoID, forKey: "selectedModelID")
        _ = startModelLoad(repoID: model.repoID)
    }

    @MainActor
    private func loadModel(repoID: String) async {
        let task = startModelLoad(repoID: repoID)
        await task.value
    }

    @MainActor
    private func refreshDownloadedModels() async {
        let repoIDs = STTModelDefinition.allModels.map(\.repoID)
        appState.downloadedModelRepoIDs = await transcriptionService.downloadedModelRepoIDs(for: repoIDs)
    }

    @MainActor
    private func deleteLocalModel(_ model: STTModelDefinition) async {
        let repoID = model.repoID
        if appState.selectedModelID == repoID { modelLoadTask?.cancel() }

        do {
            try await transcriptionService.deleteLocalModel(repoID: repoID)
            appState.downloadedModelRepoIDs.remove(repoID)

            if appState.selectedModelID == repoID {
                appState.modelStatus = .notLoaded
                if case .loading = appState.phase { _ = appState.transition(to: .idle) }
            }
        } catch {
            _ = appState.transition(to: .error("Failed to delete model: \(error.localizedDescription)"))
            resetAfterDelay()
        }
    }

    @discardableResult
    @MainActor
    private func startModelLoad(repoID: String) -> Task<Void, Never> {
        modelLoadTask?.cancel()
        modelLoadGeneration &+= 1
        let generation = modelLoadGeneration

        appState.modelStatus = .loading
        _ = appState.transition(to: .loading("Checking model files..."))

        let task = Task(priority: .userInitiated) {
            do {
                try await transcriptionService.loadModel(repoID: repoID) { update in
                    guard generation == modelLoadGeneration else { return }
                    guard appState.selectedModelID == repoID else { return }

                    switch update {
                    case .downloading(let progress):
                        appState.modelStatus = .downloading(progress: progress)
                        _ = appState.transition(to: .loading("Downloading model..."))
                    case .initializing:
                        appState.modelStatus = .loading
                        _ = appState.transition(to: .loading("Initializing model..."))
                    }
                }

                await MainActor.run {
                    guard generation == modelLoadGeneration else { return }
                    guard appState.selectedModelID == repoID else { return }

                    appState.modelStatus = .loaded
                    appState.downloadedModelRepoIDs.insert(repoID)
                    _ = appState.transition(to: .idle)
                    modelLoadTask = nil
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard generation == modelLoadGeneration else { return }
                    modelLoadTask = nil
                    switch appState.modelStatus {
                    case .loading, .downloading: appState.modelStatus = .notLoaded
                    default: break
                    }
                    if case .loading = appState.phase { _ = appState.transition(to: .idle) }
                }
            } catch {
                await MainActor.run {
                    guard generation == modelLoadGeneration else { return }
                    guard appState.selectedModelID == repoID else { return }

                    appState.modelStatus = .error(error.localizedDescription)
                    _ = appState.transition(to: .error("Model load failed: \(error.localizedDescription)"))
                    modelLoadTask = nil
                    resetAfterDelay()
                }
            }
        }
        modelLoadTask = task
        return task
    }

    // MARK: - Permissions

    @MainActor
    private func requestPermissions() async {
        let microphoneGranted = await AudioRecorder.requestPermission()
        appState.microphonePermission = microphoneGranted ? .granted : .denied
        if !PasteController.hasAccessibilityPermission { PasteController.requestAccessibilityPermission() }
        appState.accessibilityPermission = PasteController.hasAccessibilityPermission ? .granted : .denied
    }

    @MainActor
    private func requestMicrophonePermissionFromMenu() async {
        let granted = await AudioRecorder.requestPermission()
        refreshPermissionState()
        guard !granted else { return }
        openPrivacySettings(anchor: "Privacy_Microphone")
    }

    @MainActor
    private func requestAccessibilityPermissionFromMenu() {
        PasteController.requestAccessibilityPermission()
        refreshPermissionState()
        if !appState.hasAccessibilityPermission { openPrivacySettings(anchor: "Privacy_Accessibility") }
    }

    @MainActor
    private func refreshPermissionState() {
        appState.microphonePermission = microphonePermissionStatus()
        appState.accessibilityPermission = PasteController.hasAccessibilityPermission ? .granted : .denied
    }

    private func microphonePermissionStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .unknown
        @unknown default: return .denied
        }
    }

    private func openPrivacySettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Helpers
    @MainActor
    private func resetAfterDelay(seconds: Int = 3) {
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if case .error = appState.phase { _ = appState.transition(to: .idle) }
        }
    }
}
