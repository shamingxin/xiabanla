import SwiftUI
import AppKit

/// 「今日工作」设备面板：设置里改得最频繁的一块，做成实体计时器的样子和下面的列表拉开差异
/// - 左：黑色屏幕，DIN Condensed 大号到岗时间，底部一行「下班 19:00」
/// - 右：灰色机身。已到岗放胶囊上下键；未到岗放橙色 ✓（现在开始）+「补填」
/// - 点选屏幕上的小时 / 分钟可直接键盘输入，↑↓ 调整；上下键默认调分钟，选中小时后调小时
struct TodayPanel: View {
    @ObservedObject var model: WorkTimerModel
    /// 「补填」时先填入的时间
    let arrivalGuess: () -> Date
    @StateObject private var edit = TimeEditState()
    @Environment(\.colorScheme) private var scheme
    private var p: TodayPalette { .of(scheme) }

    var body: some View {
        HStack(spacing: 14) {
            screen
            controls
                .frame(width: 48)
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .padding(.vertical, 12)
        .frame(height: TodayStyle.height)
        .background(shell)
    }

    // MARK: - 屏幕

    /// 参考点阵屏的亲密度：
    /// - 「到岗时间」紧贴大号数字成一组（间距 6），是屏幕的主信息
    /// - 下班时间单独放进底部虚线胶囊，和主信息拉开距离，层级更低
    private var screen: some View {
        VStack(spacing: TodayStyle.groupGap) {
            VStack(spacing: 6) {
                Text("上班时间")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(p.dim)

                if model.hasArrived, let start = model.todayStartTime {
                    ArrivalTimeField(date: start,
                                     minDate: Calendar.current.startOfDay(for: Date()),
                                     maxDate: Date(),
                                     palette: p,
                                     state: edit,
                                     onCommit: { model.setStartTime($0) })
                        .frame(height: TodayStyle.digitBox)
                } else {
                    DotMatrixText(text: "--:--", color: p.dim)
                        .frame(maxWidth: .infinity)
                        .frame(height: TodayStyle.digitBox)
                        .accessibilityLabel("到岗时间未记录")
                }
            }

            Group {
                if model.hasArrived {
                    HStack(spacing: 6) {
                        Text(model.endTimeText).foregroundStyle(p.accent)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                        Text("下班").foregroundStyle(p.dim)
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    Text("按 ✓ 开始上班").foregroundStyle(p.dim)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .overlay(Capsule().stroke(p.accent.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [1.5, 2])))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(p.screen)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(p.screenStroke, lineWidth: 1))
        )
    }

    // MARK: - 机身按钮

    @ViewBuilder
    private var controls: some View {
        if model.hasArrived {
            CapsuleStepper(palette: p, up: { step(+1) }, down: { step(-1) })
        } else {
            VStack(spacing: 10) {
                Button(action: model.startWork) { EmptyView() }
                    .buttonStyle(ConfirmKeyStyle(palette: p))
                    .accessibilityLabel("现在开始上班")
                Button("补填") { model.setStartTime(arrivalGuess()) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(p.engrave)
                    .accessibilityLabel("补填到岗时间")
            }
        }
    }

    private func step(_ delta: Int) {
        guard let start = model.todayStartTime else { return }
        model.setStartTime(TimeMath.step(start, segment: edit.segment, by: delta,
                                         min: Calendar.current.startOfDay(for: Date()), max: Date()))
    }

    // MARK: - 机身外壳

    private var shell: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: [p.shellTop, p.shellBottom],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(
                // 顶边一道高光，底边一道暗线，做出金属机身的厚度
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [p.rimTop, p.rimBottom],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .shadow(color: p.shadow, radius: 4, y: 2)
    }
}

// MARK: - 样式

enum TodayStyle {
    static let height: CGFloat = 204
    /// 主信息组（到岗时间 + 数字）与下班胶囊之间的距离
    static let groupGap: CGFloat = 28
    static let digitSize: CGFloat = 56
    static let digitBox: CGFloat = 58
}

/// 面板配色：跟设置窗口同一色系（深色 #222120 / 卡片 #2D2B2A），机身只比卡片亮一档
/// 橙色降饱和，只用在下班时间、选中段和 ✓ 键上
struct TodayPalette {
    var shellTop: Color
    var shellBottom: Color
    var rimTop: Color
    var rimBottom: Color
    var shadow: Color
    var screen: Color
    var screenStroke: Color
    var digit: NSColor
    var dim: Color
    var accent: Color
    var nsAccent: NSColor
    var engrave: Color
    var keyTop: Color
    var keyBottom: Color
    var keyPressedTop: Color
    var keyPressedBottom: Color
    var keyArrow: Color
    var keyStroke: Color
    var keyDivider: Color
    var confirmTop: Color
    var confirmBottom: Color

    private static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
    private static let accentHex: UInt32 = 0xD98A68
    private static let nsAccent = NSColor(srgbRed: 0xD9 / 255, green: 0x8A / 255, blue: 0x68 / 255, alpha: 1)

    static let dark = TodayPalette(
        shellTop: hex(0x3A3836), shellBottom: hex(0x33312F),
        rimTop: Color.white.opacity(0.08), rimBottom: Color.black.opacity(0.3),
        shadow: Color.black.opacity(0.25),
        screen: hex(0x171615), screenStroke: Color.black.opacity(0.4),
        digit: NSColor(srgbRed: 0xE6 / 255, green: 0xE3 / 255, blue: 0xDE / 255, alpha: 1),
        dim: hex(0x85817C),
        accent: hex(accentHex), nsAccent: nsAccent,
        engrave: hex(0xA9A49E),
        keyTop: hex(0x5E5B57), keyBottom: hex(0x524F4B),
        keyPressedTop: hex(0x3E3C39), keyPressedBottom: hex(0x383633),
        keyArrow: hex(0xD2CEC8), keyStroke: Color.black.opacity(0.45), keyDivider: Color.black.opacity(0.35),
        confirmTop: hex(0xC9805F), confirmBottom: hex(0xB36E50))

    static let light = TodayPalette(
        shellTop: hex(0xEFEDEA), shellBottom: hex(0xE6E3DF),
        rimTop: Color.white.opacity(0.8), rimBottom: Color.black.opacity(0.08),
        shadow: Color.black.opacity(0.08),
        screen: hex(0x2B2A28), screenStroke: Color.black.opacity(0.15),
        digit: NSColor(srgbRed: 0xEC / 255, green: 0xE9 / 255, blue: 0xE4 / 255, alpha: 1),
        dim: hex(0x8C8984),
        accent: hex(accentHex), nsAccent: nsAccent,
        engrave: hex(0x6E6A64),
        keyTop: hex(0xFFFFFF), keyBottom: hex(0xF2F0ED),
        keyPressedTop: hex(0xE3E0DC), keyPressedBottom: hex(0xDAD7D3),
        keyArrow: hex(0x5A5650), keyStroke: Color.black.opacity(0.12), keyDivider: Color.black.opacity(0.1),
        confirmTop: hex(0xDB9070), confirmBottom: hex(0xC97C5C))

    static func of(_ scheme: ColorScheme) -> TodayPalette { scheme == .light ? .light : .dark }
}

// MARK: - 胶囊上下键

struct CapsuleStepper: View {
    let palette: TodayPalette
    let up: () -> Void
    let down: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: up) { Image(systemName: "chevron.up") }
                .buttonStyle(StepperHalfStyle(palette: palette))
                .accessibilityLabel("加一")
            Rectangle().fill(palette.keyDivider).frame(height: 1)
            Button(action: down) { Image(systemName: "chevron.down") }
                .buttonStyle(StepperHalfStyle(palette: palette))
                .accessibilityLabel("减一")
        }
        .frame(width: 44, height: 92)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(palette.keyStroke, lineWidth: 1))
        .shadow(color: palette.shadow, radius: 2, y: 1)
    }
}

