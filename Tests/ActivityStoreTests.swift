import Foundation

var failures = 0

func check<T: Equatable>(_ name: String, _ actual: T, _ expected: T) {
    let passed = actual == expected
    print((passed ? "✅" : "❌") + " " + name)
    if !passed { failures += 1 }
}

let calendar = Calendar(identifier: .gregorian)
func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

let databaseURL = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("xiabanla-activity-\(UUID().uuidString).sqlite")
defer { try? FileManager.default.removeItem(at: databaseURL) }

let store = ActivityStore(databaseURL: databaseURL)
store.record(kind: .water, action: .prompted, at: date(10, 9, 15))
store.record(kind: .water, action: .completed, at: date(10, 9, 16))
store.record(kind: .water, action: .deferred, at: date(10, 11, 30))
store.record(kind: .water, action: .completed, at: date(11, 9, 30))

let tenth = store.summary(for: date(10, 12))
check("当天记录提醒弹出", tenth.prompted, 1)
check("当天记录喝水完成", tenth.completed, 1)
check("当天记录暂不喝水", tenth.deferred, 1)
check("没有事件的日期为零", store.summary(for: date(12, 12)).total, 0)

let records = store.events(on: date(10, 12))
check("按发生时间返回当天记录", records.map(\.action), [.prompted, .completed, .deferred])
check("跨日记录不会混入", records.count, 3)

// 饮水量独立于提醒回应次数，按凌晨 5:00 划分后的工作日 key 归档。
store.recordWater(milliliters: 200, workday: "2026-11-10", at: date(10, 10))
store.recordWater(milliliters: 100, workday: "2026-11-10", at: date(10, 14))
store.recordWater(milliliters: 250, workday: "2026-11-11", at: date(11, 9))
check("同一工作日累计饮水量", store.waterMilliliters(workday: "2026-11-10"), 300)
check("快捷补记可并入饮水量", store.waterMilliliters(workday: "2026-11-11"), 250)
check("饮水量不跨工作日混入", store.waterMilliliters(workday: "2026-11-12"), 0)
let waterProgress = WaterIntakeSummary(consumedMilliliters: 200, goalMilliliters: 1800)
check("饮水进度按目标计算", waterProgress.percentage, 11)
check("饮水剩余量不为负数", waterProgress.remainingMilliliters, 1600)
let completedWaterProgress = WaterIntakeSummary(consumedMilliliters: 2000, goalMilliliters: 1800)
check("饮水进度最高为百分之百", completedWaterProgress.percentage, 100)
check("完成目标后剩余量归零", completedWaterProgress.remainingMilliliters, 0)

store.recordWorkStart(workday: "2026-11-10", at: date(10, 10), plannedSeconds: 9 * 3600)
let session = store.workSession(workday: "2026-11-10")
check("保存每日上班起点", session?.startedAt, date(10, 10))
check("保存当日计划工时", session?.plannedSeconds, 9 * 3600)

store.recordOfficePresenceStart(workday: "2026-11-10", at: date(10, 9))
store.recordOfficePresenceEnd(workday: "2026-11-10", at: date(10, 20, 58))
let presence = store.officePresenceSession(workday: "2026-11-10")
check("保存实际在岗起点", presence?.startedAt, date(10, 9))
check("保存实际在岗终点", presence?.endedAt, date(10, 20, 58))
store.recordOfficePresenceEnd(workday: "2026-11-10", at: date(10, 22))
check("首次离开后不覆盖结束", store.officePresenceSession(workday: "2026-11-10")?.endedAt, date(10, 20, 58))
check("实际在岗时间不再封顶计划时长",
      presence?.endedAt?.timeIntervalSince(presence!.startedAt), 11 * 3600 + 58 * 60)

let completedForWeek = store.completedOfficeSessions(from: "2026-11-10", through: "2026-11-16")
check("按周只读取已封存实际在岗记录", completedForWeek.count, 1)
check("按周读取保留计划工时", completedForWeek.first?.plannedSeconds, 9 * 3600)
check("按周读取保留实际在岗时长", completedForWeek.first?.presenceSeconds, 11 * 3600 + 58 * 60)

