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
    @State private var inspectedDay: Date?
    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            VStack(alignment: .leading, spacing: 0) {
              SettingsHeader(primaryTitle)
              ScreenTimeCard {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
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
                    HStack {
                        Text("每天的在岗时间")
                        Spacer()
                        Text("点击日期查看明细")
                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                    WorkWeekChart(days: chartDays, average: weekAverage, accent: accent, selection: $inspectedDay)
                    .frame(height: 122).padding(.top, 5)
                }
                if period == .week {
                    HStack {
                        Text("本周平均在岗").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Text(duration(weekAverage)).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                    }.padding(.top, 4)
                }
              }
            }
            if period == .week, let inspectedDay, weekChartDates.contains(inspectedDay) {
                inspectedDayCard(for: inspectedDay)
            }
            if reminders.waterTrackingEnabled {
              VStack(alignment: .leading, spacing: 0) {
                SettingsHeader(waterTitle)
                WaterIntakeCard(period: period,
                                daySummary: waterIntakeSummary,
                                weeklySummary: weeklyWaterIntakeSummary,
                                showQuickAdd: period == .day,
                                canAdd: isCurrentWaterFocusDay,
                                onAdd: { reminders.addWater($0) })
                    .id(selectedDay)
              }
            }
        }
        .onChange(of: weekStart) { _ in inspectedDay = nil }
        .onChange(of: period) { _ in inspectedDay = nil }
    }

    private func inspectedDayCard(for date: Date) -> some View {
        let presence = presenceSummary(on: date)
        let detail = DailyPresenceMetricText(summary: presence)
        let weekday = WorkweekChartLabels.label(for: calendar.component(.weekday, from: date))
        return ScreenTimeCard {
            HStack {
                Text("\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日 · 周\(weekday)")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let seconds = presence.creditedSeconds {
                    Text("在岗 \(duration(seconds))").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                detailColumn("到岗时间", value: detail.arrival)
                detailColumn("下班时间", value: detail.departure)
                if reminders.waterTrackingEnabled {
                    let amount = activity.waterMilliliters(workday: workdayKey(forCalendarDay: date))
                    detailColumn("饮水量", value: amount > 0 ? "\(amount.formatted()) ml" : "未记录")
                }
            }
        }
    }

    private func detailColumn(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 14, weight: .medium, design: .rounded)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var period: Period { state.period }
    private var selectedDate: Date { state.selectedDate }
    private var selectedDay: Date { calendar.startOfDay(for: selectedDate) }
    private var primaryTitle: String { period == .day ? (calendar.isDateInToday(selectedDay) ? "今日在岗时间" : "\(selectedDay.formatted(.dateTime.month().day())) 在岗时间") : "本周在岗时间" }
    private var waterTitle: String { period == .day ? (calendar.isDateInToday(selectedDay) ? "今日饮水量" : "\(selectedDay.formatted(.dateTime.month().day())) 饮水量") : "本周饮水量" }
    private var primarySeconds: TimeInterval { period == .day ? workSeconds(on: selectedDay) : weekValues.reduce(0, +) }
    private var primaryDurationText: String {
        period == .day && dailyPresenceSummary.creditedSeconds == nil ? "未记录" : duration(primarySeconds)
    }
    private var compareTitle: String { period == .day ? "与昨天比" : "与上周比" }
    private var compareReference: TimeInterval {
        if period == .day { return workSeconds(on: calendar.date(byAdding: .day, value: -1, to: selectedDay)!) }
        return (1...7).reduce(0) { total, offset in
            total + workSeconds(on: calendar.date(byAdding: .day, value: -offset, to: weekStart)!)
        }
    }
    private var compareHasData: Bool { period == .day ? dailyPresenceSummary.creditedSeconds != nil && compareReference > 0 : compareReference > 0 }
    private var compareText: String {
        guard compareHasData else { return period == .day ? "暂无昨天数据" : "暂无上周数据" }
        let change = Int(((primarySeconds - compareReference) / compareReference * 100).rounded())
        if change == 0 { return period == .day ? "与昨天持平" : "与上周持平" }
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
    private var chartDays: [WeekChartDay] {
        weekChartDates.map { date in
            WeekChartDay(date: date, label: WorkweekChartLabels.label(for: calendar.component(.weekday, from: date)),
                         seconds: workSeconds(on: date))
        }
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
        }, workedDays: weekValues.filter { $0 > 0 }.count)
    }
    private var dailyPresenceSummary: DailyPresenceSummary { presenceSummary(on: selectedDay) }
    private func presenceSummary(on day: Date) -> DailyPresenceSummary {
        let key = workdayKey(forCalendarDay: day)
        let workSession = session(on: day)
        return DailyPresenceSummary.make(segments: activity.officePresenceSegments(workday: key),
                                         countdownArrival: workSession?.startedAt,
                                         plannedSeconds: workSession?.plannedSeconds,
                                         now: model.now,
                                         isCurrentWorkday: key == WorkTimerModel.workdayKey(for: model.now))
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
    let showQuickAdd: Bool
    let canAdd: Bool
    let onAdd: (Int) -> Void
    @Environment(\.themeAccent) private var accent
    @Environment(\.settingsPalette) private var palette
    @Environment(\.colorScheme) private var scheme

    @State private var hoveredAmount: Int?
    @State private var messageVariant = Int.random(in: 0..<3)
    private let quickAmounts = [100, 200, 250, 330, 500]
    private var total: Int { period == .day ? daySummary.consumedMilliliters : weeklySummary.totalMilliliters }
    private var goal: Int { daySummary.goalMilliliters * (period == .day ? 1 : 7) }
    private var progress: Double { min(1, max(0, Double(total) / Double(max(1, goal)))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(period == .day ? "已饮用" : "本周累计")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    HStack(alignment: .lastTextBaseline, spacing: 5) {
                        Text(total.formatted())
                            .font(.system(size: 40, weight: .medium, design: .rounded))
                            .monospacedDigit()
                        Text("ml").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                    }
                    .lineLimit(1).minimumScaleFactor(0.76)
                    .padding(.vertical, 10)
                    if period == .day {
                        Text(progress >= 1
                             ? "目标 \(goal.formatted()) ml · 已达标"
                             : "目标 \(goal.formatted()) ml · 还剩 \(daySummary.remainingMilliliters.formatted()) ml")
                            .lineLimit(1).minimumScaleFactor(0.75)
                    } else {
                        Text(weeklySummary.averageDailyMilliliters.map { "在岗日日均 \($0.formatted()) ml" } ?? "在岗日日均 —")
                        Text(weeklySummary.message(variant: messageVariant)).foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 12))
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                WaterGlass(progress: progress, moving: period == .day && canAdd, color: accent)
                    .frame(width: 80, height: 110)
                    .overlay {
                        if period == .day {
                            Text("\(daySummary.percentage)%")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(progress >= 0.48 ? Color.white : (scheme == .dark ? Color.white : Color.primary))
                                .shadow(color: progress >= 0.48 ? .black.opacity(0.35) : .clear, radius: 2)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(period == .day ? "饮水目标完成 \(daySummary.percentage)%" : "本周饮水进度")
                    .padding(.horizontal, 12)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background {
                LinearGradient(colors: [.clear, accent.opacity(scheme == .dark ? 0.15 : 0.09)],
                               startPoint: .leading, endPoint: .trailing)
            }

            if showQuickAdd {
                Rectangle().fill(palette.separator).frame(height: 1)
                VStack(alignment: .leading, spacing: 8) {
                    Text("快捷补记（ml）").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    HStack(spacing: 7) {
                        ForEach(quickAmounts, id: \.self) { amount in
                            Button { onAdd(amount) } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "plus").font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(canAdd ? Color.white : Color.secondary)
                                    Text(String(amount)).font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(canAdd ? Color.white : Color.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 28)
                                .background(RoundedRectangle(cornerRadius: 7).fill(canAdd ? accent.opacity(scheme == .dark ? 0.82 : 0.9) : palette.card))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(Color.white.opacity(canAdd && hoveredAmount == amount ? 0.20 : 0))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 7)
                                                .strokeBorder(Color.white.opacity(canAdd && hoveredAmount == amount ? 0.42 : 0), lineWidth: 1)
                                        }
                                        .allowsHitTesting(false)
                                }
                                .animation(.easeOut(duration: 0.14), value: hoveredAmount == amount)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                hoveredAmount = hovering && canAdd ? amount : nil
                            }
                            .disabled(!canAdd)
                            .accessibilityLabel("补记 \(amount) 毫升")
                        }
                    }
                }.padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
        .background(palette.card)
        .clipShape(RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius, style: .continuous))
    }
}