/// 上下键的半边：浅灰渐变，按下变暗、箭头下沉 1pt
struct StepperHalfStyle: ButtonStyle {
    let palette: TodayPalette
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(palette.keyArrow)
            .offset(y: pressed ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LinearGradient(
                colors: pressed ? [palette.keyPressedTop, palette.keyPressedBottom]
                                : [palette.keyTop, palette.keyBottom],
                startPoint: .top, endPoint: .bottom))
            .contentShape(Rectangle())
    }
}

/// 橙色圆形确认键：外圈细虚线 + 对勾，按下缩一点、变暗
struct ConfirmKeyStyle: ButtonStyle {
    let palette: TodayPalette
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return ZStack {
            Circle().fill(LinearGradient(
                colors: [palette.confirmTop, palette.confirmBottom],
                startPoint: .top, endPoint: .bottom))
            Circle().fill(Color.black.opacity(pressed ? 0.12 : 0))
            Circle()
                .inset(by: 5)
                .stroke(Color.black.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [1, 2.5]))
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Color(red: 0.20, green: 0.13, blue: 0.10))
        }
        .frame(width: 44, height: 44)
        .overlay(Circle().strokeBorder(palette.keyStroke, lineWidth: 1))
        .scaleEffect(pressed ? 0.96 : 1)
        .shadow(color: palette.shadow, radius: 2, y: 1)
        .contentShape(Circle())
    }
}

