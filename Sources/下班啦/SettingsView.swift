import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 设置面板：参考 macOS 系统设置（菜单栏页）的分组样式
/// - 组标题：13pt 半粗，与行内文字左对齐
/// - 分组卡片：半透明浅色底、12pt 圆角、无描边，行间细分隔线
/// - 说明文字：次级色、11pt、左对齐，放在卡片下方
struct SettingsView: View {
    @ObservedObject var model: WorkTimerModel
    @ObservedObject var reminders: ReminderModel
    /// 顶部 toast 文案，nil 时隐藏
    @State private var toast: String?
    @State private var toastToken = 0
    @State private var showAbout = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                todaySection
                workSection
                // 一个标题下两张独立卡片，参考系统设置「外观 › 主题」
                SettingsGroup("提醒") {
                    SettingsCard { waterRows }
                    SettingsCard { eggRows }
                    SettingsCard { offWorkRows }
                }
                SettingsSection("通用") {
                    SettingsRow("登录时打开") {
                        SettingsSwitch(isOn: $model.launchAtLogin)
                    }
                    SettingsDivider()
                    SettingsRow("主题色") {
                        BackgroundPicker(model: model)
                    }
                    SettingsDivider()
                    Button(action: { showAbout = true }) {
                        SettingsRow("关于下班啦") {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .frame(width: 460, height: 560)
        .background(SettingsPalette.of(model.background).window)
        .environment(\.settingsPalette, SettingsPalette.of(model.background))
        .environment(\.colorScheme, model.background == .light ? .light : .dark)
        .sheet(isPresented: $showAbout) {
            AboutView()
                .environment(\.settingsPalette, SettingsPalette.of(model.background))
                .environment(\.colorScheme, model.background == .light ? .light : .dark)
        }
        .overlay(alignment: .top) {
            if let toast {
                ToastView(text: toast)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: toast)
    }

    /// 显示 2.5 秒 toast，并让读屏读出来
    private func showToast(_ text: String) {
        toastToken += 1
        let token = toastToken
        toast = text
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if toastToken == token { toast = nil }
        }
    }

    private static let rangeResetToast = "下班区间不能早于开始，已恢复默认 10:00 – 12:00"

    // MARK: - 今日工作

    /// 改得最频繁的一块，用设备面板样式（见 TodayPanel.swift）和下面的列表区分开
    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader("今日工作")
            TodayPanel(model: model, arrivalGuess: { defaultArrivalGuess })
        }
    }

    /// 点「补填」时先填一个规则里的上班时间（不晚于现在），再用上下箭头微调
    private var defaultArrivalGuess: Date {
        let base = WorkTimerModel.workdayBase(for: Date())
        return min(WorkTimerModel.time(model.ruleStartText, on: base), Date())
    }

    // MARK: - 上班规则

    /// 工时模式、工作时长、上班时间变化时，下班时间由模型自动重算
    private var workSection: some View {
        SettingsSection("上班规则") {
            SettingsRow("工时模式") {
                SettingsPicker("工时模式", selection: $model.workMode, options: WorkMode.allCases) { $0.title }
            }
            SettingsDivider()
            SettingsRow("工作时长") {
                SettingsPicker("工作时长", selection: $model.workHours,
                               options: Array(stride(from: 6.0, through: 12.0, by: 0.5))) { Self.hoursText($0) }
            }
            SettingsDivider()
            SettingsRow("上班时间") {
                if model.workMode == .fixed {
                    TimeField(date: ruleStartBinding, accessibilityLabel: "上班时间")
                } else {
                    HStack(spacing: 6) {
                        TimeField(date: ruleStartBinding, accessibilityLabel: "上班区间开始")
                        Text("–").foregroundStyle(.secondary).accessibilityHidden(true)
                        TimeField(date: ruleLatestBinding, accessibilityLabel: "上班区间结束")
                    }
                }
            }
            SettingsDivider()
            SettingsRow("下班时间") { ValueText(model.ruleEndText) }
        }
    }

    // MARK: - 喝水提醒

    @ViewBuilder
    private var waterRows: some View {
            SettingsRow("喝水提醒") { SettingsSwitch(isOn: $reminders.waterEnabled) }
            if reminders.waterEnabled {
                SettingsDivider()
                SettingsRow("提醒间隔") {
                    SettingsPicker("提醒间隔", selection: $reminders.waterIntervalMinutes,
                                   options: ReminderModel.waterIntervals) { Self.minutesText($0) }
                }
                SettingsDivider()
                videoRow(.water)
            }
    }