/// 以杯口、收窄的杯壁和实心杯底界定液体的可用空间。
private struct GlassOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        return Path { path in
            path.move(to: CGPoint(x: 0, y: 0.05*h))
            path.addQuadCurve(to: CGPoint(x: w, y: 0.05*h), control: CGPoint(x: w/2, y: -0.035*h))
            path.addLine(to: CGPoint(x: 0.90*w, y: 0.90*h))
            path.addQuadCurve(to: CGPoint(x: 0.80*w, y: 0.97*h), control: CGPoint(x: 0.89*w, y: 0.96*h))
            path.addQuadCurve(to: CGPoint(x: 0.20*w, y: 0.97*h), control: CGPoint(x: w/2, y: 1.01*h))
            path.addQuadCurve(to: CGPoint(x: 0.10*w, y: 0.90*h), control: CGPoint(x: 0.11*w, y: 0.96*h))
            path.closeSubpath()
        }
    }
}

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

private struct WaterGlass: View {
    let progress: Double
    let moving: Bool
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let glint = Color(nsColor: .white)
        let edge = scheme == .dark ? glint.opacity(0.48) : color.opacity(0.35)
        ZStack {
            Ellipse().fill(color.opacity(0.16))
                .frame(width: 65, height: 7).blur(radius: 3).offset(y: 53)
            GlassOutline().fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0.04), color.opacity(0.16)],
                                               startPoint: .leading, endPoint: .trailing))
            TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || !moving || progress == 0 || activeState == .inactive)) { context in
                let phase = reduceMotion || !moving ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 5) * 2 * .pi / 5
                ZStack {
                    WaterSurface(level: progress, phase: phase + 2.3)
                        .fill(Color.cyan.opacity(0.65))
                    WaterSurface(level: progress, phase: phase)
                        .fill(LinearGradient(colors: [.cyan, color], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: progress)
            }
            .clipShape(GlassOutline())
            Canvas { context, size in
                let w = size.width, h = size.height
                var markings = Path()
                for index in 1...5 {
                    let y = h * Double(index + 1) / 8
                    let x = w * (0.86 - 0.06 * y / h)
                    markings.move(to: CGPoint(x: x, y: y))
                    markings.addLine(to: CGPoint(x: x - (index.isMultiple(of: 2) ? 5 : 8), y: y))
                }
                context.stroke(markings, with: .color(edge), lineWidth: 1)
                var reflection = Path()
                reflection.move(to: CGPoint(x: w * 0.09, y: h * 0.18))
                reflection.addLine(to: CGPoint(x: w * 0.12, y: h * 0.48))
                context.stroke(reflection, with: .color(glint.opacity(0.56)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            GlassOutline().stroke(edge, lineWidth: 0.85)
            VStack {
                Ellipse().fill(glint.opacity(0.08)).overlay(Ellipse().stroke(edge, lineWidth: 0.85))
                    .frame(height: 9).padding(.top, 1)
                Spacer()
            }
        }
        .accessibilityHidden(true)
    }
}

private struct WeekChartDay {
    let date: Date
    let label: String
    let seconds: TimeInterval
}

private struct WorkWeekChart: View {
    let days: [WeekChartDay]
    let average: TimeInterval
    let accent: Color
    @Binding var selection: Date?
    @State private var hoveredDay: Date?
    var body: some View { GeometryReader { geo in
        let axisWidth: CGFloat = 42
        let chartWidth = max(0, geo.size.width - axisWidth)
        let top: CGFloat = 8, labelHeight: CGFloat = 18
        let plotHeight = max(0, geo.size.height - top - labelHeight)
        let peak = max(days.map(\.seconds).max() ?? 0, average)
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
                    ForEach(days, id: \.date) { day in
                        let isSelected = selection == day.date
                        Button { selection = day.date } label: {
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(day.seconds > 0 ? accent : Color.secondary.opacity(0.14))
                                    .brightness(hoveredDay == day.date ? 0.14 : 0)
                                    .frame(height: max(2, CGFloat(day.seconds / maximum) * plotHeight))
                                    .scaleEffect(hoveredDay == day.date ? 1.06 : 1, anchor: .bottom)
                                    // overlay 不参与柱状图的排版，避免提示文字把该列撑宽。
                                    .overlay(alignment: .top) {
                                        if hoveredDay == day.date {
                                            Text("周\(day.label)\n\(workDuration(day.seconds))")
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
                                    .animation(.easeOut(duration: 0.14), value: hoveredDay == day.date)
                                Text(day.label)
                                    .font(.system(size: 10, weight: isSelected ? .bold : .regular))
                                    .foregroundStyle(isSelected ? Color.primary : .secondary)
                                    .frame(width: 24, height: 16)
                                    .background(Capsule().fill(isSelected ? accent.opacity(0.26) : .clear))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .contentShape(Rectangle())
                            .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? accent.opacity(0.11) : .clear))
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in hoveredDay = hovering ? day.date : nil }
                        .accessibilityLabel("周\(day.label)，在岗\(workDuration(day.seconds))")
                        .accessibilityHint("查看当天明细")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .zIndex(hoveredDay == day.date ? 1 : 0)
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