// MARK: - 可点选输入的大号时间

enum TimeSegment { case hour, minute }

/// 当前选中的是小时还是分钟：上下键据此决定调哪一段，默认小时
final class TimeEditState: ObservableObject {
    @Published var segment: TimeSegment = .hour
}

enum TimeMath {
    static func step(_ date: Date, segment: TimeSegment, by delta: Int, min lo: Date?, max hi: Date?) -> Date {
        let unit: TimeInterval = segment == .hour ? 3600 : 60
        return clamp(date.addingTimeInterval(TimeInterval(delta) * unit), lo, hi)
    }

    static func clamp(_ date: Date, _ lo: Date?, _ hi: Date?) -> Date {
        var d = date
        if let lo { d = max(d, lo) }
        if let hi { d = min(d, hi) }
        return d
    }
}

struct ArrivalTimeField: NSViewRepresentable {
    let date: Date
    let minDate: Date?
    let maxDate: Date?
    let palette: TodayPalette
    @ObservedObject var state: TimeEditState
    let onCommit: (Date) -> Void

    func makeNSView(context: Context) -> TimeDisplayView {
        let view = TimeDisplayView()
        view.onSelection = { [weak state] segment in
            DispatchQueue.main.async { state?.segment = segment }
        }
        return view
    }

    func updateNSView(_ view: TimeDisplayView, context: Context) {
        view.minDate = minDate
        view.maxDate = maxDate
        view.onCommit = onCommit
        view.digitColor = palette.digit
        view.accentColor = palette.nsAccent
        view.date = date
    }
}

/// 点阵屏上的「HH:MM」，自己处理点选、数字输入和方向键
/// - 选中段常驻高亮（默认小时），改动实时生效，不需要回车确认
/// - SwiftUI 在 macOS 13 上没有 onKeyPress，NSDatePicker 又拿不到当前选中的是小时还是分钟，所以自己画
final class TimeDisplayView: NSView {
    var date = Date() {
        didSet { if oldValue != date { needsDisplay = true } }
    }
    var minDate: Date?
    var maxDate: Date?
    var onCommit: (Date) -> Void = { _ in }
    var onSelection: (TimeSegment) -> Void = { _ in }
    var digitColor = TodayPalette.dark.digit { didSet { needsDisplay = true } }
    var accentColor = TodayPalette.dark.nsAccent { didSet { needsDisplay = true } }

