import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 设置面板：参考 macOS 系统设置（菜单栏页）的分组样式
/// - 组标题：13pt 半粗，与行内文字左对齐
/// - 分组卡片：半透明浅色底、12pt 圆角、无描边，行间细分隔线
/// - 说明文字：次级色、11pt、左对齐，放在卡片下方
/// 设置面板侧边栏分区：对应系统设置左侧列表
enum SettingsSidebarItem: String, CaseIterable, Identifiable {
    case workHours = "工作时长"
    case reminderAnimations = "提醒动画"
    case general = "通用"
    case appearance = "外观"
    case about = "关于"

    var id: String { rawValue }

    /// 实心图标，放在彩色圆角方块里（系统设置左栏同款）
    var icon: String {
        switch self {
        case .workHours: return "clock.fill"
        case .reminderAnimations: return "bell.fill"
        case .general: return "gearshape.fill"
        case .appearance: return "circle.lefthalf.filled"
        case .about: return "info.circle.fill"
        }
    }

    /// 图标底色：分类色，固定不随主题色变化（和系统设置一样，每个分区一种颜色）
    var tint: Color {
        switch self {
        case .workHours: return Color(red: 1.0, green: 0.584, blue: 0.0)      // 橙
        case .reminderAnimations: return Color(red: 1.0, green: 0.231, blue: 0.188) // 红
        case .general: return Color(red: 0.557, green: 0.557, blue: 0.576)    // 灰
        case .appearance: return Color(red: 0.11, green: 0.11, blue: 0.118)    // 黑（系统设置「外观」同款）
        case .about: return Color(red: 0.0, green: 0.478, blue: 1.0)          // 蓝
        }
    }
}

/// 左侧分区列表：参考 macOS 26 系统设置
/// - 整块是内缩的浮起圆角面板（细描边），窗口红黄绿按钮落在面板顶部
/// - 每行：20pt 彩色圆角方块图标 + 13pt 文字，行高 32
/// - 选中态：主题色实底，文字按底色亮度自动取黑/白
struct SettingsSidebar: View {
    @Binding var selection: SettingsSidebarItem
    @Environment(\.settingsPalette) private var palette
    @Environment(\.themeAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsSidebarItem.allCases) { item in
                row(item)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        // 顶部留出红黄绿按钮的位置（标题栏 52pt 高，面板从 8pt 开始）
        .padding(.top, SettingsMetrics.toolbarHeight - SettingsMetrics.sidebarInset + 4)
        .padding(.bottom, 10)
        .frame(width: SettingsMetrics.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: SettingsMetrics.sidebarRadius, style: .continuous)
                .fill(palette.sidebar.opacity(palette.sidebarTintOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsMetrics.sidebarRadius, style: .continuous)
                .strokeBorder(palette.sidebarStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 6, y: 1)
        .padding([.leading, .top, .bottom], SettingsMetrics.sidebarInset)
    }

    private func row(_ item: SettingsSidebarItem) -> some View {
        let selected = selection == item
        return Button(action: { selection = item }) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(item.tint.gradient)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Image(systemName: item.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(selected ? 0.35 : 0), lineWidth: 0.5)
                    )
                Text(item.rawValue)
                    .font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? accent.contrastingText : Color.primary)
            .padding(.horizontal, 6)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? accent : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.rawValue)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension Color {
    /// 放在这个颜色上的文字该用黑还是白：按 sRGB 相对亮度判断（黄、荧光绿用黑字，蓝、红用白字）
    var contrastingText: Color {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return .white }
        func lin(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let l = 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
        return l > 0.4 ? Color.black.opacity(0.85) : .white
    }
}

