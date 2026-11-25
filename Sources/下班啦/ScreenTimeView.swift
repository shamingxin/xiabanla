import SwiftUI

final class ScreenTimeState: ObservableObject {
    @Published var period: ScreenTimePeriod = ScreenTimePeriod.defaultPeriod
    @Published var selectedDate = WorkTimerModel.workdayBase(for: Date())
}

enum ReminderTab: String, CaseIterable {
    case water = "喝水"
    case rest = "休息"
    case offWork = "下班"
}

final class SettingsNavigationState: ObservableObject {
    @Published var selectedSection: SettingsSidebarItem = .workHours
    @Published var selectedReminderTab: ReminderTab = .water
}

/// 仅统计下班啦记录的工作与喝水行为，不读取系统 App 使用时间。
struct ScreenTimeView: View {
    typealias Period = ScreenTimePeriod
    @ObservedObject var model: WorkTimerModel
    @ObservedObject var state: ScreenTimeState
    let activity: ActivityStore
    @ObservedObject var reminders: ReminderModel
    @Environment(\.themeAccent) private var accent
    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            ScreenTimeCard {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(primaryTitle).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        Text(primaryDurationText).font(.system(size: 30, weight: .medium, design: .rounded)).monospacedDigit()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(compareTitle).font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(compareText).font(.system(size: 12, weight: .medium)).foregroundStyle(compareHasData ? .primary : .secondary)
                    }
                }
                if period == .day {
                    DailyPresenceMetrics(text: DailyPresenceMetricText(summary: dailyPresenceSummary))
                        .padding(.top, 5)
                }
                if period == .week {
                    Text("每天的在岗时间").font(.system(size: 11)).foregroundStyle(.secondary)
                    WorkWeekChart(values: weekChartValues, labels: weekChartLabels, average: weekAverage, accent: accent)
                    .frame(height: 122).padding(.top, 5)
                }
                HStack {
                    Text(period == .day ? "当天在岗" : "本周平均在岗").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Text(period == .day ? primaryDurationText : duration(weekAverage)).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                }.padding(.top, 4)
            }
            if reminders.waterTrackingEnabled {
                WaterIntakeCard(period: period,
                                daySummary: waterIntakeSummary,
                                weeklySummary: weeklyWaterIntakeSummary,
                                day: selectedDay,
                                showQuickAdd: period == .day,
                                canAdd: isCurrentWaterFocusDay,
                                onAdd: { reminders.addWater($0) })
            }
            VStack(alignment: .leading, spacing: 0) {
                SettingsHeader(period == .day ? "当天喝水记录" : "本周喝水记录")
                ScreenTimeCard {
                    MetricRow(title: "喝水完成", value: "\(waterSummary.completed) 次", color: .blue)
                    SettingsDivider()
                    MetricRow(title: "还不渴", value: "\(waterSummary.deferred) 次", color: .orange)
                    SettingsDivider()
                    MetricRow(title: "提醒弹出", value: "\(waterSummary.prompted) 次", color: .gray)
                }
            }
        }
    }

    private var period: Period { state.period }
    private var selectedDate: Date { state.selectedDate }
    private var selectedDay: Date { calendar.startOfDay(for: selectedDate) }
    private var primaryTitle: String { period == .day ? (calendar.isDateInToday(selectedDay) ? "今天的在岗时间" : "\(selectedDay.formatted(.dateTime.month().day())) 的在岗时间") : "本周累计在岗时间" }
    private var primarySeconds: TimeInterval { period == .day ? workSeconds(on: selectedDay) : weekValues.reduce(0, +) }
    private var primaryDurationText: String {
        period == .day && dailyPresenceSummary.creditedSeconds == nil ? "未记录" : duration(primarySeconds)
    }
    private var compareTitle: String { period == .day ? "与昨天比" : "与上周比" }
    private var compareReference: TimeInterval {
        if period == .day { return workSeconds(on: calendar.date(byAdding: .day, value: -1, to: selectedDay)!) }
        return weekAverage(for: calendar.date(byAdding: .day, value: -7, to: weekStart)!)
    }
    private var compareHasData: Bool { period == .day ? dailyPresenceSummary.creditedSeconds != nil && compareReference > 0 : compareReference > 0 }
    private var compareText: String {
        guard compareHasData else { return period == .day ? "暂无昨天数据" : "暂无上周数据" }
        let change = Int(((primarySeconds - compareReference) / compareReference * 100).rounded())
        if change == 0 { return "与上一周期持平" }
        return change > 0 ? "多 \(change)%" : "少 \(-change)%"
    }
    private var weekStart: Date {
        let weekday = calendar.component(.weekday, from: selectedDay)
        return calendar.date(byAdding: .day, value: weekday == 1 ? -6 : 2 - weekday, to: selectedDay)!
    }
    private var weekValues: [TimeInterval] { (0..<7).map { workSeconds(on: calendar.date(byAdding: .day, value: $0, to: weekStart)!) } }
    private var weekChartDates: [Date] {
        (0..<7).compactMap { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: weekStart)!
            return model.autoStartWeekdays.contains(calendar.component(.weekday, from: day)) ? day : nil
        }
    }
    private var weekChartValues: [TimeInterval] { weekChartDates.map(workSeconds(on:)) }
    private var weekChartLabels: [String] {
        weekChartDates.map { WorkweekChartLabels.label(for: calendar.component(.weekday, from: $0)) }
    }
    private var weekAverage: TimeInterval { weekAverage(for: weekStart) }
    private var isCurrentWaterFocusDay: Bool {
        workdayKey(forCalendarDay: selectedDay) == WorkTimerModel.workdayKey(for: model.now)
    }
    private var waterIntakeSummary: WaterIntakeSummary {
        WaterIntakeSummary(consumedMilliliters: activity.waterMilliliters(workday: workdayKey(forCalendarDay: selectedDay)),
                           goalMilliliters: reminders.dailyWaterGoalMilliliters)
    }
    private var weeklyWaterIntakeSummary: WeeklyWaterIntakeSummary {
        WeeklyWaterIntakeSummary(dailyMilliliters: (0..<7).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: weekStart)!
            return activity.waterMilliliters(workday: workdayKey(forCalendarDay: day))
        })
    }
    private var dailyPresenceSummary: DailyPresenceSummary {
        let key = workdayKey(forCalendarDay: selectedDay)
        return DailyPresenceSummary.make(segments: activity.officePresenceSegments(workday: key),
                                         countdownArrival: session(on: selectedDay)?.startedAt,
                                         plannedSeconds: session(on: selectedDay)?.plannedSeconds,
                                         now: model.now,
                                         isCurrentWorkday: key == WorkTimerModel.workdayKey(for: model.now))
    }
    private var waterSummary: ActivityDaySummary {
        if period == .day { return activity.summary(for: selectedDay) }
        return (0..<7).reduce(ActivityDaySummary()) { partial, offset in
            let next = activity.summary(for: calendar.date(byAdding: .day, value: offset, to: weekStart)!)
            return ActivityDaySummary(prompted: partial.prompted + next.prompted, completed: partial.completed + next.completed, deferred: partial.deferred + next.deferred)
        }
    }
    private func session(on day: Date) -> WorkSession? {
        let key = workdayKey(forCalendarDay: day)
        // 优先使用开始当天已写入的计划工时，避免用户午后修改全局设置而回算当天加班。
        if let saved = activity.workSession(workday: key) { return saved }
        if key == WorkTimerModel.workdayKey(for: Date()), let start = model.todayStartTime {
            return WorkSession(workday: key, startedAt: start, plannedSeconds: model.workHours * 3600)
        }
        return nil
    }
    private func workSeconds(on day: Date) -> TimeInterval {
        let todayStart = calendar.startOfDay(for: Date())
        guard day <= todayStart else { return 0 }
        guard let session = session(on: day) else { return 0 }
        let key = workdayKey(forCalendarDay: day)
        let segments = activity.officePresenceSegments(workday: key)
        if !segments.isEmpty {
            return DailyPresenceSummary.make(segments: segments,
                                             countdownArrival: session.startedAt,
                                             plannedSeconds: session.plannedSeconds,
                                             now: model.now,
                                             isCurrentWorkday: key == WorkTimerModel.workdayKey(for: model.now))
                .creditedSeconds ?? 0
        }
        return ScreenTimeDuration.seconds(for: activity.officePresenceSession(workday: key),
                                          plannedSeconds: session.plannedSeconds,
                                          now: model.now,
                                          isCurrentWorkday: key == WorkTimerModel.workdayKey(for: model.now),
                                          fallbackStartedAt: model.todayStartTime)
    }
    private func weekAverage(for start: Date) -> TimeInterval {
        let values = (0..<7).map { workSeconds(on: calendar.date(byAdding: .day, value: $0, to: start)!) }.filter { $0 > 0 }
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
    /// UI 选的是自然日；取中午再交给凌晨 5 点分界的工作日逻辑，避免午夜被归到前一天。
    private func workdayKey(forCalendarDay day: Date) -> String {
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        return WorkTimerModel.workdayKey(for: noon)
    }
    private func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分钟" : "\(minutes) 分钟"
    }
}