    private var segment: TimeSegment = .hour
    /// 选中段已输入一位、等第二位的数字；此时屏幕只显示这一位，原数字被清掉
    private var pending: Int?
    private var clickMonitor: Any?
    private var hourRect = CGRect.zero
    private var minuteRect = CGRect.zero
    private let calendar = Calendar.current

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: TodayStyle.digitBox) }

    /// 设置窗口打开后直接接管键盘，打数字就能改小时
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        guard window != nil else { return }
        // 点面板外任意地方（包括空白处，空白处不会抢焦点）都把输入了一半的数字补零生效
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            let p = self.convert(event.locationInWindow, from: nil)
            if !self.bounds.contains(p) { self.commitPending() }
            return event
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, !(window.firstResponder is NSTextView) else { return }
            window.makeFirstResponder(self)
        }
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        let c = calendar.dateComponents([.hour, .minute], from: date)
        // 输入了一位时只显示这一位（前面留空），提交后才补零
        let hh = (segment == .hour ? pending.map { " \($0)" } : nil) ?? String(format: "%02d", c.hour ?? 0)
        let mm = (segment == .minute ? pending.map { " \($0)" } : nil) ?? String(format: "%02d", c.minute ?? 0)
        let text = hh + ":" + mm
        let layout = DotMatrix.layout(text, in: bounds)
        hourRect = layout.span(0..<2)
        minuteRect = layout.span(3..<5)

        // 选中段底下一块淡色圆角底
        let sel = (segment == .hour ? hourRect : minuteRect).insetBy(dx: -6, dy: -4)
        cg.setFillColor(accentColor.withAlphaComponent(0.14).cgColor)
        cg.addPath(CGPath(roundedRect: sel, cornerWidth: 6, cornerHeight: 6, transform: nil))
        cg.fillPath()

        DotMatrix.draw(layout, in: cg) { i in
            if i == 2 { return digitColor.withAlphaComponent(0.6) }
            let inHour = i < 2
            return (inHour == (segment == .hour)) ? accentColor : digitColor
        }
    }

    // MARK: 鼠标

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let mid = (hourRect.maxX + minuteRect.minX) / 2
        window?.makeFirstResponder(self)
        select(p.x < mid ? .hour : .minute)
    }

    /// 失焦后：输入了一半的补零生效，回到默认选中小时
    override func resignFirstResponder() -> Bool {
        select(.hour)
        return true
    }

    // MARK: 键盘

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: commitPending(); commit(TimeMath.step(date, segment: segment, by: +1, min: minDate, max: maxDate))  // ↑
        case 125: commitPending(); commit(TimeMath.step(date, segment: segment, by: -1, min: minDate, max: maxDate))  // ↓
        case 123: select(.hour)     // ←
        case 124: select(.minute)   // →
        case 48 where segment == .hour && !event.modifierFlags.contains(.shift): select(.minute)  // Tab
        case 48 where segment == .minute && event.modifierFlags.contains(.shift): select(.hour)  // ⇧Tab
        case 36, 76, 53: window?.makeFirstResponder(nil)  // 回车 / Esc 退出键盘输入（改动早已生效）
        default:
            if let ch = event.characters, ch.count == 1, let d = Int(ch) {
                type(d)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    /// 逐位输入，每次选中都从第一位重新开始：
    /// - 第一位：清掉原数字，只显示这一位（如 17 → 1）
    /// - 第二位：拼成两位生效（1 → 11）；小时输满后跳到分钟
    /// - 只输一位就点别处 / 切换 / 按上下键：补零生效（1 → 01）
    /// - 第一位已不可能组成两位（小时 3–9、分钟 6–9）时直接补零生效
    private func type(_ d: Int) {
        let limit = segment == .hour ? 23 : 59
        if let p = pending {
            let v = p * 10 + d
            pending = nil
            if v <= limit {
                apply(v)
                if segment == .hour { segment = .minute }
            } else {
                // 拼出来不合法（如 25），把这一位当作新的第一位
                startTyping(d, limit: limit)
            }
        } else {
            startTyping(d, limit: limit)
        }
        report()
    }

    private func startTyping(_ d: Int, limit: Int) {
        if d * 10 > limit {
            apply(d)
            if segment == .hour { segment = .minute }
        } else {
            pending = d
        }
    }

    /// 把输入了一半的那一位补零生效
    func commitPending() {
        guard let p = pending else { return }
        pending = nil
        apply(p)
        report()
    }

    private func apply(_ value: Int) {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let h = segment == .hour ? value : (c.hour ?? 0)
        let m = segment == .minute ? value : (c.minute ?? 0)
        if let new = calendar.date(bySettingHour: h, minute: m, second: 0, of: date) {
            commit(TimeMath.clamp(new, minDate, maxDate))
        }
    }

    private func select(_ s: TimeSegment) {
        commitPending()
        segment = s
        needsDisplay = true
        report()
    }

    private func commit(_ new: Date) {
        date = new
        onCommit(new)
    }

    private func report() {
        needsDisplay = true
        onSelection(segment)
    }

    // MARK: 无障碍：读屏当作「可增减」的时间控件

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .incrementor }
    override func accessibilityLabel() -> String? { "到岗时间" }
    override func accessibilityValue() -> Any? {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
    override func accessibilityPerformIncrement() -> Bool {
        commit(TimeMath.step(date, segment: segment, by: +1, min: minDate, max: maxDate)); return true
    }
    override func accessibilityPerformDecrement() -> Bool {
        commit(TimeMath.step(date, segment: segment, by: -1, min: minDate, max: maxDate)); return true
    }
}

