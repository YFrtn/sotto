import SwiftUI

// Превью-версия нового визуала. В реальном приложении используется
// RecordingOverlayView из RecordingOverlay.swift. Этот файл нужен
// только чтобы крутить дизайн в Xcode Preview, не ломая OverlayManager.

struct CityPillOverlay: View {
    enum CityStyle { case astana, almaty }

    let style: CityStyle
    var isPaused: Bool = false
    var onCancel: () -> Void = {}
    var onPauseResume: () -> Void = {}
    var onSubmit: () -> Void = {}

    private let bgTop    = Color(red: 0.30, green: 0.62, blue: 0.72)
    private let bgMid    = Color(red: 0.18, green: 0.50, blue: 0.62)
    private let bgBottom = Color(red: 0.10, green: 0.34, blue: 0.46)
    private let gold     = Color(red: 0.96, green: 0.80, blue: 0.36)
    private let goldDeep = Color(red: 0.74, green: 0.55, blue: 0.18)
    private let inkDark  = Color(red: 0.07, green: 0.20, blue: 0.30)

    var body: some View {
        ZStack {
            background
            HStack(spacing: 18) {
                circleButton(system: "xmark", filled: true, action: onCancel)
                circleButton(system: isPaused ? "play.fill" : "pause.fill",
                             filled: false, action: onPauseResume)

                Spacer(minLength: 24)

                CityDotsIndicator(color: gold)
                    .frame(height: 10)

                Spacer(minLength: 24)

                circleButton(system: "arrow.up", filled: false, action: onSubmit)
            }
            .padding(.leading, 92)
            .padding(.trailing, 14)
            .padding(.vertical, 14)
        }
        .frame(width: 520, height: 92)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(gold, lineWidth: 2.2))
        .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 8)
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [bgTop, bgMid, bgBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            cityFar.fill(inkDark.opacity(0.28))
            cityNear.fill(gold.opacity(0.18)).blendMode(.plusLighter)

            HStack {
                leadingSymbol
                    .frame(width: 64, height: 76)
                    .padding(.leading, 18)
                Spacer()
            }

            LinearGradient(
                colors: [.white.opacity(0.18), .clear, .black.opacity(0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
            .blendMode(.softLight)
        }
    }

    @ViewBuilder
    private var leadingSymbol: some View {
        switch style {
        case .astana:
            BaiterekIconV2()
                .stroke(gold, style: .init(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
        case .almaty:
            KokTobeIcon()
                .fill(gold)
        }
    }

    private var cityFar: AnyShape {
        switch style {
        case .astana: return AnyShape(AstanaSkylineFull(seed: 0))
        case .almaty: return AnyShape(AlmatyRangeFull(seed: 0))
        }
    }

    private var cityNear: AnyShape {
        switch style {
        case .astana: return AnyShape(AstanaSkylineFull(seed: 1))
        case .almaty: return AnyShape(AlmatyRangeFull(seed: 1))
        }
    }

    private func circleButton(system: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if filled {
                    Circle()
                        .fill(LinearGradient(colors: [gold, goldDeep],
                                             startPoint: .top, endPoint: .bottom))
                    Image(systemName: system)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundColor(inkDark)
                } else {
                    Circle()
                        .fill(bgMid.opacity(0.55))
                        .overlay(Circle().stroke(gold, lineWidth: 2.4))
                    Image(systemName: system)
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundColor(gold)
                }
            }
            .frame(width: 44, height: 44)
            .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Точки

struct CityDotsIndicator: View {
    let color: Color

    var body: some View {
        TimelineView(.animation) { ctx in
            HStack(spacing: 8) {
                ForEach(0..<6) { i in
                    let phase = ctx.date.timeIntervalSinceReferenceDate
                    let pulse = 0.55 + 0.45 * sin(phase * 2.4 + Double(i) * 0.6)
                    Circle()
                        .fill(color)
                        .frame(width: 9, height: 9)
                        .opacity(0.55 + 0.45 * pulse)
                        .scaleEffect(0.85 + 0.15 * pulse)
                }
            }
        }
    }
}

// MARK: - Полноширинный силуэт Астаны

struct AstanaSkylineFull: Shape {
    var seed: Int = 0

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let baseY = rect.maxY - rect.height * 0.04

        let towers: [(x: CGFloat, w: CGFloat, h: CGFloat, hasSpire: Bool)] = seed == 0
            ? [
                (0.18, 0.045, 0.55, true),
                (0.24, 0.055, 0.42, false),
                (0.32, 0.040, 0.62, true),
                (0.40, 0.060, 0.48, false),
                (0.50, 0.050, 0.70, true),
                (0.60, 0.045, 0.40, false),
                (0.68, 0.055, 0.58, true),
                (0.78, 0.040, 0.46, false),
                (0.86, 0.050, 0.66, true),
                (0.93, 0.040, 0.50, false),
            ]
            : [
                (0.21, 0.060, 0.34, false),
                (0.29, 0.050, 0.50, true),
                (0.37, 0.065, 0.30, false),
                (0.46, 0.045, 0.56, true),
                (0.55, 0.060, 0.36, false),
                (0.64, 0.055, 0.50, true),
                (0.73, 0.050, 0.40, false),
                (0.82, 0.060, 0.54, true),
                (0.90, 0.045, 0.36, false),
            ]

        for t in towers {
            let w = rect.width * t.w
            let h = rect.height * t.h
            let x = rect.minX + rect.width * t.x
            p.addRect(CGRect(x: x, y: baseY - h, width: w, height: h))
            if t.hasSpire {
                p.move(to: CGPoint(x: x + w / 2, y: baseY - h))
                p.addLine(to: CGPoint(x: x + w / 2, y: baseY - h - rect.height * 0.18))
            }
        }

        if seed == 0 {
            let dx = rect.minX + rect.width * 0.55
            let dw = rect.width * 0.07
            let dh = rect.height * 0.34
            let dy = baseY - dh
            p.addRect(CGRect(x: dx, y: dy + dh * 0.45, width: dw, height: dh * 0.55))
            p.addEllipse(in: CGRect(x: dx - dw * 0.10, y: dy, width: dw * 1.20, height: dh * 0.70))
            p.move(to: CGPoint(x: dx + dw / 2, y: dy))
            p.addLine(to: CGPoint(x: dx + dw / 2, y: dy - rect.height * 0.10))
        }

        return p
    }
}

// MARK: - Полноширинный силуэт гор Алматы

struct AlmatyRangeFull: Shape {
    var seed: Int = 0

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let baseY = rect.maxY - rect.height * 0.04

        let peaks: [(CGFloat, CGFloat)] = seed == 0
            ? [(0.00, 0.00), (0.08, 0.45), (0.18, 0.20), (0.28, 0.55), (0.40, 0.30),
               (0.52, 0.62), (0.62, 0.32), (0.74, 0.58), (0.86, 0.28), (0.96, 0.50), (1.00, 0.20)]
            : [(0.00, 0.30), (0.10, 0.62), (0.22, 0.40), (0.34, 0.72), (0.46, 0.46),
               (0.58, 0.78), (0.70, 0.48), (0.82, 0.70), (0.92, 0.42), (1.00, 0.55)]

        p.move(to: CGPoint(x: rect.minX, y: baseY))
        for (rx, ry) in peaks {
            let x = rect.minX + rect.width * rx
            let y = rect.minY + rect.height * (1.0 - ry)
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: baseY))
        p.closeSubpath()

        for (rx, ry) in peaks where ry > 0.5 {
            let cx = rect.minX + rect.width * rx
            let cy = rect.minY + rect.height * (1.0 - ry)
            p.move(to: CGPoint(x: cx - rect.width * 0.018, y: cy + rect.height * 0.07))
            p.addLine(to: CGPoint(x: cx, y: cy))
            p.addLine(to: CGPoint(x: cx + rect.width * 0.018, y: cy + rect.height * 0.07))
            p.closeSubpath()
        }

        return p
    }
}

// MARK: - Иконка Байтерек

struct BaiterekIconV2: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX
        let baseY = rect.maxY - rect.height * 0.04
        let topSpireY = rect.minY + rect.height * 0.04
        let sphereR = rect.width * 0.22
        let sphereCY = rect.minY + rect.height * 0.26

        p.addEllipse(in: CGRect(
            x: cx - sphereR, y: sphereCY - sphereR,
            width: sphereR * 2, height: sphereR * 2
        ))

        p.move(to: CGPoint(x: cx, y: topSpireY))
        p.addLine(to: CGPoint(x: cx, y: baseY))

        let waistTop = sphereCY + sphereR
        for sign in [CGFloat(-1), CGFloat(1)] {
            p.move(to: CGPoint(x: cx + sign * rect.width * 0.05, y: waistTop))
            p.addCurve(
                to: CGPoint(x: cx + sign * rect.width * 0.30, y: baseY),
                control1: CGPoint(x: cx + sign * rect.width * 0.22, y: rect.minY + rect.height * 0.55),
                control2: CGPoint(x: cx + sign * rect.width * 0.10, y: rect.minY + rect.height * 0.78)
            )
        }

        for ry in [0.55, 0.72, 0.88] as [CGFloat] {
            let y = rect.minY + rect.height * ry
            let halfW = rect.width * 0.30
            p.move(to: CGPoint(x: cx - halfW * 0.7, y: y))
            p.addLine(to: CGPoint(x: cx + halfW * 0.7, y: y))
        }

        p.move(to: CGPoint(x: cx - rect.width * 0.36, y: baseY))
        p.addLine(to: CGPoint(x: cx + rect.width * 0.36, y: baseY))

        return p
    }
}

