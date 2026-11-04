import SwiftUI

/// 设置面板：参考 macOS 系统设置（菜单栏页）的分组样式
/// - 组标题：13pt 半粗，与行内文字左对齐
/// - 分组卡片：半透明浅色底、12pt 圆角、无描边，行间细分隔线
/// - 说明文字：次级色、11pt、左对齐，放在卡片下方
struct SettingsView: View {
    @ObservedObject var model: WorkTimerModel
    @ObservedObject var reminders: ReminderModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                todaySection
                workSection
                // 一个标题下两张独立卡片，参考系统设置「外观 › 主题」
                SettingsGroup("提醒") {
                    SettingsCard { waterRows }
                    SettingsCard { eggRows }
                }
                SettingsSection("通用") {
                    SettingsRow("登录时打开") {
                        SettingsSwitch(isOn: $model.launchAtLogin)
                    }
                    SettingsDivider()
                    SettingsRow("主题色") {
                        HStack(spacing: 10) {
                            ForEach(AppTheme.allCases) { theme in
                                ThemeSwatch(theme: theme, selected: model.theme == theme) {
                                    model.theme = theme
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .frame(width: 460, height: 560)
        .background(SettingsPalette.window)
    }

    // MARK: - 今天

    private var todaySection: some View {
        SettingsSection("今日工作") {
            SettingsRow("到岗时间") {
                HStack(spacing: 8) {
                    TimeField(date: startBinding,
                              minDate: Calendar.current.startOfDay(for: Date()),
                              maxDate: Date())
                    if !model.hasStarted {
                        Button("现在开始") { model.startWork() }
                    }
                }
            }
            if model.hasStarted {
                SettingsDivider()
                SettingsRow("预计下班") { ValueText(model.endTimeText) }
            }
        }
    }

    // MARK: - 工作

    /// 每日工作时长、参考上班时间变化时，参考下班时间由模型自动重算
    private var workSection: some View {
        SettingsSection("工作时长") {
            SettingsRow("每日工作时长") {
                Picker("", selection: $model.workHours) {
                    ForEach(Array(stride(from: 6.0, through: 12.0, by: 0.5)), id: \.self) { h in
                        Text(Self.hoursText(h)).tag(h)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            SettingsDivider()
            SettingsRow("参考上班时间") {
                TimeField(date: referenceStartBinding)
            }
            SettingsDivider()
            SettingsRow("参考下班时间") { ValueText(model.defaultEndTimeText) }
        }
    }

    // MARK: - 喝水提醒

    @ViewBuilder
    private var waterRows: some View {
            SettingsRow("喝水提醒") { SettingsSwitch(isOn: $reminders.waterEnabled) }
            if reminders.waterEnabled {
                SettingsDivider()
                SettingsRow("提醒间隔") {
                    Picker("", selection: $reminders.waterIntervalMinutes) {
                        ForEach(ReminderModel.waterIntervals, id: \.self) { Text(Self.minutesText($0)).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                SettingsRow("仅在上班时提醒") { SettingsSwitch(isOn: $reminders.waterOnlyDuringWork) }
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
                SettingsRow("出现时机") {
                    Picker("", selection: $reminders.eggMode) {
                        ForEach(EggMode.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                switch reminders.eggMode {
                case .interval:
                    SettingsRow("间隔") {
                        Picker("", selection: $reminders.eggIntervalMinutes) {
                            ForEach(ReminderModel.eggIntervals, id: \.self) { Text(Self.minutesText($0)).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    SettingsDivider()
                    SettingsRow("仅在上班时出现") { SettingsSwitch(isOn: $reminders.eggOnlyDuringWork) }
                case .random:
                    SettingsRow("每天次数") {
                        Picker("", selection: $reminders.eggRandomCount) {
                            ForEach(ReminderModel.eggCounts, id: \.self) { Text("\($0) 次").tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                case .fixedTime:
                    SettingsRow("时间") { TimeField(date: eggTimeBinding) }
                    SettingsDivider()
                    SettingsRow("仅在上班时出现") { SettingsSwitch(isOn: $reminders.eggOnlyDuringWork) }
                case .beforeOffWork:
                    SettingsRow("提前") {
                        Picker("", selection: $reminders.eggLeadMinutes) {
                            ForEach(ReminderModel.eggLeadOptions, id: \.self) {
                                Text($0 == 0 ? "下班那一刻" : "下班前 \($0) 分钟").tag($0)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                SettingsDivider()
                videoRow(.egg)
            }
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

    private var eggTimeBinding: Binding<Date> {
        Binding(
            get: { ReminderModel.time(reminders.eggFixedTimeText, on: Date()) ?? Date() },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                reminders.eggFixedTimeText = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            }
        )
    }

    private static func minutesText(_ m: Int) -> String {
        m >= 60 && m % 60 == 0 ? "每 \(m / 60) 小时" : (m > 60 ? "每 \(m / 60) 小时 \(m % 60) 分" : "每 \(m) 分钟")
    }

    // MARK: - 绑定

    private var startBinding: Binding<Date> {
        Binding(get: { model.todayStartTime ?? Date() },
                set: { model.setStartTime($0) })
    }

    /// 把 "HH:mm" 字符串绑定成 Date，供时间选择器使用
    private var referenceStartBinding: Binding<Date> {
        Binding(
            get: {
                let parts = model.defaultStartTimeText.split(separator: ":").compactMap { Int($0) }
                return Calendar.current.date(bySettingHour: parts.first ?? 0,
                                             minute: parts.count > 1 ? parts[1] : 0,
                                             second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                model.defaultStartTimeText = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
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

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SettingsPalette.card)
            )
    }
}

/// 一行：左侧标签，右侧控件
struct SettingsRow<Trailing: View>: View {
    let label: String
    @ViewBuilder let trailing: Trailing

    init(_ label: String, @ViewBuilder trailing: () -> Trailing) {
        self.label = label
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 13))
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, SettingsMetrics.inset)
        .frame(minHeight: 40)
    }
}

/// 系统设置风格的小开关
struct SettingsSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
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
    var body: some View {
        Rectangle()
            .fill(SettingsPalette.separator)
            .frame(height: 0.5)
            .padding(.horizontal, SettingsMetrics.inset)
    }
}

/// 配色取自 macOS 系统设置深色模式（窗口 #2A2928 / 卡片 #353332），整体再压深一档
enum SettingsPalette {
    static let window = Color(red: 0x22 / 255, green: 0x21 / 255, blue: 0x20 / 255)     // #222120
    static let card = Color(red: 0x2D / 255, green: 0x2B / 255, blue: 0x2A / 255)       // #2D2B2A
    static let separator = Color.white.opacity(0.07)
}

/// 无边框时间选择器：只显示数字和右侧上下箭头，数字底下没有输入框
/// SwiftUI 的 DatePicker 去不掉边框，所以直接包一层 NSDatePicker
struct TimeField: NSViewRepresentable {
    @Binding var date: Date
    var minDate: Date? = nil
    var maxDate: Date? = nil

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
        picker.setAccessibilityLabel("时间")
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

/// 主题色色块：仿 macOS「强调色」选择器，选中时外圈描边
struct ThemeSwatch: View {
    let theme: AppTheme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(theme.accentColor)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.15), lineWidth: 0.5))
                .overlay {
                    if selected {
                        Circle().fill(.white).frame(width: 6, height: 6)
                    }
                }
                .padding(3)
                .overlay(Circle().strokeBorder(selected ? theme.accentColor.opacity(0.6) : .clear, lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(theme.rawValue)
        .accessibilityLabel(theme.rawValue)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