struct ScreenTimeToolbar: View {
    @ObservedObject var state: ScreenTimeState
    private let calendar = Calendar.current
    var body: some View {
        HStack(spacing: 7) {
            Menu {
                Button("按天查看") { state.period = .day }
                Button("按周查看") { state.period = .week }
            } label: {
                Text(state.period == .day ? state.selectedDate.formatted(.dateTime.month().day()) : weekRange)
                    .font(.system(size: 13, weight: .medium)).padding(.horizontal, 10).frame(height: 28)
            }.menuStyle(.borderlessButton).fixedSize().settingsHoverFeedback(cornerRadius: 7).accessibilityLabel("选择按天或按周查看")
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.bordered).settingsHoverFeedback(cornerRadius: 7)
            Button(state.period == .day ? "今天" : "本周") { state.selectedDate = WorkTimerModel.workdayBase(for: Date()) }.buttonStyle(.bordered).settingsHoverFeedback(cornerRadius: 7)
            Button { shift(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.bordered).settingsHoverFeedback(cornerRadius: 7)
        }
    }
    private var weekRange: String {
        let weekday = calendar.component(.weekday, from: state.selectedDate)
        let monday = calendar.date(byAdding: .day, value: weekday == 1 ? -6 : 2 - weekday, to: state.selectedDate)!
        let sunday = calendar.date(byAdding: .day, value: 6, to: monday)!
        return "\(Self.rangeDateFormatter.string(from: monday)) - \(Self.rangeDateFormatter.string(from: sunday))"
    }
    private static let rangeDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M.d"
        return formatter
    }()
    private func shift(_ amount: Int) { state.selectedDate = calendar.date(byAdding: .day, value: state.period == .day ? amount : amount * 7, to: state.selectedDate) ?? state.selectedDate }
}