struct SettingsView: View {
    @ObservedObject var model: WorkTimerModel
    @ObservedObject var reminders: ReminderModel
    /// 顶部 toast 文案，nil 时隐藏
    @State private var toast: String?
    @State private var toastToken = 0
    /// 当前选中的侧边栏分区，默认「工作时长」
    @State private var selectedSection: SettingsSidebarItem = .workHours

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selectedSection)
            VStack(spacing: 0) {
                // 工具栏行：标题和窗口红黄绿按钮同一水平线，参考系统设置「外观」页顶部
                Text(selectedSection.rawValue)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SettingsMetrics.contentPadding)
                    .frame(height: SettingsMetrics.toolbarHeight)
                    .accessibilityAddTraits(.isHeader)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedSection {
                        case .workHours:
                            todaySection
                            workSection
                        case .reminderAnimations:
                            SettingsCard { waterRows }
                            SettingsCard { eggRows }
                            SettingsCard { offWorkRows }
                        case .general:
                            SettingsCard {
                                SettingsRow("登录时打开") {
                                    SettingsSwitch(isOn: $model.launchAtLogin)
                                }
                            }
                            // 固定模式按设定时间倒计时，不需要自动开始
                            if model.workMode == .flexible { autoStartSection }
                            commuteBufferSection
                        case .appearance:
                            // 页面标题已经是「外观」，卡片上方不再重复小标题
                            SettingsCard {
                                // 参考系统设置「外观」行：标签左上，右侧窗口缩略图 + 下方文字
                                HStack(alignment: .top, spacing: 12) {
                                    Text("深浅模式").font(.system(size: 13))
                                        .padding(.top, 2)
                                    Spacer(minLength: 8)
                                    BackgroundPicker(model: model)
                                }
                                .padding(.horizontal, SettingsMetrics.inset)
                                .padding(.vertical, 12)
                                SettingsDivider()
                                SettingsRow("主题色") {
                                    AccentColorPicker(model: model)
                                }
                            }
                            // 倒计时样式单独成组：可视化预览网格，参考系统设置「墙纸」，后续加样式直接往枚举里加
                            VStack(alignment: .leading, spacing: 0) {
                                SettingsHeader("倒计时样式")
                                CountdownStylePicker(model: model)
                            }
                        case .about:
                            AboutView()
                        }
                    }
                    .padding(.horizontal, SettingsMetrics.contentPadding)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: SettingsMetrics.contentWidth)
        }
        // 宽度固定；高度跟随窗口（用户可上下拖动），由 AppDelegate 限制最小/最大高度
        .frame(width: SettingsMetrics.windowWidth)
        .frame(minHeight: SettingsMetrics.minWindowHeight, maxHeight: .infinity)
        // 窗口外框圆角自己画：用 15.x SDK 编译时系统只给小圆角，和 macOS 26 系统设置对不上
        // 窗口本身是透明的（见 AppDelegate.applySettingsAppearance），可见形状完全由这里决定
        .background(
            ZStack {
                // 透出窗口后方桌面的模糊，参考系统设置
                SettingsBlurBackground(light: model.background == .light,
                                       cornerRadius: SettingsMetrics.windowRadius)
                // 内容区压一层较实的底色；侧边栏区域挖空，侧边栏自己铺更透的底，所以左边透出更多壁纸色
                WindowTintShape()
                    .fill(SettingsPalette.of(model.background).window
                            .opacity(SettingsPalette.of(model.background).windowTintOpacity),
                          style: FillStyle(eoFill: true))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: SettingsMetrics.windowRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsMetrics.windowRadius, style: .continuous)
                .strokeBorder(SettingsPalette.of(model.background).windowStroke, lineWidth: 1)
        )
        .environment(\.settingsPalette, SettingsPalette.of(model.background))
        .environment(\.colorScheme, model.background == .light ? .light : .dark)
        .environment(\.themeAccent, model.accentColor)
        .overlay(alignment: .top) {
            if let toast {
                ToastView(text: toast)
                    .padding(.top, SettingsMetrics.toolbarHeight)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: toast)
        // 必须放在最外层：整块（含圆角背景和裁切）铺到标题栏下面（窗口是 fullSizeContentView）
        // 放在里层的话，外层圆角背景仍按安全区排版，会把顶部 52pt 裁掉、红黄绿按钮露在窗口外
        .ignoresSafeArea()
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

    // MARK: - 自动开始上班

    /// 一个开关 + 开启后的上班日；开机自动开始依赖「登录时打开」，没开时给一条提示
    private var autoStartSection: some View {
        SettingsCard {
            SettingsRow("自动计时", subtitle: "早晨打开电脑后，自动开始当天的下班倒计时。") {
                SettingsSwitch(isOn: $model.autoStartEnabled)
                    .accessibilityLabel("自动计时")
            }
            if model.autoStartEnabled {
                SettingsDivider()
                SettingsRow("上班日") {
                    WeekdayPicker(selection: $model.autoStartWeekdays)
                }
                if !model.launchAtLogin {
                    SettingsDivider()
                    HStack(spacing: 8) {
                        Text("开机后要自动开始，请先开启「登录时打开」。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button("前往通用") { selectedSection = .general }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, SettingsMetrics.inset)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    /// 独立于自动计时：不管自动开始还是手动点「开始上班」，到岗时间都按此回拨
    private var commuteBufferSection: some View {
        SettingsCard {
            SettingsRow("到工位缓冲", subtitle: "开始上班时，将记录的上班时间提前一段到工位的时间。") {
                SettingsSwitch(isOn: $model.commuteBufferEnabled)
                    .accessibilityLabel("到工位缓冲")
            }
            if model.commuteBufferEnabled {
                SettingsDivider()
                SettingsRow("缓冲时间") {
                    SettingsPicker("缓冲时间", selection: $model.commuteBufferMinutes,
                                   options: WorkTimerModel.commuteBufferOptions) { "\($0) 分钟" }
                }
            }
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
                SettingsRow("强制提醒", subtitle: "需手动关闭动画") {
                    SettingsSwitch(isOn: $reminders.waterSticky)
                }
                SettingsDivider()
                videoRow(.water)
            }
    }

    // MARK: - 小彩蛋

    @ViewBuilder
    private var eggRows: some View {
            SettingsRow("随机彩蛋") { SettingsSwitch(isOn: $reminders.eggEnabled) }
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
                RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius, style: .continuous)
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

/// 自绘开关：开启时用「今日工作」面板的强调色
/// 系统开关跟随系统强调色，窗口失焦还会变灰，所以自己画，保证颜色稳定
struct AccentSwitchStyle: ToggleStyle {
    @Environment(\.settingsPalette) private var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.themeAccent) private var accent

    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        let offTrack = scheme == .light ? Color.black.opacity(0.12) : Color.white.opacity(0.16)
        return Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule()
                    .fill(on ? accent : offTrack)
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

/// 上班日选择：一到日 7 个圆形按钮，选中用主题色实底
/// selection 存 Calendar weekday（1 = 周日 … 7 = 周六），界面按周一开头排列
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    @Environment(\.themeAccent) private var accent

    private static let days: [(weekday: Int, title: String)] =
        [(2, "一"), (3, "二"), (4, "三"), (5, "四"), (6, "五"), (7, "六"), (1, "日")]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Self.days, id: \.weekday) { day in
                let on = selection.contains(day.weekday)
                Button {
                    if on { selection.remove(day.weekday) } else { selection.insert(day.weekday) }
                } label: {
                    Text(day.title)
                        .font(.system(size: 11, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? accent.contrastingText : Color.primary.opacity(0.75))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(on ? accent : Color.primary.opacity(0.08)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("周" + day.title)
                .accessibilityValue(on ? "已选" : "未选")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
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
    /// 侧边栏浮起面板底色与描边
    var sidebar: Color
    var sidebarStroke: Color
    /// 自绘窗口外框描边（代替系统窗口边缘的细高光线）
    var windowStroke: Color
    /// 背景模糊上压的底色不透明度：内容区较实、侧边栏较透
    var windowTintOpacity: Double
    var sidebarTintOpacity: Double
    var nsWindow: NSColor

    // 参考 macOS 26 系统设置：三层都是半透明，叠在窗口底部的背景模糊上
    // - 侧边栏：底色最透，壁纸颜色透出最明显
    // - 内容区：底色较实，只隐约透一点
    // - 卡片：在内容区上再叠一层很淡的白（深色）/ 黑（浅色），本身不遮挡模糊
    // 底色用中性冷灰，不再用偏暖的 #222120，避免和壁纸色调打架
    static let dark = SettingsPalette(
        window: Color(red: 0x1F / 255, green: 0x20 / 255, blue: 0x23 / 255),
        card: Color.white.opacity(0.055),
        separator: Color.white.opacity(0.08),
        chevronBase: Color.white.opacity(0.1),
        toast: Color(white: 0.24),
        sidebar: Color(red: 0x1F / 255, green: 0x20 / 255, blue: 0x23 / 255),
        sidebarStroke: Color.white.opacity(0.1),
        windowStroke: Color.white.opacity(0.14),
        windowTintOpacity: 0.78,
        sidebarTintOpacity: 0.3,
        nsWindow: NSColor(srgbRed: 0x1F / 255, green: 0x20 / 255, blue: 0x23 / 255, alpha: 1))

    static let light = SettingsPalette(
        window: .white,
        card: Color.black.opacity(0.035),
        separator: Color.black.opacity(0.07),
        chevronBase: Color.black.opacity(0.07),
        toast: .white,
        sidebar: .white,
        sidebarStroke: Color.black.opacity(0.06),
        windowStroke: Color.black.opacity(0.12),
        windowTintOpacity: 0.8,
        sidebarTintOpacity: 0.35,
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

/// 主题色环境值：用户在「主题色」行选择的强调色，开关、选中态等统一从这里取
/// 默认黄色兜底，SettingsView 根部用 model.accentColor 覆盖
private struct ThemeAccentKey: EnvironmentKey {
    static let defaultValue = WorkTimerModel.color(fromHex: AccentPreset.yellow.hex)!
}

extension EnvironmentValues {
    var themeAccent: Color {
        get { self[ThemeAccentKey.self] }
        set { self[ThemeAccentKey.self] = newValue }
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

/// 设置窗口的背景模糊：透出窗口后方的桌面（behindWindow），随深浅模式切换外观
/// 用遮罩图做圆角，SwiftUI 的 clipShape 裁不到 NSVisualEffectView 的模糊层
struct SettingsBlurBackground: NSViewRepresentable {
    var light: Bool
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .underWindowBackground
        view.maskImage = Self.maskImage(cornerRadius: cornerRadius)
        update(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) { update(view) }

    private func update(_ view: NSVisualEffectView) {
        view.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
    }

    private static func maskImage(cornerRadius r: CGFloat) -> NSImage {
        let edge = r * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        image.resizingMode = .stretch
        return image
    }
}

/// 整个窗口减去侧边栏面板的形状（配合 eoFill 使用），让内容区和侧边栏各自控制透明度
struct WindowTintShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRect(rect)
        let m = SettingsMetrics.self
        let sidebar = CGRect(x: rect.minX + m.sidebarInset, y: rect.minY + m.sidebarInset,
                             width: m.sidebarWidth, height: rect.height - m.sidebarInset * 2)
        p.addRoundedRect(in: sidebar, cornerSize: CGSize(width: m.sidebarRadius, height: m.sidebarRadius),
                         style: .continuous)
        return p
    }
}

enum SettingsMetrics {
    /// 卡片内左右边距，标题和说明文字也与之对齐
    static let inset: CGFloat = 12
    /// 窗口标题栏（带空工具栏）高度，红黄绿按钮垂直居中在这一行
    static let toolbarHeight: CGFloat = 52
    /// 侧边栏浮起面板：距窗口边缘内缩、宽度、圆角
    static let sidebarInset: CGFloat = 8
    static let sidebarWidth: CGFloat = 190
    static let sidebarRadius: CGFloat = 20
    /// 内容卡片圆角
    static let cardRadius: CGFloat = 16
    /// 右侧内容区宽度（「今日工作」面板按这个宽度设计，不要改）与左右留白
    static let contentWidth: CGFloat = 480
    static let contentPadding: CGFloat = 20
    /// 窗口固定尺寸：不随内容自适应，避免布局循环
    static let windowWidth: CGFloat = sidebarInset + sidebarWidth + contentWidth
    /// 设置窗口默认高度（首次打开、没有拖动记录时）
    static let windowHeight: CGFloat = 680
    /// 用户拖动高度的范围
    static let minWindowHeight: CGFloat = 500
    static let maxWindowHeight: CGFloat = 1000
    /// 窗口外框圆角：和侧边栏面板同心（内缩 8 + 面板圆角 20）
    static let windowRadius: CGFloat = sidebarInset + sidebarRadius
}

/// 深浅模式选择：参考系统设置「外观」，窗口缩略图 + 下方文字，选中态主题色描边
/// 顺序和系统一致：浅色在前、深色在后
/// 曾有「上传图片」第三态，已下线（代码见 WidgetContainer.customImage 注释，未删除）
struct BackgroundPicker: View {
    @ObservedObject var model: WorkTimerModel
    @Environment(\.themeAccent) private var accent

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            option(.light, title: "浅色")
            option(.dark, title: "深色")
        }
    }

    private func option(_ value: AppBackground, title: String) -> some View {
        let selected = model.background == value
        return Button(action: { model.background = value }) {
            VStack(spacing: 6) {
                AppearanceThumbnail(light: value == .light)
                    .padding(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(selected ? accent : Color.clear, lineWidth: 3)
                    )
                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 深浅模式缩略图：蓝色渐变壁纸上叠两扇小窗（后窗带蓝色条，前窗带红黄绿三点）
/// 浅色是白窗，深色是深灰窗，和系统设置「外观」缩略图同一画法
struct AppearanceThumbnail: View {
    let light: Bool

    var body: some View {
        let wallpaper: [Color] = light
            ? [Color(red: 0.62, green: 0.78, blue: 1.0), Color(red: 0.18, green: 0.42, blue: 0.95)]
            : [Color(red: 0.22, green: 0.20, blue: 0.62), Color(red: 0.06, green: 0.08, blue: 0.28)]
        let backWindow = light ? Color(white: 0.94) : Color(red: 0.16, green: 0.16, blue: 0.22)
        let frontWindow = light ? Color.white : Color(red: 0.11, green: 0.11, blue: 0.13)
        let windowBlue = Color(red: 0.25, green: 0.47, blue: 1.0)

        return ZStack(alignment: .topLeading) {
            LinearGradient(colors: wallpaper, startPoint: .topLeading, endPoint: .bottomTrailing)

            // 后窗：顶部一条蓝色高亮
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(backWindow)
                .frame(width: 58, height: 26)
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(windowBlue)
                        .frame(width: 40, height: 5)
                        .padding(.top, 5)
                        .padding(.leading, 5)
                }
                .offset(x: 5, y: 5)

            // 前窗：红黄绿三点
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(frontWindow)
                .frame(width: 40, height: 20)
                .overlay {
                    HStack(spacing: 3) {
                        Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34))
                        Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18))
                        Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25))
                    }
                    .frame(height: 5)
                }
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                .offset(x: 24, y: 24)
        }
        .frame(width: 68, height: 46, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .accessibilityHidden(true)
    }
}

/// 主题色选择：5 个预设色块 + 自定义十六进制输入
/// 选中态用一个细描边圈标出，和深浅模式的按钮高亮区分开（这里本身就是在挑颜色，不需要再用主题色描边）
struct AccentColorPicker: View {
    @ObservedObject var model: WorkTimerModel
    @State private var customHex: String = ""
    @State private var customInvalid = false

    private var selectedPreset: AccentPreset? {
        AccentPreset.allCases.first { $0.hex.caseInsensitiveCompare(model.accentColorHex) == .orderedSame }
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(AccentPreset.allCases) { preset in
                swatch(color: WorkTimerModel.color(fromHex: preset.hex) ?? .clear,
                       selected: selectedPreset == preset) {
                    model.accentColorHex = preset.hex
                }
                .help(preset.rawValue)
                .accessibilityLabel(preset.rawValue)
            }
            customField
        }
        .onAppear { syncCustomField() }
        .onChange(of: model.accentColorHex) { _ in syncCustomField() }
    }

    private func swatch(color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                .overlay(Circle().strokeBorder(selected ? Color.primary.opacity(0.8) : .clear, lineWidth: 2)
                    .padding(-2.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 自定义十六进制输入：失焦或回车时校验，格式不对标红且不生效
    /// 当前颜色不是任何预设（即用户在用自定义色）时，描边高亮，和预设色块的选中态呼应
    private var customField: some View {
        let isCustomSelected = selectedPreset == nil
        return HStack(spacing: 6) {
            Text("#").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
            TextField("自定义", text: $customHex)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 64)
                .onSubmit(applyCustomHex)
                .onChange(of: customHex) { _ in customInvalid = false }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(customInvalid ? Color.red.opacity(0.6)
                              : (isCustomSelected ? Color.primary.opacity(0.8) : Color.clear),
                              lineWidth: customInvalid || isCustomSelected ? 1.5 : 1)
        )
        .accessibilityAddTraits(isCustomSelected ? .isSelected : [])
    }

    private func applyCustomHex() {
        guard WorkTimerModel.color(fromHex: customHex) != nil else {
            customInvalid = true
            return
        }
        var h = customHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        model.accentColorHex = h.uppercased()
        customInvalid = false
    }

    /// 当前颜色不是预设时，自定义框显示当前 hex；是预设时自定义框留空
    private func syncCustomField() {
        customHex = selectedPreset == nil ? model.accentColorHex : ""
    }
}

/// 倒计时样式选择：参考系统设置「墙纸」，每个样式一张预览缩略图 + 下方名称，选中态主题色描边
/// 3 列网格，遍历 CountdownStyle.allCases：以后新增样式只需在枚举里加一项、在 CountdownStylePreview 里画出预览
/// 只影响主卡片（CountdownCardView），不影响「今日工作」点阵面板
struct CountdownStylePicker: View {
    @ObservedObject var model: WorkTimerModel
    @Environment(\.themeAccent) private var accent

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(CountdownStyle.allCases) { style in
                option(style)
            }
        }
    }

    private func option(_ style: CountdownStyle) -> some View {
        let selected = model.countdownStyle == style
        return Button(action: { model.countdownStyle = style }) {
            VStack(spacing: 7) {
                CountdownStylePreview(style: style, light: model.background == .light)
                    .padding(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(selected ? accent : Color.clear, lineWidth: 3)
                    )
                Text(style.rawValue)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("倒计时样式：\(style.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 倒计时样式预览：主卡片数字区的缩小版（固定显示 08:42:16），跟随深浅模式
/// 画法和 CountdownCardView 对应样式保持一致：翻页 = 半透明数字牌 + 中缝，灵动岛 = 圆体粗数字 + 冒号点
struct CountdownStylePreview: View {
    let style: CountdownStyle
    let light: Bool

    private let digits = ["08", "42", "16"]

    var body: some View {
        let palette = light ? CardPalette.light : CardPalette.dark
        let background: [Color] = light
            ? [Color(white: 0.97), Color(white: 0.88)]
            : [Color(red: 0.24, green: 0.23, blue: 0.24), Color(red: 0.12, green: 0.12, blue: 0.13)]

        return ZStack {
            LinearGradient(colors: background, startPoint: .topLeading, endPoint: .bottomTrailing)
            content(palette)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 78)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func content(_ palette: CardPalette) -> some View {
        switch style {
        case .flip:
            HStack(spacing: 4) {
                ForEach(digits, id: \.self) { d in
                    ZStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(palette.tile)
                        Text(d)
                            .font(Font(NSFont(name: "DINCondensed-Bold", size: 26)
                                       ?? .monospacedDigitSystemFont(ofSize: 21, weight: .bold)))
                            .foregroundStyle(palette.digit)
                            .offset(y: 2)
                        // 翻页牌中缝
                        Rectangle()
                            .fill(light ? Color.white.opacity(0.9) : Color.black.opacity(0.45))
                            .frame(height: 1)
                    }
                    .frame(width: 30, height: 30)
                }
            }
        case .dynamicIsland:
            HStack(spacing: 0) {
                ForEach(Array(digits.enumerated()), id: \.offset) { i, d in
                    if i > 0 {
                        VStack(spacing: 6) {
                            Circle().frame(width: 3, height: 3)
                            Circle().frame(width: 3, height: 3)
                        }
                        .foregroundStyle(palette.digit.opacity(0.8))
                        .frame(width: 8)
                    }
                    // 两位数字必须在一行：30pt 宽放不下 23pt 圆体粗字，会被折成上下两行
                    Text(d)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(palette.digit)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: 32)
                }
            }
        case .standbyClock:
            HStack(spacing: 0) {
                standbyDigits("08", groupIndex: 0)
                standbyColon.zIndex(10)
                standbyDigits("42", groupIndex: 1)
                standbyColon.zIndex(10)
                standbyDigits("16", groupIndex: 2)
            }
        }
    }

    /// 待机时钟缩略图：十位深蓝、个位浅蓝，靠负间距形成双色大字，和主卡片的 StandbyDigitGroup 保持同一视觉语言。
    private func standbyDigits(_ digits: String, groupIndex: Int) -> some View {
        let characters = Array(digits)
        let tens = characters.indices.contains(0) ? String(characters[0]) : "–"
        let ones = characters.indices.contains(1) ? String(characters[1]) : "–"
        return ZStack {
            HStack(spacing: -10) {
                Text(tens)
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(red: 0.00, green: 0.33, blue: 0.73).opacity(0.86))
                    .scaleEffect(x: 1.08, y: 1.09)
                    .rotationEffect(.degrees(previewTilt(at: groupIndex * 2)))
                Text(ones)
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(red: 0.34, green: 0.66, blue: 0.94).opacity(0.86))
                    .scaleEffect(x: 1.08, y: 1.09)
                    .rotationEffect(.degrees(previewTilt(at: groupIndex * 2 + 1)))
            }
        }
        .lineLimit(1)
        .fixedSize()
        .frame(width: 30)
    }

    private func previewTilt(at position: Int) -> Double {
        let tilts: [Double] = [4.2, -6.4, 1.3, -2.5, 5.1, -3.6]
        return tilts[position % tilts.count]
    }

    private var standbyColon: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(LinearGradient(colors: [.white.opacity(0.96), Color(white: 0.62)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 6, height: 6)
            Circle()
                .fill(LinearGradient(colors: [.white.opacity(0.96), Color(white: 0.62)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 6, height: 6)
        }
        .frame(width: 12)
    }
}

// MARK: - 关于下班啦

/// 「关于下班啦」分区：直接显示在设置右侧内容区，不再弹窗
/// 参考系统「关于本机」：图标 + 名称居中，下面一张信息卡片，底部小字版权
struct AboutView: View {
    @Environment(\.settingsPalette) private var palette
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
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .padding(.bottom, 28)

            VStack(spacing: 0) {
                aboutRow("版本", version)
                SettingsDivider()
                aboutRow("开发者", "沙沙")
                SettingsDivider()
                aboutRow("宝贵意见共创人", "PJ")
                SettingsDivider()
                HStack(spacing: 12) {
                    Text("项目地址").font(.system(size: 13))
                    Spacer(minLength: 8)
                    Link("GitHub", destination: repoURL)
                        .font(.system(size: 13))
                }
                .padding(.horizontal, SettingsMetrics.inset)
                .frame(minHeight: 40)
            }
            .background(RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius, style: .continuous).fill(palette.card))

            VStack(spacing: 4) {
                Text("由沙沙制作")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("© 2026 沙沙. 保留所有权利。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
        }
    }

    private func aboutRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 13))
            Spacer(minLength: 8)
            Text(value).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, SettingsMetrics.inset)
        .frame(minHeight: 40)
    }
}