let bufferedHappinessDay = "2026-11-11"
store.recordWorkStart(workday: bufferedHappinessDay, at: date(11, 10, 30), plannedSeconds: 9 * 3600)
store.recordOfficePresenceStart(workday: bufferedHappinessDay, at: date(11, 10, 40))
store.recordOfficePresenceEnd(workday: bufferedHappinessDay, at: date(11, 19, 35))
check("已封存记录把缓冲计入幸福指数", store.completedOfficeSessions(from: bufferedHappinessDay,
      through: bufferedHappinessDay).first?.presenceSeconds, 9 * 3600 + 5 * 60)
store.recordWorkStart(workday: bufferedHappinessDay, at: date(11, 10, 30), plannedSeconds: 8 * 3600)
check("当天开始后修改基础工时不改写计划快照", store.workSession(workday: bufferedHappinessDay)?.plannedSeconds, 9 * 3600)

let manualWorkday = "2026-11-13"
store.recordManualWorkStart(workday: manualWorkday,
                            countdownStartedAt: date(13, 10, 15),
                            plannedSeconds: 9 * 3600,
                            presenceStartedAt: date(13, 10, 20))
check("手动开始保存倒计时起点", store.workSession(workday: manualWorkday)?.startedAt, date(13, 10, 15))
check("手动开始同时保存真实在岗起点", store.officePresenceSession(workday: manualWorkday)?.startedAt, date(13, 10, 20))
store.recordOfficePresenceEnd(workday: manualWorkday, at: date(13, 21, 30))
check("手动开始后睡眠可封存真实终点", store.officePresenceSession(workday: manualWorkday)?.endedAt, date(13, 21, 30))

let segmentedWorkday = "2026-11-14"
store.startOfficePresenceSegment(workday: segmentedWorkday, at: date(14, 10))
store.endOpenOfficePresenceSegment(workday: segmentedWorkday, at: date(14, 19))
store.startOfficePresenceSegment(workday: segmentedWorkday, at: date(14, 20, 30))
store.endOpenOfficePresenceSegment(workday: segmentedWorkday, at: date(14, 21, 30))
store.endOpenOfficePresenceSegment(workday: segmentedWorkday, at: date(14, 22))
check("下班后重启会追加第二段在岗", store.officePresenceSegments(workday: segmentedWorkday).count, 2)
check("重复睡眠不覆盖第二段终点", store.officePresenceSegments(workday: segmentedWorkday).last?.endedAt, date(14, 21, 30))
check("睡眠间隔不计入当天在岗", store.officePresenceSeconds(workday: segmentedWorkday, now: date(14, 23), includeOpenSegment: false), 10 * 3600)

let independentWorkday = "2026-11-12"
store.recordOfficePresenceStart(workday: independentWorkday, at: date(12, 9))
check("不依赖倒计时也能保存实际在岗起点",
      store.officePresenceSession(workday: independentWorkday)?.startedAt, date(12, 9))

let openPresence = OfficePresenceSession(workday: "2026-11-12", startedAt: date(12, 9), endedAt: nil)
check("当天未结束时按当前时刻累计", ScreenTimeDuration.seconds(for: openPresence,
      plannedSeconds: 9 * 3600, now: date(12, 18), isCurrentWorkday: true), 9 * 3600)
check("当天缺少真实会话时按倒计时起点累计", ScreenTimeDuration.seconds(for: nil,
      plannedSeconds: 9 * 3600, now: date(12, 19, 0), isCurrentWorkday: true,
      fallbackStartedAt: date(12, 10, 18)), 8 * 3600 + 42 * 60)
check("历史未结束记录不伪造计划时长", ScreenTimeDuration.seconds(for: openPresence,
      plannedSeconds: 9 * 3600, now: date(13, 9), isCurrentWorkday: false), 0)