private struct ScreenTimeCard<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.settingsPalette) private var palette
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { VStack(alignment: .leading, spacing: 9) { content }.padding(14).background(RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius, style: .continuous).fill(palette.card)) }
}

private struct DailyPresenceMetrics: View {
    let text: DailyPresenceMetricText
    @Environment(\.settingsPalette) private var palette
    @Environment(\.themeAccent) private var accent

    var body: some View {
        HStack(spacing: 9) {
            metric(title: "到岗时间", value: text.arrival)
            metric(title: "下班时间", value: text.departure)
            metric(title: "加班时长", value: text.overtime, emphasize: text.overtime != "—")
        }
    }

    private func metric(title: String, value: String, emphasize: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(emphasize ? accent : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }
}

private struct WaterIntakeCard: View {
    let period: ScreenTimePeriod
    let daySummary: WaterIntakeSummary
    let weeklySummary: WeeklyWaterIntakeSummary
    let day: Date
    let showQuickAdd: Bool
    let canAdd: Bool
    let onAdd: (Int) -> Void
    @Environment(\.themeAccent) private var accent
    @Environment(\.settingsPalette) private var palette

    private let quickAmounts = [100, 200, 250, 330, 500]

    private var totalMilliliters: Int {
        period == .day ? daySummary.consumedMilliliters : weeklySummary.totalMilliliters
    }

    private var progress: Double {
        if period == .day { return Double(daySummary.percentage) / 100 }
        let weeklyGoal = max(1, daySummary.goalMilliliters * 7)
        return min(1, Double(weeklySummary.totalMilliliters) / Double(weeklyGoal))
    }

    private var title: String {
        period == .day ? day.formatted(.dateTime.month().day()) + " 饮水量" : "本周饮水量"
    }

    private var detail: String {
        period == .day
            ? "完成 \(daySummary.percentage)% · 还差 \(daySummary.remainingMilliliters) ml"
            : "平均每天 \(weeklySummary.averageDailyMilliliters) ml"
    }