// MARK: - 点阵数字

/// 5×7 点阵字形；每个像素再由 3×3 个小圆点组成，模拟参考图里的 LED / LCD 点阵屏
enum DotMatrix {
    static let rows = 7
    /// 一个像素的边长（pt）；7 行高 49pt，上下给选中底色留出余量
    static let pixel: CGFloat = 7
    /// 每个像素里的小圆点数（每边）
    static let dotsPerPixel = 3
    static let dotRatio: CGFloat = 0.78

    static let glyphs: [Character: [String]] = [
        "0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
        "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
        "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
        "3": ["#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."],
        "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
        "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
        "6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
        "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
        "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
        "9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
        ":": [".", ".", "#", ".", "#", ".", "."],
        " ": [".....", ".....", ".....", ".....", ".....", ".....", "....."],
        "-": [".....", ".....", ".....", ".###.", ".....", ".....", "....."],
    ]

    struct Layout {
        /// 每个字符的左上角和字形
        var chars: [(origin: CGPoint, glyph: [String])]
        func span(_ r: Range<Int>) -> CGRect {
            let first = chars[r.lowerBound], last = chars[r.upperBound - 1]
            let w = CGFloat(last.glyph[0].count) * DotMatrix.pixel
            return CGRect(x: first.origin.x, y: first.origin.y,
                          width: last.origin.x + w - first.origin.x,
                          height: CGFloat(DotMatrix.rows) * DotMatrix.pixel)
        }
    }

    /// 在 rect 里水平、垂直居中排版（坐标系 y 向下）
    static func layout(_ text: String, in rect: CGRect) -> Layout {
        let gs = text.map { glyphs[$0] ?? glyphs["-"]! }
        let widths = gs.map { CGFloat($0[0].count) * pixel }
        let total = widths.reduce(0, +) + pixel * CGFloat(max(gs.count - 1, 0))
        var x = rect.midX - total / 2
        let y = rect.midY - CGFloat(rows) * pixel / 2
        var chars: [(CGPoint, [String])] = []
        for (g, w) in zip(gs, widths) {
            chars.append((CGPoint(x: x.rounded(), y: y.rounded()), g))
            x += w + pixel
        }
        return Layout(chars: chars.map { (origin: $0.0, glyph: $0.1) })
    }

    static func draw(_ layout: Layout, in cg: CGContext, color: (Int) -> NSColor) {
        let step = pixel / CGFloat(dotsPerPixel)
        let d = step * dotRatio
        for (i, ch) in layout.chars.enumerated() {
            cg.setFillColor(color(i).cgColor)
            for (row, line) in ch.glyph.enumerated() {
                for (col, bit) in line.enumerated() where bit == "#" {
                    let px = ch.origin.x + CGFloat(col) * pixel
                    let py = ch.origin.y + CGFloat(row) * pixel
                    for dy in 0..<dotsPerPixel {
                        for dx in 0..<dotsPerPixel {
                            cg.addEllipse(in: CGRect(x: px + CGFloat(dx) * step + (step - d) / 2,
                                                     y: py + CGFloat(dy) * step + (step - d) / 2,
                                                     width: d, height: d))
                        }
                    }
                }
            }
            cg.fillPath()
        }
    }
}

/// 只读的点阵文字（未到岗时的「--:--」）
struct DotMatrixText: View {
    let text: String
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            ctx.withCGContext { cg in
                let layout = DotMatrix.layout(text, in: CGRect(origin: .zero, size: size))
                DotMatrix.draw(layout, in: cg) { _ in NSColor(color) }
            }
        }
    }
}
