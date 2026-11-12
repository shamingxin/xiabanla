import SwiftUI
import AppKit



/// 卡片配色：黑色背景和图片背景用浅色字，白色背景用深色字
/// 「公司倒欠你」固定用同一个绿色，不随背景变化
struct CardPalette {
    var digit: Color
    var label: Color
    var faint: Color
    /// 数字牌：半透明，透出背后的毛玻璃
    var tile: Color
    /// 进度条底轨
    var track: Color
    var hover: Color
    let overtime = Color(red: 0.30, green: 0.78, blue: 0.40)

    static let dark = CardPalette(digit: Color(white: 0.93),
                                  label: Color.white.opacity(0.75),
                                  faint: Color.white.opacity(0.66),
                                  tile: Color.black.opacity(0.32),
                                  track: Color.black.opacity(0.32),
                                  hover: Color.white.opacity(0.14))

    static let light = CardPalette(digit: Color(white: 0.12),
                                   label: Color.black.opacity(0.70),
                                   faint: Color.black.opacity(0.55),
                                   tile: Color.black.opacity(0.06),
                                   track: Color.black.opacity(0.10),
                                   hover: Color.black.opacity(0.08))
}

private struct CardPaletteKey: EnvironmentKey {
    static let defaultValue = CardPalette.dark
}

extension EnvironmentValues {
    var cardPalette: CardPalette {
        get { self[CardPaletteKey.self] }
        set { self[CardPaletteKey.self] = newValue }
    }
}

/// 布局尺寸
enum Metrics {
    static let tileSize: CGFloat = 88
    static let tileGap: CGFloat = 12
    static let tileRadius: CGFloat = 12
    /// 数字牌上下两半之间的缝隙，透出背景
    static let splitGap: CGFloat = 2
    static let digitFontSize: CGFloat = 76
    static let horizontalPadding: CGFloat = 24
    static let verticalPadding: CGFloat = 28
}

/// 卡片上可触发的操作，由 AppDelegate 提供
struct CardActions {
    var openSettings: () -> Void = {}
    var showWindow: () -> Void = {}
    /// 只有桌面小窗才有关闭/最小化；为 nil 时不显示红黄绿按钮
    var closeWindow: (() -> Void)? = nil
    var minimizeWindow: (() -> Void)? = nil
    var quit: () -> Void = { NSApp.terminate(nil) }
}

/// 倒计时主视图
/// - 未开始：数字牌显示 --，下方「开始上班」按钮 + 补填到岗时间入口
/// - 倒计时中：时/分/秒三块翻页数字牌 + 进度条 + 到岗/下班时间
/// - 已下班：红色正向计时「已下班，公司倒欠你」+ 超过 100% 的冲击进度条
struct CountdownCardView: View {
    @ObservedObject var model: WorkTimerModel
    @Environment(\.cardPalette) var palette
    var actions = CardActions()

    private var digitColor: Color {
        model.isOffWork ? palette.overtime : palette.digit
    }

