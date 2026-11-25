import SwiftUI

private struct WaterSurface: Shape {
    var level: Double
    let phase: Double

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard level > 0 else { return Path() }
        let baseline = rect.height * (0.995 - 0.89 * level)
        let amplitude = min(2.8, level * rect.height * 0.45)
        return Path { path in
            path.move(to: CGPoint(x: 0, y: rect.maxY))
            for i in 0...32 {
                let fraction = Double(i) / 32
                let y = baseline + amplitude * sin(fraction * 2 * .pi + phase)
                path.addLine(to: CGPoint(x: rect.width * fraction, y: y))
            }
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

enum WaterVessel {
    case glass, bucket, jar, kirby

    init(dailyGoal: Int) {
        switch dailyGoal {
        case ..<2000: self = .glass
        case ..<3000: self = .bucket
        case ..<4500: self = .jar
        default: self = .kirby
        }
    }

    /// 液体、刻度及百分比共用同一局部坐标系。卡比的进度单独显示在角色下方。
    fileprivate var bodyRect: CGRect {
        switch self {
        case .kirby: return CGRect(x: 26, y: 88, width: 60, height: 21)
        case .glass: return Self.containerRect(width: 76)
        case .bucket: return Self.containerRect(width: 92)
        case .jar: return Self.containerRect(width: 110)
        }
    }

    private static func containerRect(width: CGFloat) -> CGRect {
        CGRect(x: (112 - width) / 2, y: 0, width: width, height: 110)
    }
}

private struct VesselOutline: Shape {
    let kind: WaterVessel

    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        if kind == .kirby { return Capsule().path(in: rect) }
        return Path { p in
            if kind == .jar {
                p.move(to: point(0.20, 0.05))
                p.addQuadCurve(to: point(0.80, 0.05), control: point(0.5, -0.035))
                p.addQuadCurve(to: point(0.86, 0.23), control: point(0.74, 0.14))
                p.addCurve(to: point(0.80, 0.94), control1: point(1.05, 0.42), control2: point(1.02, 0.77))
                p.addQuadCurve(to: point(0.20, 0.94), control: point(0.5, 1.04))
                p.addCurve(to: point(0.14, 0.23), control1: point(-0.02, 0.77), control2: point(-0.05, 0.42))
                p.addQuadCurve(to: point(0.20, 0.05), control: point(0.26, 0.14))
            } else {
                let inset: CGFloat = kind == .glass ? 0.10 : 0.16
                p.move(to: point(0, 0.05))
                p.addQuadCurve(to: point(1, 0.05), control: point(0.5, -0.035))
                p.addLine(to: point(1 - inset, 0.90))
                p.addQuadCurve(to: point(0.80, 0.97), control: point(1 - inset, 0.96))
                p.addQuadCurve(to: point(0.20, 0.97), control: point(0.5, 1.01))
                p.addQuadCurve(to: point(inset, 0.90), control: point(inset, 0.96))
            }
            p.closeSubpath()
        }
    }
}

struct WaterVesselView: View {
    let kind: WaterVessel
    let progress: Double
    let moving: Bool
    let percentage: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.colorScheme) private var scheme

    private var blue: Color { AccentPreset.systemBlue }
    private var edge: Color { scheme == .dark ? .white.opacity(0.55) : blue.opacity(0.50) }
    private var outline: VesselOutline { VesselOutline(kind: kind) }

    var body: some View {
        let rect = kind.bodyRect
        ZStack(alignment: .topLeading) {
            if kind == .kirby {
                KirbyAnimation(playing: moving && !reduceMotion && activeState != .inactive)
                    .frame(width: 112, height: 86)
                    .accessibilityHidden(true)
            }
            ZStack {
                outline.fill(LinearGradient(colors: [blue.opacity(0.22), blue.opacity(0.04), blue.opacity(0.16)],
                                            startPoint: .leading, endPoint: .trailing))
                waves.clipShape(outline)
                if kind != .kirby { markings.clipShape(outline) }
                outline.stroke(edge, lineWidth: 0.85)
                if kind != .kirby {
                    Ellipse().fill(Color.white.opacity(0.08))
                        .overlay(Ellipse().stroke(edge, lineWidth: 0.85))
                        .frame(width: rect.width * (kind == .jar ? 0.62 : 1), height: 8)
                        .position(x: rect.width / 2, y: rect.height * 0.05)
                }
                if let percentage {
                    Text("\(percentage)%")
                        .font(.system(size: kind == .kirby ? 13 : 16, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(progress >= 0.48 || scheme == .dark ? Color.white : .primary)
                        .shadow(color: progress >= 0.48 ? .black.opacity(0.40) : .clear, radius: 2)
                }
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
        }
        .frame(width: 112, height: 110)
    }

    private var waves: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || !moving || progress == 0 || activeState == .inactive)) { context in
            let phase = reduceMotion || !moving ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 5) * 2 * .pi / 5
            ZStack {
                WaterSurface(level: progress, phase: phase + 2.3).fill(Color.cyan.opacity(0.65))
                WaterSurface(level: progress, phase: phase)
                    .fill(LinearGradient(colors: [.cyan, blue], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: progress)
        }
    }

    private var markings: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            var ticks = Path()
            for index in 1...5 {
                let y = h * CGFloat(index + 1) / 8
                let x = w * 0.84
                ticks.move(to: CGPoint(x: x, y: y))
                ticks.addLine(to: CGPoint(x: x - (index.isMultiple(of: 2) ? 4 : 6), y: y))
            }
            context.stroke(ticks, with: .color(edge), lineWidth: 1)
        }
    }
}

private struct KirbyAnimation: NSViewRepresentable {
    let playing: Bool

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        if let url = Bundle.main.url(forResource: "Kirby", withExtension: "gif") {
            view.image = NSImage(contentsOf: url)
        }
        return view
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        view.animates = playing
    }
}