    // MARK: - 小彩蛋

    @ViewBuilder
    private var eggRows: some View {
            SettingsRow("小彩蛋") { SettingsSwitch(isOn: $reminders.eggEnabled) }
            if reminders.eggEnabled {
                SettingsDivider()
                SettingsRow("提醒间隔") {
                    SettingsPicker("提醒间隔", selection: $reminders.eggIntervalMinutes,
                                   options: ReminderModel.eggIntervals) { Self.minutesText($0) }
                }
                SettingsDivider()
                videoRow(.egg)
            }
    }

    // MARK: - 下班提醒

    @ViewBuilder
    private var offWorkRows: some View {
        SettingsRow("下班提醒") { SettingsSwitch(isOn: $reminders.offWorkEnabled) }
    }

    /// 视频行：显示内置视频数量，可立即预览
    private func videoRow(_ kind: ReminderKind) -> some View {
        let count = reminders.videoCounts[kind] ?? 0
        return SettingsRow("视频") {
            HStack(spacing: 8) {
                ValueText(count == 0 ? "暂无" : "\(count) 个")
                Button("预览") { reminders.preview(kind) }
                    .disabled(count == 0)
            }
            .controlSize(.small)
        }
    }


    private static func minutesText(_ m: Int) -> String {
        m >= 60 && m % 60 == 0 ? "每 \(m / 60) 小时" : (m > 60 ? "每 \(m / 60) 小时 \(m % 60) 分" : "每 \(m) 分钟")
    }

    // MARK: - 绑定

    private var ruleStartBinding: Binding<Date> {
        timeBinding(get: { model.ruleStartText }, set: { text in
            if !model.setStartText(text) { showToast(Self.rangeResetToast) }
        })
    }

    private var ruleLatestBinding: Binding<Date> {
        timeBinding(get: { model.latestTextForUI }, set: { text in
            if !model.setLatestText(text) { showToast(Self.rangeResetToast) }
        })
    }

    /// 把 "HH:mm" 字符串绑定成 Date，供时间选择器使用
    private func timeBinding(get: @escaping () -> String, set: @escaping (String) -> Void) -> Binding<Date> {
        Binding(
            get: {
                let m = WorkTimerModel.minutes(get())
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                set(String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0))
            }
        )
    }

    private static func hoursText(_ h: Double) -> String {
        h == h.rounded() ? "\(Int(h)) 小时" : String(format: "%.1f 小时", h)
    }
}

// MARK: - 系统设置风格的基础组件

/// 一个设置分组：标题 + 卡片 + 可选说明
struct SettingsSection<Content: View>: View {
    let title: String
    let footer: String?
    @ViewBuilder let content: Content

    init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(title)
            SettingsCard { content }

            if let footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SettingsMetrics.inset)
                    .padding(.top, 8)
            }
        }
    }
}

/// 一个标题下放多张卡片，卡片之间留 10pt 间距
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(title)
            VStack(spacing: 10) { content }
        }
    }
}

/// 组标题：13pt 半粗，与卡片内文字左对齐
struct SettingsHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, SettingsMetrics.inset)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 圆角卡片容器
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.settingsPalette) private var palette

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(palette.card)
            )
    }
}

/// 一行：左侧标签，右侧控件
/// 可选副标题：标签下方一行次级色说明，参考系统设置「接入电源时启动」
struct SettingsRow<Trailing: View>: View {
    let label: String
    let subtitle: String?
    @ViewBuilder let trailing: Trailing

    init(_ label: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.label = label
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.system(size: 13))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, SettingsMetrics.inset)
        .padding(.vertical, subtitle == nil ? 0 : 8)
        .frame(maxWidth: .infinity, minHeight: 40)
        .contentShape(Rectangle())
    }
}

/// 系统设置风格的下拉（参考「能耗 › 接入电源时启动」）
/// - 默认：文字 + 右侧小圆底上下箭头
/// - 悬停：整块浅色圆角底，圆底隐去
/// - 按下：底色再亮一档，弹出系统原生菜单（选中项打勾，菜单对齐当前项）
struct SettingsPicker<Value: Hashable>: View {
    @Environment(\.settingsPalette) private var palette
    let label: String
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String