    /// 时、分、秒三段文字
    private var parts: (String, String, String) {
        if model.isResting || model.isWaitingForUnlock || !model.hasStarted { return ("--", "--", "--") }
        let s = model.isOffWork ? model.overtimeSeconds : model.remainingSeconds
        return (String(format: "%02d", s / 3600),
                String(format: "%02d", (s % 3600) / 60),
                String(format: "%02d", s % 60))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 14) {
                if let close = actions.closeWindow {
                    WindowControls(close: close, minimize: actions.minimizeWindow)
                }
                header
            }
            Group {
                switch model.countdownStyle {
                case .flip:
                    HStack(spacing: Metrics.tileGap) {
                        FlipTile(value: parts.0, color: digitColor, label: "小时")
                        FlipTile(value: parts.1, color: digitColor, label: "分钟")
                        FlipTile(value: parts.2, color: digitColor, label: "秒")
                    }
                case .dynamicIsland:
                    HStack(spacing: 0) {
                        BounceDigitGroup(value: parts.0, color: digitColor, label: "小时")
                        colonSeparator
                        BounceDigitGroup(value: parts.1, color: digitColor, label: "分钟")
                        colonSeparator
                        BounceDigitGroup(value: parts.2, color: digitColor, label: "秒")
                    }
                case .standbyClock:
                    HStack(spacing: 0) {
                        StandbyDigitGroup(value: parts.0, groupIndex: 0, color: digitColor,
                                          isOvertime: model.isOffWork, label: "小时")
                            .zIndex(0)
                        StandbyColonSeparator(color: digitColor, isOvertime: model.isOffWork)
                            .zIndex(10)
                        StandbyDigitGroup(value: parts.1, groupIndex: 1, color: digitColor,
                                          isOvertime: model.isOffWork, label: "分钟")
                            .zIndex(0)
                        StandbyColonSeparator(color: digitColor, isOvertime: model.isOffWork)
                            .zIndex(10)
                        StandbyDigitGroup(value: parts.2, groupIndex: 2, color: digitColor,
                                          isOvertime: model.isOffWork, label: "秒")
                            .zIndex(0)
                    }
                    .offset(y: -7)
                }
            }
            if model.isResting || model.isWaitingForUnlock {
                Text(model.isWaitingForUnlock ? "休息中，等待下一次有效解锁" : "下一工作日将在凌晨 5:00 开始").font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.faint).frame(maxWidth: .infinity, minHeight: 48)
            } else if model.hasStarted {
                progressFooter
            } else {
                startFooter
            }
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .padding(.top, actions.closeWindow != nil ? 16 : Metrics.verticalPadding)
        .padding(.bottom, Metrics.verticalPadding)
        .fixedSize()
        .animation(.easeInOut(duration: 0.3), value: model.isOffWork)
        .contextMenu {
            Button("设置…", action: actions.openSettings)
            Button("显示桌面小窗", action: actions.showWindow)
            if let close = actions.closeWindow {
                Button("关闭桌面小窗", action: close)
            }
            Divider()
            Button("退出下班啦", action: actions.quit)
        }
    }

    /// 灵动岛风格两组数字间的圆点分隔符
    /// 宽度固定等于 Metrics.tileGap，和翻页样式的数字牌间距相同，两种样式总宽度保持一致
    private var colonSeparator: some View {
        VStack(spacing: Metrics.tileSize * 0.22) {
            Circle().fill(digitColor.opacity(0.8)).frame(width: 6, height: 6)
            Circle().fill(digitColor.opacity(0.8)).frame(width: 6, height: 6)
        }
        .frame(width: Metrics.tileGap, height: Metrics.tileSize)
    }

    // MARK: - 顶部：状态文字 + 右上角设置

    private var header: some View {
        HStack(spacing: 8) {
            if model.isResting || model.isWaitingForUnlock {
                Image(systemName: "moon.zzz.fill").foregroundStyle(palette.faint)
                Text(model.isWaitingForUnlock ? "休息中，等待解锁" : "休息中").foregroundStyle(palette.label)
            } else if model.isOffWork {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(palette.overtime)
                Text("已下班，公司倒欠你")
                    .foregroundStyle(palette.overtime)
            } else {
                Image(systemName: "clock")
                    .foregroundStyle(palette.label)
                Text(model.hasStarted ? "距离下班" : "还没开始上班")
                    .foregroundStyle(palette.label)
            }
            Spacer()
            SettingsGearButton(action: actions.openSettings)
        }
        .font(.system(size: 14, weight: .medium))
    }

    // MARK: - 底部：未开始

    private var startFooter: some View {
        VStack(spacing: 12) {
            Button(action: { model.startWork() }) {
                Text("开始上班")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(palette.digit)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(palette.digit, lineWidth: 1.5)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                Text("忘了点？").foregroundStyle(palette.faint)
                Button("补填今天的到岗时间", action: actions.openSettings)
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.label)
                    .underline()
            }
            .font(.system(size: 12, weight: .medium))
        }
    }

    // MARK: - 底部：进度条 + 到岗/下班时间 + 百分比

    private var progressFooter: some View {
        let percent = Int(model.progress * 100)
        let tint = model.isOffWork ? palette.overtime : palette.faint
        return VStack(spacing: 12) {
            Group {
                if model.isOffWork {
                    OvertimeBar()
                } else {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(palette.track)
                            Capsule().fill(palette.digit)
                                .frame(width: max(4, geo.size.width * min(1, model.progress)))
                        }
                    }
                }
            }
            .frame(height: 4)
            .accessibilityElement()
            .accessibilityLabel("今日进度")
            .accessibilityValue("\(percent)%")

            HStack {
                Text(footerText).foregroundStyle(palette.faint)
                Spacer()
                Text("\(percent)%").foregroundStyle(tint)
            }
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()
        }
    }

    /// 「09:44 到 · 19:00 下班」；固定模式没填到岗时显示「10:00 上班 · 19:00 下班」
    private var footerText: String {
        if model.hasArrived { return "\(model.startTimeText) 到 · \(model.endTimeText) 下班" }
        return "\(model.ruleStartText) 上班 · \(model.endTimeText) 下班"
    }
}