// MARK: - Кок-Тобе

struct KokTobeIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX
        let baseY = rect.maxY - rect.height * 0.04
        let topY  = rect.minY + rect.height * 0.04

        p.addRect(CGRect(x: cx - rect.width * 0.025,
                         y: rect.minY + rect.height * 0.18,
                         width: rect.width * 0.05,
                         height: baseY - (rect.minY + rect.height * 0.18)))

        p.addRect(CGRect(x: cx - rect.width * 0.008,
                         y: topY,
                         width: rect.width * 0.016,
                         height: rect.height * 0.18))

        p.addEllipse(in: CGRect(x: cx - rect.width * 0.10,
                                y: rect.minY + rect.height * 0.36,
                                width: rect.width * 0.20,
                                height: rect.height * 0.10))

        p.move(to: CGPoint(x: cx - rect.width * 0.15, y: baseY))
        p.addLine(to: CGPoint(x: cx, y: rect.minY + rect.height * 0.50))
        p.addLine(to: CGPoint(x: cx + rect.width * 0.15, y: baseY))
        p.closeSubpath()

        return p
    }
}

// MARK: - Превью

#Preview {
    VStack(spacing: 24) {
        CityPillOverlay(style: .astana)
        CityPillOverlay(style: .almaty, isPaused: true)
    }
    .padding(40)
    .background(Color.black)
}