    @State private var hovering = false
    @State private var pressed = false

    init(_ label: String, selection: Binding<Value>, options: [Value], title: @escaping (Value) -> String) {
        self.label = label
        self._selection = selection
        self.options = options
        self.title = title
    }

    private var active: Bool { hovering || pressed }

    var body: some View {
        HStack(spacing: 14) {
            Text(title(selection))
                .font(.system(size: 13))
                .monospacedDigit()
            UpDownChevron()
                .stroke(Color.primary.opacity(0.85),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                .frame(width: 12, height: 12)
                .frame(width: 22, height: 22)
                .background(Circle().fill(active ? Color.clear : palette.chevronBase))
        }
        .padding(.leading, 10)
        .padding(.trailing, 3)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(pressed ? 0.12 : (hovering ? 0.07 : 0)))
        )
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.08), value: pressed)
        .accessibilityHidden(true)
        // 点击交给透明的系统弹出按钮处理：菜单位置、键盘、读屏都是原生的
        .overlay(
            PopUpOverlay(titles: options.map(title),
                         selectedIndex: options.firstIndex(of: selection) ?? 0,
                         label: label,
                         onSelect: { index in
                             if options.indices.contains(index) { selection = options[index] }
                         },
                         onHover: { hovering = $0 },
                         onPress: { pressed = $0 })
        )
    }
}

/// 系统设置下拉用的箭头：设计稿 Assets/Icons/updown-chevron.svg（12×12 画板，线宽 1.2）
/// 按 12×12 坐标描点，再缩放到实际尺寸，保证和设计稿一致
private struct UpDownChevron: Shape {
    func path(in r: CGRect) -> Path {
        let sx = r.width / 12, sy = r.height / 12
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * sx, y: r.minY + y * sy) }
        var p = Path()
        // 下箭头 ∨
        p.move(to: pt(9.95262, 7.31759))
        p.addLine(to: pt(8.63503, 8.63518))
        p.addLine(to: pt(6.6323, 10.6379))
        p.addCurve(to: pt(5.36741, 10.6379), control1: pt(6.28301, 10.9872), control2: pt(5.7167, 10.9872))
        p.addLine(to: pt(3.36467, 8.63518))
        p.addLine(to: pt(2.04708, 7.31759))
        // 上箭头 ∧
        p.move(to: pt(9.95262, 4.68241))
        p.addLine(to: pt(8.63503, 3.36482))
        p.addLine(to: pt(6.6323, 1.36208))
        p.addCurve(to: pt(5.36741, 1.36208), control1: pt(6.28301, 1.01279), control2: pt(5.7167, 1.01279))
        p.addLine(to: pt(3.36467, 3.36482))
        p.addLine(to: pt(2.04708, 4.68241))
        return p
    }
}

/// 透明的 NSPopUpButton，只负责响应点击、弹菜单，外观由 SwiftUI 绘制
private struct PopUpOverlay: NSViewRepresentable {
    let titles: [String]
    let selectedIndex: Int
    let label: String
    let onSelect: (Int) -> Void
    let onHover: (Bool) -> Void
    let onPress: (Bool) -> Void

    func makeNSView(context: Context) -> HoverPopUpButton {
        let button = HoverPopUpButton(frame: .zero, pullsDown: false)
        button.isTransparent = true
        button.isBordered = false
        // 不画系统自带的上下箭头，箭头由 SwiftUI 按设计稿绘制，避免重影
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        button.font = .systemFont(ofSize: 13)
        button.target = context.coordinator
        button.action = #selector(Coordinator.changed(_:))
        return button
    }

    func updateNSView(_ button: HoverPopUpButton, context: Context) {
        context.coordinator.parent = self
        if button.itemTitles != titles {
            button.removeAllItems()
            button.addItems(withTitles: titles)
        }
        if button.indexOfSelectedItem != selectedIndex { button.selectItem(at: selectedIndex) }
        button.setAccessibilityLabel(label)
        button.onHover = { onHover($0) }
        button.onPress = { onPress($0) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: PopUpOverlay
        init(_ parent: PopUpOverlay) { self.parent = parent }
        @objc func changed(_ sender: NSPopUpButton) { parent.onSelect(sender.indexOfSelectedItem) }
    }
}

/// 带悬停 / 按下回调的弹出按钮
final class HoverPopUpButton: NSPopUpButton {
    var onHover: ((Bool) -> Void)?
    var onPress: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
        NSCursor.pointingHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
        NSCursor.arrow.set()
    }