/// 下班后的红色进度条：满格红条上，亮光一波波从左往右冲过去，整体轻微呼吸
/// 系统开启「减弱动态效果」时只显示静态红条
struct OvertimeBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cardPalette) var palette
    private static let period = 1.1

    var body: some View {
        if reduceMotion {
            Capsule().fill(palette.overtime)
        } else {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = (t / Self.period).truncatingRemainder(dividingBy: 1)
                let pulse = 0.82 + 0.18 * sin(t * 2 * .pi / Self.period)
                GeometryReader { geo in
                    let w = geo.size.width
                    let glow = w * 0.28
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.overtime.opacity(pulse))
                        // 冲击光：一段渐亮的高光，从左侧外面冲到右侧外面
                        LinearGradient(colors: [.clear, .white.opacity(0.85), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: glow)
                            .offset(x: -glow + (w + glow) * phase)
                    }
                    .clipShape(Capsule())
                    .shadow(color: palette.overtime.opacity(0.6 * pulse), radius: 4)
                }
            }
        }
    }
}

/// 左上角红黄绿按钮（仿 macOS 窗口按钮）：悬停时显示 × 和 − 符号
/// 小窗尺寸固定，不需要全屏按钮，只保留关闭和最小化
struct WindowControls: View {
    let close: () -> Void
    let minimize: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            TrafficLight(color: Color(red: 1.0, green: 0.373, blue: 0.341),
                         symbol: "xmark", showsSymbol: hovering, action: close)
                .accessibilityLabel("关闭")
            TrafficLight(color: Color(red: 0.996, green: 0.737, blue: 0.180),
                         symbol: "minus", showsSymbol: hovering, action: minimize ?? {})
                .accessibilityLabel("最小化")
        }
        .onHover { hovering = $0 }
    }
}

struct TrafficLight: View {
    let color: Color
    let symbol: String
    let showsSymbol: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(color)
                Circle().strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5)
                if showsSymbol {
                    Image(systemName: symbol)
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(Color.black.opacity(0.55))
                }
            }
            .frame(width: 12, height: 12)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// 右上角设置按钮：悬停时图标变亮 + 浅色圆角底 + 手形光标
struct SettingsGearButton: View {
    let action: () -> Void
    @Environment(\.cardPalette) var palette
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(hovering ? palette.digit : palette.label)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hovering ? palette.hover : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help("设置工作时长、今天几点到")
        .accessibilityLabel("设置")
    }
}

/// 数字牌一面：可选半透明牌面 + 按数字实际高度居中绘制的数字
/// DIN Condensed 的上下留白不对称，用 Core Text 按大写高度（数字高度）定位基线，保证视觉居中
struct DigitFace: View {
    let value: String
    @Environment(\.cardPalette) var palette
    let color: Color
    var showsTile = true
    var showsDigits = true

    var body: some View {
        Canvas { ctx, size in
            if showsTile {
                ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size),
                              cornerRadius: Metrics.tileRadius, style: .continuous),
                         with: .color(palette.tile))
            }
            guard showsDigits else { return }
            ctx.withCGContext { cg in
                let font = NSFont(name: "DINCondensed-Bold", size: Metrics.digitFontSize)
                    ?? NSFont.monospacedDigitSystemFont(ofSize: Metrics.digitFontSize * 0.8, weight: .bold)
                let text = NSAttributedString(string: value, attributes: [
                    .font: font,
                    .foregroundColor: NSColor(color),
                ])
                let line = CTLineCreateWithAttributedString(text)
                let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                // 当前坐标系 y 轴向下，翻转文字矩阵让字形正向绘制
                cg.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
                cg.textPosition = CGPoint(x: (size.width - width) / 2,
                                          y: (size.height + font.capHeight) / 2)
                CTLineDraw(line, cg)
            }
        }
        .frame(width: Metrics.tileSize, height: Metrics.tileSize)
    }
}

/// 翻页数字牌：数字变化时，旧数字上半片向下翻倒，新数字下半片随后落下
///
/// 牌面是半透明的，翻片会透出下面的数字，所以底层数字随翻片角度淡入/淡出：
/// - 上半：底层新数字从透明淡入，翻片（旧数字）倒下
/// - 下半：翻片（新数字）落下，底层旧数字淡出
struct FlipTile: View {
    let value: String
    let color: Color
    let label: String

    @State private var current: String
    @State private var previous: String
    @State private var flipping = false
    /// 上半翻片角度：0 → -90
    @State private var topAngle: Double = 0
    /// 下半翻片角度：90 → 0
    @State private var bottomAngle: Double = 0

    private static let topDuration = 0.18
    private static let bottomDuration = 0.22

    init(value: String, color: Color, label: String) {
        self.value = value
        self.color = color
        self.label = label
        _current = State(initialValue: value)
        _previous = State(initialValue: value)
    }

