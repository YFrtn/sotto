import SwiftUI

/// The interactive pill-shaped UI shown during recording.
/// Apple Intelligence "Siri Aura" Style (fixed).
struct RecordingOverlayView: View {
    let appState: AppState

    var onPauseResume: (() -> Void)? = nil
    var onStopAndTranscribe: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    var body: some View {
        Group {
            if isVisible {
                ZStack {
                    // 👇 Капсула + градиент + бордер рисуются как один Metal-растр
                    // через drawingGroup — на светлом фоне нет никаких прямоугольных
                    // артефактов от композитинга слоёв.
                    Capsule()
                        .fill(Color.black.opacity(0.55))
                        .background(
                            SiriAuraBackground(audioLevel: appState.audioLevel, phase: appState.phase)
                                .clipShape(Capsule())
                        )
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .drawingGroup()
                        .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)

                    // Контент поверх капсулы (вне drawingGroup, чтобы иконки оставались векторными)
                    HStack(spacing: 16) {
                        // 1. Кнопка Отмены (Красное стекло)
                        Button(action: {
                            onCancel?()
                        }) {
                            ZStack {
                                Circle().fill(Color.red.opacity(0.75))
                                Image(systemName: "xmark")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Circle())
                        .disabled(appState.phase == .transcribing)

                        // 2. Кнопка Паузы / Плей (Морозное стекло)
                        Button(action: {
                            onPauseResume?()
                        }) {
                            ZStack {
                                Circle().fill(Color.white.opacity(0.25))
                                Image(systemName: appState.phase == .paused ? "play.fill" : "pause.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Circle())
                        .disabled(appState.phase == .transcribing)

                        // 3. Светящийся белый эквалайзер
                        HStack(spacing: 5) {
                            ForEach(0..<6) { i in
                                Capsule()
                                    .fill(Color.white)
                                    .frame(width: 5, height: capsuleHeight(index: i))
                                    .animation(.bouncy(duration: 0.25, extraBounce: 0.1), value: appState.audioLevel)
                                    .shadow(color: .white.opacity(0.6), radius: 4, x: 0, y: 0)
                            }
                        }
                        .frame(width: 54, height: 32)
                        .opacity(appState.phase == .transcribing ? 0.3 : 1.0)

                        // 4. Кнопка Отправить (Зеленое стекло)
                        Button(action: {
                            onStopAndTranscribe?()
                        }) {
                            ZStack {
                                Circle().fill(Color.green.opacity(0.75))
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Circle())
                        .disabled(appState.phase == .transcribing)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .fixedSize()
            }
        }
    }

    private var isVisible: Bool {
        appState.phase == .recording || appState.phase == .transcribing || appState.phase == .paused
    }

    private func capsuleHeight(index: Int) -> CGFloat {
        let baseHeight: CGFloat = 6
        if appState.phase == .transcribing || appState.phase == .paused { return baseHeight }
        let level = CGFloat(appState.audioLevel)
        let modifiers: [CGFloat] = [0.7, 1.1, 0.9, 1.2, 0.8, 0.6]
        let modifiedLevel = level * 300 * modifiers[index]
        return max(baseHeight, min(28, modifiedLevel))
    }
}

/// Анимированный фон в стиле Apple Intelligence (Siri Aura)
struct SiriAuraBackground: View {
    var audioLevel: Float
    var phase: AppPhase

    @State private var rotation: Double = 0

    var body: some View {
        GeometryReader { geo in
            // Диагональ × 2.2 — гарантирует, что круглый угловой градиент
            // полностью накроет широкую пилюлю и по бокам не останется пустот.
            let diameter = max(geo.size.width, geo.size.height) * 2.2

            ZStack {
                let intensity = (phase == .recording) ? CGFloat(audioLevel) * 2.0 : 0.0
                let scale = 1.0 + (intensity * 0.15)

                AngularGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.2, green: 0.5, blue: 1.0),
                        Color(red: 0.8, green: 0.3, blue: 0.9),
                        Color(red: 1.0, green: 0.5, blue: 0.3),
                        Color(red: 0.2, green: 0.5, blue: 1.0)
                    ]),
                    center: .center,
                    angle: .degrees(rotation)
                )
                .frame(width: diameter, height: diameter)
                .blur(radius: 25)
                .opacity(0.55 + (Double(intensity) * 0.4))
                .scaleEffect(scale)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: intensity)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .onAppear {
                withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
        }
    }
}