    /// 菜单弹出期间 super.mouseDown 会阻塞，返回即表示菜单已关闭
    override func mouseDown(with event: NSEvent) {
        onPress?(true)
        super.mouseDown(with: event)
        onPress?(false)
        if let window {
            let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            onHover?(bounds.contains(point))
        }
    }
}

/// 顶部轻提示
struct ToastView: View {
    @Environment(\.settingsPalette) private var palette
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color(red: 1.0, green: 0.74, blue: 0.18))
            Text(text)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(palette.toast))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
    }
}

/// 系统设置风格的小开关
struct SettingsSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(AccentSwitchStyle())
    }
}

/// 自绘开关：开启时用「今日工作」面板的橙色强调色
/// 系统开关跟随系统强调色，窗口失焦还会变灰，所以自己画，保证颜色稳定
struct AccentSwitchStyle: ToggleStyle {
    @Environment(\.settingsPalette) private var palette
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        let offTrack = scheme == .light ? Color.black.opacity(0.12) : Color.white.opacity(0.16)
        return Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule()
                    .fill(on ? TodayPalette.dark.accent : offTrack)
                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    .padding(2)
            }
            .frame(width: 32, height: 18)
            .animation(.easeOut(duration: 0.15), value: on)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(on ? "开" : "关")
        .accessibilityAction { configuration.isOn.toggle() }
    }
}

/// 只读数值（自动计算的时间），次级色等宽数字
struct ValueText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }
}

/// 行间分隔线：左右与文字对齐内缩
struct SettingsDivider: View {
    @Environment(\.settingsPalette) private var palette
    var body: some View {
        Rectangle()
            .fill(palette.separator)
            .frame(height: 0.5)
            .padding(.horizontal, SettingsMetrics.inset)
    }
}

/// 设置面板配色：跟随「背景」选项
/// - 深色取自系统设置深色模式整体压深一档（窗口 #222120 / 卡片 #2D2B2A）
/// - 浅色取自系统设置浅色模式（窗口 #FFFFFF / 卡片 #F7F7F7 / 分隔线 #EBEBEB）
struct SettingsPalette {
    var window: Color
    var card: Color
    var separator: Color
    /// 下拉箭头的小圆底
    var chevronBase: Color
    var toast: Color
    var nsWindow: NSColor

    static let dark = SettingsPalette(
        window: Color(red: 0x22 / 255, green: 0x21 / 255, blue: 0x20 / 255),
        card: Color(red: 0x2D / 255, green: 0x2B / 255, blue: 0x2A / 255),
        separator: Color.white.opacity(0.07),
        chevronBase: Color.white.opacity(0.1),
        toast: Color(white: 0.24),
        nsWindow: NSColor(srgbRed: 0x22 / 255, green: 0x21 / 255, blue: 0x20 / 255, alpha: 1))

    static let light = SettingsPalette(
        window: .white,
        card: Color(red: 0xF7 / 255, green: 0xF7 / 255, blue: 0xF7 / 255),
        separator: Color(red: 0xEB / 255, green: 0xEB / 255, blue: 0xEB / 255),
        chevronBase: Color(red: 0xE4 / 255, green: 0xE4 / 255, blue: 0xE4 / 255),
        toast: .white,
        nsWindow: .white)

    static func of(_ background: AppBackground) -> SettingsPalette {
        background == .light ? .light : .dark
    }
}

private struct SettingsPaletteKey: EnvironmentKey {
    static let defaultValue = SettingsPalette.dark
}

extension EnvironmentValues {
    var settingsPalette: SettingsPalette {
        get { self[SettingsPaletteKey.self] }
        set { self[SettingsPaletteKey.self] = newValue }
    }
}