    var body: some View {
        VStack(spacing: Metrics.splitGap) {
            ZStack {
                half(top: true) { DigitFace(value: "", color: color, showsDigits: false) }
                half(top: true) { DigitFace(value: current, color: color, showsTile: false) }
                    .opacity(flipping ? -topAngle / 90 : 1)
                half(top: true) { DigitFace(value: previous, color: color) }
                    .brightness(topAngle / 90 * 0.25)
                    .rotation3DEffect(.degrees(topAngle), axis: (x: 1, y: 0, z: 0),
                                      anchor: .bottom, perspective: 0.5)
                    .opacity(flipping ? 1 : 0)
            }
            .zIndex(1)
            ZStack {
                half(top: false) { DigitFace(value: "", color: color, showsDigits: false) }
                half(top: false) { DigitFace(value: previous, color: color, showsTile: false) }
                    .opacity(flipping ? bottomAngle / 90 : 1)
                half(top: false) { DigitFace(value: current, color: color) }
                    .brightness(-bottomAngle / 90 * 0.25)
                    .rotation3DEffect(.degrees(bottomAngle), axis: (x: 1, y: 0, z: 0),
                                      anchor: .top, perspective: 0.5)
                    .opacity(flipping ? 1 : 0)
            }
        }
        .onChange(of: value) { newValue in flip(to: newValue) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }

    /// 截取数字牌的上半或下半，中间留出缝隙
    private func half<V: View>(top: Bool, @ViewBuilder _ content: () -> V) -> some View {
        content()
            .frame(width: Metrics.tileSize,
                   height: Metrics.tileSize / 2 - Metrics.splitGap / 2,
                   alignment: top ? .top : .bottom)
            .clipped()
    }

    private func flip(to newValue: String) {
        guard newValue != current else { return }
        var instant = Transaction()
        instant.disablesAnimations = true

        // 准备：旧数字翻片立在上半，新数字翻片竖起藏在下半
        withTransaction(instant) {
            previous = current
            current = newValue
            topAngle = 0
            bottomAngle = 90
            flipping = true
        }

        // 第一段：旧数字上半片翻倒
        withAnimation(.easeIn(duration: Self.topDuration)) { topAngle = -90 }

        // 第二段：新数字下半片落下
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.topDuration) {
            withAnimation(.easeOut(duration: Self.bottomDuration)) { bottomAngle = 0 }
        }

        // 结束：复位，静止状态上下都显示新数字
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.topDuration + Self.bottomDuration) {
            guard current == newValue else { return }
            withTransaction(instant) {
                previous = current
                topAngle = 0
                flipping = false
            }
        }
    }
}

/// 灵动岛风格数字组：粗体无衬线裸数字，数字变化时果冻式弹跳，不显示时/分/秒标签
/// 用 spring 动画模拟灵动岛的弹性手感：数字先微微放大上弹，再回落，不做翻页卡片背景
/// 宽高对齐 Metrics.tileSize，和翻页样式的 FlipTile 保持同样的占位尺寸，切换样式时卡片整体宽度不变
struct BounceDigitGroup: View {
    let value: String
    let color: Color
    let label: String

    @State private var bounce = false

    var body: some View {
        Text(value)
            .font(.system(size: Metrics.digitFontSize * 0.78, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .scaleEffect(bounce ? 1.12 : 1)
            .offset(y: bounce ? -4 : 0)
            .frame(width: Metrics.tileSize, height: Metrics.tileSize, alignment: .center)
            .onChange(of: value) { _ in bounceOnce() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(value) \(label)")
    }

    /// 弹起再回落：弹起快、回落稍慢，接近灵动岛的果冻感
    private func bounceOnce() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) {
            bounce = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) {
                bounce = false
            }
        }
    }
}

/// 仿 iPhone 待机显示的大数字：每组十位深蓝、个位浅蓝，靠负间距形成宽厚的双色构图。
/// 只有值变化的短暂过程中才同时显示旧/新值；静止时绝不保留同字阴影。
struct StandbyDigitGroup: View {
    let value: String
    /// 时/分/秒三组分别是 0/1/2，用来给六个视觉位置分配不重复的姿态。
    let groupIndex: Int
    let color: Color
    let isOvertime: Bool
    let label: String

    @State private var displayedValue: String
    @State private var outgoingValue: String?
    @State private var progress: CGFloat
    @State private var impactScale = CGSize(width: 1, height: 1)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let travel: CGFloat = 17

