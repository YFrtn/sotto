import SwiftUI
import Observation

/// The phases of the app's push-to-talk state machine.
enum AppPhase: Equatable {
    case idle
    case loading(String) // loading model, message
    case recording
    case paused // НОВОЕ СОСТОЯНИЕ: Запись на паузе
    case transcribing
    case pasting
    case error(String)
}

private enum AppPhaseKind: Equatable {
    case idle
    case loading
    case recording
    case paused // НОВОЕ СОСТОЯНИЕ
    case transcribing
    case pasting
    case error
}

private extension AppPhase {
    var kind: AppPhaseKind {
        switch self {
        case .idle:
            return .idle
        case .loading:
            return .loading
        case .recording:
            return .recording
        case .paused:
            return .paused
        case .transcribing:
            return .transcribing
        case .pasting:
            return .pasting
        case .error:
            return .error
        }
    }
}

/// Central observable state for the entire app.
@Observable
@MainActor
final class AppState {
    var phase: AppPhase = .idle
    var selectedModelID: String = STTModelDefinition.default.repoID
    var hotkeyPreset: ModifierHotkeyPreset = .defaultPreset
    var hotkeySettingsMessage: String?
    var modelStatus: ModelStatus = .notLoaded
    var downloadedModelRepoIDs: Set<String> = []
    var microphonePermission: PermissionStatus = .unknown
    var accessibilityPermission: PermissionStatus = .unknown
    var runOnStartupEnabled = false
    var runOnStartupError: String?
    /// Real-time microphone audio level (0–1), updated from the audio tap.
    var audioLevel: Float = 0

    /// Brief status text shown in the menu bar dropdown.
    var statusText: String {
        switch phase {
        case .loading(let msg):
            return msg
        case .recording:
            return "Recording..."
        case .paused:
            return "Paused..." // Текст для паузы
        case .transcribing:
            return "Transcribing..."
        case .pasting:
            return "Pasting..."
        case .error(let msg):
            return "Error: \(msg)"
        case .idle:
            switch modelStatus {
            case .loaded where hasRequiredPermissions:
                return "Ready"
            case .loaded:
                return "Missing \(missingPermissionSummary)."
            case .downloading(let progress):
                let percent = Int((min(max(progress, 0), 1) * 100).rounded())
                return "Downloading model (\(percent)%)."
            case .loading:
                return "Initializing model..."
            case .error(let message):
                return "Model error: \(message)"
            case .notLoaded:
                return downloadedModelRepoIDs.isEmpty ? "No local models available." : "Model not loaded."
            }
        }
    }

    var menuStatusLabel: String {
        switch phase {
        case .recording:
            return "Sotto Recording"
        case .paused:
            return "Sotto Paused" // Текст для меню
        case .transcribing:
            return "Sotto Transcribing"
        case .pasting:
            return "Sotto Pasting"
        case .loading:
            switch modelStatus {
            case .downloading:
                return "Sotto Downloading"
            case .loading:
                return "Sotto Initializing"
            default:
                return "Sotto Loading"
            }
        case .error:
            return "Sotto Error"
        case .idle:
            switch modelStatus {
            case .loaded where hasRequiredPermissions:
                return "Sotto Ready"
            case .loaded:
                return "Sotto Needs Permission"
            case .error:
                return "Model Error"
            case .notLoaded where downloadedModelRepoIDs.isEmpty:
                return "No Local Models"
            default:
                return "Sotto Loading"
            }
        }
    }

    var menuStatusColor: Color {
        switch phase {
        case .recording:
            return .red
        case .paused:
            return .yellow // Цвет паузы
        case .transcribing, .pasting:
            return .blue
        case .error:
            return .red
        case .idle:
            switch modelStatus {
            case .loaded where hasRequiredPermissions:
                return .green
            case .error:
                return .red
            default:
                return .orange
            }
        case .loading:
            return .orange
        }
    }

    var shouldShowStatusDetail: Bool {
        if case .idle = phase, modelStatus == .loaded, hasRequiredPermissions {
            return false
        }
        return true
    }

    /// SF Symbol name for the menu bar icon.
    var menuBarIcon: String {
        switch phase {
        case .idle:
            return "waveform.circle"
        case .loading:
            switch modelStatus {
            case .downloading:
                return "arrow.down.circle"
            case .loading:
                return "arrow.right.circle"
            default:
                return "arrow.right.circle"
            }
        case .recording:
            return "waveform.circle.fill"
        case .paused:
            return "pause.circle" // Иконка в статус-баре Mac
        case .transcribing, .pasting:
            return "waveform.circle.fill" // Можно заменить на hourglass, если хочется
        case .error:
            return "exclamationmark.triangle"
        }
    }

    var hasMicrophonePermission: Bool { microphonePermission == .granted }
    var hasAccessibilityPermission: Bool { accessibilityPermission == .granted }
    var hasRequiredPermissions: Bool { hasMicrophonePermission && hasAccessibilityPermission }

    var missingPermissionSummary: String {
        var missing: [String] = []
        if !hasMicrophonePermission {
            missing.append("Microphone")
        }
        if !hasAccessibilityPermission {
            missing.append("Accessibility")
        }

        switch missing.count {
        case 2:
            return "Microphone and Accessibility permissions"
        case 1:
            return "\(missing[0]) permission"
        default:
            return "required permissions"
        }
    }

    @discardableResult
    func transition(to newPhase: AppPhase) -> Bool {
        let currentKind = phase.kind
        let nextKind = newPhase.kind

        guard canTransition(from: currentKind, to: nextKind) else {
            assertionFailure("Invalid phase transition from \(phase) to \(newPhase)")
            return false
        }

        phase = newPhase
        return true
    }

    private func canTransition(from current: AppPhaseKind, to next: AppPhaseKind) -> Bool {
        if current == next {
            return true
        }

        if next == .error {
            return true
        }

        switch current {
        case .idle:
            return next == .loading || next == .recording
        case .loading:
            return next == .idle || next == .loading
        case .recording:
            return next == .paused || next == .transcribing || next == .idle
        case .paused:
            // Из паузы можно вернуться в запись, начать транскрибацию или отменить
            return next == .recording || next == .transcribing || next == .idle
        case .transcribing:
            return next == .pasting || next == .idle
        case .pasting:
            return next == .idle
        case .error:
            return next == .idle || next == .loading
        }
    }
}

enum ModelStatus: Equatable {
    case notLoaded
    case downloading(progress: Double)
    case loading
    case loaded
    case error(String)
}

enum PermissionStatus: Equatable {
    case unknown
    case granted
    case denied
}