/// 无边框时间选择器：只显示数字和右侧上下箭头，数字底下没有输入框
/// SwiftUI 的 DatePicker 去不掉边框，所以直接包一层 NSDatePicker
struct TimeField: NSViewRepresentable {
    @Binding var date: Date
    var minDate: Date? = nil
    var maxDate: Date? = nil
    var accessibilityLabel: String = "时间"

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .hourMinute
        picker.isBezeled = false
        picker.isBordered = false
        picker.drawsBackground = false
        picker.focusRingType = .none
        picker.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        picker.setContentHuggingPriority(.required, for: .horizontal)
        picker.setAccessibilityLabel(accessibilityLabel)
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.parent = self
        picker.minDate = minDate
        picker.maxDate = maxDate
        if picker.dateValue != date { picker.dateValue = date }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: TimeField
        init(_ parent: TimeField) { self.parent = parent }
        @objc func changed(_ sender: NSDatePicker) { parent.date = sender.dateValue }
    }
}

enum SettingsMetrics {
    /// 卡片内左右边距，标题和说明文字也与之对齐
    static let inset: CGFloat = 12
}

/// 背景选择：黑色 / 白色色块 + 上传图片按钮
struct BackgroundPicker: View {
    @ObservedObject var model: WorkTimerModel

    var body: some View {
        HStack(spacing: 10) {
            swatch(.dark, fill: .black)
            swatch(.light, fill: .white)
            Button("上传图片…", action: pickImage)
                .controlSize(.small)
        }
    }

    private func swatch(_ option: AppBackground, fill: Color) -> some View {
        let selected = model.background == option
        return Button(action: { model.background = option }) {
            Circle()
                .fill(fill)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                .overlay {
                    if selected {
                        Circle().fill(fill == .white ? Color.black : Color.white).frame(width: 6, height: 6)
                    }
                }
                .padding(3)
                // 选中圈和开关同色：今日工作面板的橙色强调色
                .overlay(Circle().strokeBorder(selected ? TodayPalette.dark.accent : .clear, lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(option.rawValue)
        .accessibilityLabel(option.rawValue)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 打开系统文件选择器，选中的图片拷贝到 App 的 Application Support 目录持久保存
    private func pickImage() {
        let panel = NSOpenPanel()
        panel.title = "选择背景图片"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let saved = Self.persist(url) {
            model.backgroundImagePath = saved
            model.background = .image
        }
    }

    /// 拷贝到 Application Support/下班啦/Backgrounds，避免原图被用户移动或删除后失效
    private static func persist(_ source: URL) -> String? {
        let fm = FileManager.default
        guard let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                        appropriateFor: nil, create: true) else { return nil }
        let dir = support.appendingPathComponent("下班啦/Backgrounds", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("custom.\(source.pathExtension.isEmpty ? "png" : source.pathExtension)")
        try? fm.removeItem(at: dest)
        do {
            try fm.copyItem(at: source, to: dest)
            return dest.path
        } catch {
            return nil
        }
    }
}

// MARK: - 关于下班啦

/// 关于面板：参考系统「关于本机」——图标 + 名称，中间一段信息列表，底部小字版权
struct AboutView: View {
    @Environment(\.settingsPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    /// Info.plist 里的版本号（CFBundleShortVersionString / CFBundleVersion）
    private var version: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "版本 \(shortVersion) (\(build))"
    }
    private let repoURL = URL(string: "https://github.com/shamingxin/xiabanla")!

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)

                VStack(spacing: 4) {
                    Text("下班啦")
                        .font(.system(size: 22, weight: .semibold))
                    Text("这个点，该走了")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 36)
            .padding(.bottom, 24)

            VStack(spacing: 0) {
                aboutRow("版本", version)
                SettingsDivider()
                aboutRow("开发者", "沙沙")
                SettingsDivider()
                HStack(spacing: 12) {
                    Text("项目地址").font(.system(size: 13))
                    Spacer(minLength: 8)
                    Link("GitHub", destination: repoURL)
                        .font(.system(size: 13))
                }
                .padding(.horizontal, SettingsMetrics.inset)
                .frame(minHeight: 36)
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.card))
            .padding(.horizontal, 36)

            Spacer(minLength: 20)

            VStack(spacing: 4) {
                Text("由沙沙制作")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("© 2026 沙沙. 保留所有权利。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .padding(.bottom, 20)
        }
        .frame(width: 360, height: 420)
        .background(palette.window)
        .overlay(alignment: .topTrailing) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(14)
        }
    }

    private func aboutRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 13))
            Spacer(minLength: 8)
            Text(value).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, SettingsMetrics.inset)
        .frame(minHeight: 36)
    }
}