    init(value: String, groupIndex: Int, color: Color, isOvertime: Bool, label: String) {
        self.value = value
        self.groupIndex = groupIndex
        self.color = color
        self.isOvertime = isOvertime
        self.label = label
        _displayedValue = State(initialValue: value)
        _progress = State(initialValue: 1)
    }

    var body: some View {
        ZStack {
            if let outgoingValue {
                digitLayers(outgoingValue, outgoing: true)
            }

            digitLayers(displayedValue, outgoing: false)
        }
        .frame(width: StandbyClockMetrics.pairWidth, height: Metrics.tileSize)
        // 只在数值更新瞬间做一次短促的压缩—回弹，让秒级变化有「duang」的重量感。
        .scaleEffect(x: impactScale.width, y: impactScale.height)
        .onChange(of: value) { transition(to: $0) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }

    private func digitLayers(_ digits: String, outgoing: Bool) -> some View {
        let amount = outgoing ? progress : 1 - progress
        // 新值从下方顶上来，旧值向上离开；方向和参考待机钟的数字推进一致。
        let direction: CGFloat = outgoing ? -1 : 1
        let y = direction * Self.travel * amount
        let opacity = outgoing ? 1 - progress : 0.58 + 0.42 * progress

        return pairDigits(digits)
            .offset(y: y)
            .opacity(opacity)
            .animation(.easeOut(duration: 0.40), value: progress)
    }

    private func pairDigits(_ digits: String) -> some View {
        let characters = Array(digits)
        let tens = characters.indices.contains(0) ? String(characters[0]) : "–"
        let ones = characters.indices.contains(1) ? String(characters[1]) : "–"
        return HStack(spacing: -24) {
            displayText(tens, color: tensColor, position: groupIndex * 2)
            displayText(ones, color: onesColor, position: groupIndex * 2 + 1)
        }
    }

    private func displayText(_ digit: String, color: Color, position: Int) -> some View {
        Text(digit)
            .font(.system(size: Metrics.digitFontSize * 1.24, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .scaleEffect(x: 1.08, y: 1.09, anchor: .center)
            // 六个位置允许有不同倾角，但必须共用同一条视觉基线，不能做波浪式上下错位。
            .rotationEffect(.degrees(tilt(at: position)))
    }

    /// 六个位置各有固定且不重复的倾角；不依赖数字内容，重复数字也不会摆出相同姿势。
    private func tilt(at position: Int) -> Double {
        let tilts: [Double] = [4.2, -6.4, 1.3, -2.5, 5.1, -3.6]
        return tilts[position % tilts.count]
    }

    private var tensColor: Color {
        isOvertime ? color.opacity(0.72) : Color(red: 0.00, green: 0.33, blue: 0.73).opacity(0.86)
    }

    private var onesColor: Color {
        isOvertime ? color.opacity(0.90) : Color(red: 0.34, green: 0.66, blue: 0.94).opacity(0.86)
    }

    private func transition(to newValue: String) {
        guard newValue != displayedValue else { return }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            outgoingValue = displayedValue
            displayedValue = newValue
            progress = 0
        }
        guard !reduceMotion else {
            withTransaction(instant) { progress = 1 }
            return
        }
        withAnimation(.easeOut(duration: 0.40)) {
            progress = 1
        }

        withAnimation(.easeOut(duration: 0.09)) {
            impactScale = CGSize(width: 0.94, height: 1.08)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
            guard displayedValue == newValue else { return }
            withAnimation(.interpolatingSpring(stiffness: 360, damping: 20)) {
                impactScale = CGSize(width: 1, height: 1)
            }
        }
    }
}

/// 待机时钟的冒号：两个较大的独立圆点使用柔和的白灰渐变，已下班时跟随绿色状态。
struct StandbyColonSeparator: View {
    let color: Color
    let isOvertime: Bool

    var body: some View {
        VStack(spacing: Metrics.tileSize * 0.18) {
            dot
            dot
        }
        .frame(width: StandbyClockMetrics.colonWidth, height: Metrics.tileSize)
        .accessibilityHidden(true)
    }

    private var dot: some View {
        Circle()
            .fill(LinearGradient(colors: dotColors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 17, height: 17)
    }

    private var dotColors: [Color] {
        isOvertime
            ? [color.opacity(0.98), color.opacity(0.55)]
            : [Color.white.opacity(0.96), Color(white: 0.62).opacity(0.86)]
    }
}

/// 三组总宽度与翻页/灵动岛一致：缩小每一对的布局槽位，把空间让给两个冒号区。
/// 这样 HH、MM、SS 各自更亲密，而组间仍有清楚的呼吸感。
private enum StandbyClockMetrics {
    static let pairWidth: CGFloat = 80
    static let colonWidth: CGFloat = 24
}