    var body: some View {
        ScreenTimeCard {
            HStack(alignment: .center, spacing: 18) {
                WaterGlass(progress: progress, color: accent)
                    .frame(width: 72, height: 104)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text("\(totalMilliliters)")
                            .font(.system(size: 30, weight: .medium, design: .rounded))
                            .monospacedDigit()
                        Text("ml").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    }
                    Text(detail)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    if period == .week {
                        Text(weeklySummary.message)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            if showQuickAdd {
                Text("快捷补记").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 3)
                HStack(spacing: 7) {
                    ForEach(quickAmounts, id: \.self) { amount in
                        Button { onAdd(amount) } label: {
                            Text("+\(amount)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 28)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(accent)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(accent.opacity(0.13)))
                        .disabled(!canAdd)
                        .settingsHoverFeedback(cornerRadius: 9)
                        .accessibilityLabel("补记 \(amount) 毫升")
                    }
                }
            }
        }
    }
}

private struct WaterGlass: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let waterHeight = max(5, geo.size.height * CGFloat(min(1, max(0, progress))))
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(color.opacity(0.08))
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(color.opacity(0.78))
                    .frame(height: waterHeight)
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(color.opacity(0.45), lineWidth: 1)
            }
        }
    }
}

private struct WorkWeekChart: View {
    let values: [TimeInterval]; let labels: [String]; let average: TimeInterval; let accent: Color
    @State private var hoveredIndex: Int?
    var body: some View { GeometryReader { geo in
        let axisWidth: CGFloat = 42
        let chartWidth = max(0, geo.size.width - axisWidth)
        let top: CGFloat = 8, labelHeight: CGFloat = 18
        let plotHeight = max(0, geo.size.height - top - labelHeight)
        let peak = max(values.max() ?? 0, average)
        let maximum = max(12 * 3600, ceil(peak / (3 * 3600)) * 3 * 3600)
        let averageY = top + plotHeight - CGFloat(average / maximum) * plotHeight
        HStack(alignment: .top, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<3) { _ in
                        Divider().overlay(Color.secondary.opacity(0.22))
                        Spacer()
                    }
                    Divider().overlay(Color.secondary.opacity(0.22))
                }
                .padding(.top, top)
                .padding(.bottom, labelHeight)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: averageY))
                    path.addLine(to: CGPoint(x: chartWidth, y: averageY))
                }
                .stroke(Color.green.opacity(0.78), style: StrokeStyle(lineWidth: 1.3, dash: [4, 5]))
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(values.indices, id: \.self) { i in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(values[i] > 0 ? accent : Color.secondary.opacity(0.14))
                                .brightness(hoveredIndex == i ? 0.14 : 0)
                                .frame(height: max(2, CGFloat(values[i] / maximum) * plotHeight))
                                .scaleEffect(hoveredIndex == i ? 1.06 : 1, anchor: .bottom)
                                // overlay 不参与柱状图的排版，避免提示文字把该列撑宽。
                                .overlay(alignment: .top) {
                                    if hoveredIndex == i {
                                        Text("周\(labels[i])\n\(workDuration(values[i]))")
                                            .font(.system(size: 10, weight: .medium))
                                            .multilineTextAlignment(.center)
                                            .fixedSize()
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 5)
                                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.84)))
                                            .foregroundStyle(.white)
                                            .offset(y: -38)
                                    }
                                }
                                .animation(.easeOut(duration: 0.14), value: hoveredIndex == i)
                            Text(labels[i]).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .contentShape(Rectangle())
                        .onHover { hovering in hoveredIndex = hovering ? i : nil }
                        .zIndex(hoveredIndex == i ? 1 : 0)
                    }
                }
                .padding(.top, top)
            }
            .frame(width: chartWidth, height: geo.size.height)
            VStack(alignment: .leading, spacing: 0) {
                Text(duration(maximum)).frame(maxHeight: .infinity, alignment: .topLeading)
                Text(duration(maximum / 2)).frame(maxHeight: .infinity, alignment: .center)
                Text("0").frame(height: labelHeight, alignment: .bottomLeading)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .frame(width: axisWidth, height: geo.size.height)
            .overlay(alignment: .center) {
                Text("平均").font(.system(size: 10, weight: .medium)).foregroundStyle(.green)
                    .offset(y: averageY - geo.size.height / 2)
            }
        }
    }.accessibilityLabel("本周每天在岗时间") }

    private func duration(_ seconds: TimeInterval) -> String {
        "\(Int(seconds / 3600)) 小时"
    }

    private func workDuration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分钟" : "\(minutes) 分钟"
    }
}

private struct MetricRow: View { let title: String; let value: String; let color: Color; var body: some View { HStack { Circle().fill(color).frame(width: 7, height: 7); Text(title).font(.system(size: 13)); Spacer(); Text(value).font(.system(size: 13, weight: .semibold)).monospacedDigit() }.padding(.vertical, 3) } }