let completedSummary = DailyPresenceSummary.make(
    segments: [OfficePresenceSegment(id: 1, workday: "2026-11-14",
                                     startedAt: date(14, 9), endedAt: date(14, 18, 30))],
    countdownArrival: date(14, 8, 55), plannedSeconds: 9 * 3600,
    now: date(14, 22), isCurrentWorkday: false)
check("按天摘要到岗时间跟随缓冲后的倒计时起点", completedSummary.arrivalTime, date(14, 8, 55))
check("按天摘要显示下班时间", completedSummary.departure, .recorded(date(14, 18, 30)))
check("按天摘要把缓冲时间计入加班时长", completedSummary.overtimeSeconds, 35 * 60)

let bufferedDurationSummary = DailyPresenceSummary.make(
    segments: [OfficePresenceSegment(id: 1, workday: "2026-11-16",
                                     startedAt: date(16, 10, 40), endedAt: date(16, 19, 35))],
    countdownArrival: date(16, 10, 30), plannedSeconds: 9 * 3600,
    now: date(16, 22), isCurrentWorkday: false)
check("缓冲时间计入当天在岗累计", bufferedDurationSummary.creditedSeconds, 9 * 3600 + 5 * 60)
check("缓冲时间后加班正确", bufferedDurationSummary.overtimeSeconds, 5 * 60)

let multiSegmentSummary = DailyPresenceSummary.make(
    segments: [OfficePresenceSegment(id: 1, workday: "2026-11-14", startedAt: date(14, 9), endedAt: date(14, 12)),
               OfficePresenceSegment(id: 2, workday: "2026-11-14", startedAt: date(14, 13), endedAt: date(14, 20))],
    plannedSeconds: 9 * 3600, now: date(14, 22), isCurrentWorkday: false)
check("按天摘要取最早到岗", multiSegmentSummary.arrivalTime, date(14, 9))
check("按天摘要取最后下班", multiSegmentSummary.departure, .recorded(date(14, 20)))
check("按天摘要不把间隔算作加班", multiSegmentSummary.overtimeSeconds, 60 * 60)

let openSummary = DailyPresenceSummary.make(
    segments: [OfficePresenceSegment(id: 1, workday: "2026-11-14", startedAt: date(14, 9), endedAt: nil)],
    plannedSeconds: 9 * 3600, now: date(14, 19, 30), isCurrentWorkday: true)
check("当天开放片段显示仍在岗", openSummary.departure, .stillPresent)
check("当天开放片段计算加班", openSummary.overtimeSeconds, 90 * 60)

let historicalOpenSummary = DailyPresenceSummary.make(
    segments: [OfficePresenceSegment(id: 1, workday: "2026-11-14", startedAt: date(14, 9), endedAt: nil)],
    plannedSeconds: 9 * 3600, now: date(15, 9), isCurrentWorkday: false)
check("历史开放片段显示记录未结束", historicalOpenSummary.departure, .incomplete)
check("历史开放片段不展示不完整累计", historicalOpenSummary.creditedSeconds, nil)

let unavailableSummary = DailyPresenceSummary.make(segments: [], plannedSeconds: 9 * 3600,
                                                    now: date(14, 22), isCurrentWorkday: false)
check("没有真实记录不虚构到岗时间", unavailableSummary.arrivalTime, nil)
check("没有真实记录不虚构下班时间", unavailableSummary.departure, .unavailable)
check("没有真实记录不虚构加班时长", unavailableSummary.overtimeSeconds, nil)

let emptyToday = DailyPresenceSummary.make(segments: [], plannedSeconds: 9 * 3600,
                                           now: date(26, 5), isCurrentWorkday: true)
check("新工作日还未到岗时累计为零", emptyToday.creditedSeconds, 0)
check("历史日期缺少片段时保留未记录", unavailableSummary.creditedSeconds, nil)
let firstMinute = DailyPresenceSummary.make(
    segments: [OfficePresenceSegment(id: 1, workday: "2026-11-26", startedAt: date(26, 10), endedAt: nil)],
    plannedSeconds: nil, now: date(26, 10).addingTimeInterval(59), isCurrentWorkday: true)
