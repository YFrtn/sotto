import AppKit
import SwiftUI

/// Управляет жизненным циклом плавающей панели записи.
@MainActor
final class OverlayManager {
    private var panel: FloatingPanel<RecordingOverlayView>?
    private var isPresented = false
    private let overlaySize = CGSize(width: 250, height: 75) // Оптимальный размер

    func show(
        appState: AppState,
        onPauseResume: @escaping () -> Void,
        onStopAndTranscribe: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        if panel == nil {
            let binding = Binding<Bool>(
                get: { [weak self] in
                    self?.isPresented ?? false
                },
                set: { [weak self] newValue in
                    guard let self else { return }
                    self.isPresented = newValue
                    if !newValue {
                        self.panel = nil
                    }
                }
            )

            let contentRect = NSRect(origin: .zero, size: overlaySize)
            let newPanel = FloatingPanel(
                view: {
                    RecordingOverlayView(
                        appState: appState,
                        onPauseResume: onPauseResume,
                        onStopAndTranscribe: onStopAndTranscribe,
                        onCancel: onCancel
                    )
                },
                contentRect: contentRect,
                isPresented: binding
            )
            
            newPanel.ignoresMouseEvents = false
            newPanel.isMovableByWindowBackground = true // Включаем плавное перетаскивание за фон
            newPanel.positionBottomCenter()
            panel = newPanel
        } else {
            panel?.updateView {
                RecordingOverlayView(
                    appState: appState,
                    onPauseResume: onPauseResume,
                    onStopAndTranscribe: onStopAndTranscribe,
                    onCancel: onCancel
                )
            }
        }

        isPresented = true
        panel?.orderFrontRegardless()
    }

    func hide() {
        isPresented = false
        panel?.close()
        panel = nil
    }
}
