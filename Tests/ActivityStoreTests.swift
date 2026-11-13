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
check("历史未结束记录回退计划时长", ScreenTimeDuration.seconds(for: openPresence,
      plannedSeconds: 9 * 3600, now: date(13, 9), isCurrentWorkday: false), 9 * 3600)
check("在岗时间默认显示本周", ScreenTimePeriod.defaultPeriod, .week)

print(failures == 0 ? "全部通过" : "失败 \(failures) 项")
exit(failures == 0 ? 0 : 1)