check("刚开始的前 59 秒累计不足一分钟", firstMinute.creditedSeconds, 59)
check("新工作日尚未饮水时饮水量为零", store.waterMilliliters(workday: "2026-11-26"), 0)

let noPlanSummary = DailyPresenceSummary.make(
    segments: [OfficePresenceSegment(id: 1, workday: "2026-11-14", startedAt: date(14, 9), endedAt: date(14, 20))],
    plannedSeconds: nil, now: date(14, 22), isCurrentWorkday: false)
check("没有计划工时不虚构加班时长", noPlanSummary.overtimeSeconds, nil)

let completedMetricText = DailyPresenceMetricText(summary: completedSummary)
check("按天摘要格式化缓冲后的到岗时间", completedMetricText.arrival, "08:55")
check("按天摘要格式化下班时间", completedMetricText.departure, "18:30")
check("按天摘要格式化加班时长", completedMetricText.overtime, "35 分钟")
let openMetricText = DailyPresenceMetricText(summary: openSummary)
check("按天摘要在岗状态文案", openMetricText.departure, "仍在岗")
let unavailableMetricText = DailyPresenceMetricText(summary: unavailableSummary)
check("按天摘要缺失记录文案", unavailableMetricText.arrival, "未记录")
check("按天摘要未加班显示横线", DailyPresenceMetricText(summary: DailyPresenceSummary.make(
    segments: [OfficePresenceSegment(id: 1, workday: "2026-11-14", startedAt: date(14, 9), endedAt: date(14, 17))],
    plannedSeconds: 9 * 3600, now: date(14, 22), isCurrentWorkday: false)).overtime, "—")
check("在岗时间默认显示当天", ScreenTimePeriod.defaultPeriod, .day)
let selection = ScreenTimeState()
let nov25 = date(25, 0), nov26 = date(26, 0), nov27 = date(27, 0)
check("启动当天显示当前工作日", selection.selectedDay(currentWorkday: nov25), nov25)
check("跨工作日自动显示 26 日", selection.selectedDay(currentWorkday: nov26), nov26)
selection.shift(-1, currentWorkday: nov26)
check("查看历史时跨天仍显示原日期", selection.selectedDay(currentWorkday: nov27), nov25)
selection.showCurrent()
check("点今天后继续跟随工作日", selection.selectedDay(currentWorkday: nov27), nov27)
selection.period = .week
selection.shift(-1, currentWorkday: nov26)
check("翻到上周后保留所选周", selection.selectedDay(currentWorkday: nov27), date(19, 0))
selection.shift(1, currentWorkday: nov26)
check("翻回当前日期后恢复跟随", selection.selectedDay(currentWorkday: nov27), nov27)

let weeklyWater = WeeklyWaterIntakeSummary(dailyMilliliters: [900, 1200, 0, 500, 0, 0, 0], workedDays: 3)
check("周饮水累计所有日期", weeklyWater.totalMilliliters, 2600)
check("周饮水按实际计时天数平均", weeklyWater.averageDailyMilliliters, 867)
check("计时但未饮水的日期计入平均", WeeklyWaterIntakeSummary(dailyMilliliters: [900, 0, 0], workedDays: 2).averageDailyMilliliters, 450)
check("没有计时的日期不显示日均", WeeklyWaterIntakeSummary(dailyMilliliters: [500, 0], workedDays: 0).averageDailyMilliliters, nil)
check("周饮水文案提供杯数换算", weeklyWater.message(variant: 0).contains("杯"), true)
check("周图只显示周一至周五", WorkweekChartLabels.selectedLabels(for: [2, 3, 4, 5, 6]), ["一", "二", "三", "四", "五"])
check("周图按当前上班日排序", WorkweekChartLabels.selectedLabels(for: [1, 3, 5]), ["二", "四", "日"])

print(failures == 0 ? "全部通过" : "失败 \(failures) 项")
exit(failures == 0 ? 0 : 1)
