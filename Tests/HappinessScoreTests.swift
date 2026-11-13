import Foundation

var failures = 0

func check<T: Equatable>(_ name: String, _ actual: T, _ expected: T) {
    let passed = actual == expected
    print((passed ? "✅" : "❌") + " " + name)
    if !passed { failures += 1 }
}

let onTime = HappinessScore.Session(workday: "2026-11-10",
                                    plannedSeconds: 9 * 3600,
                                    presenceSeconds: 9 * 3600)
let oneHourOver = HappinessScore.Session(workday: "2026-11-11",
                                         plannedSeconds: 9 * 3600,
                                         presenceSeconds: 10 * 3600)
let twoHoursOver = HappinessScore.Session(workday: "2026-11-12",
                                          plannedSeconds: 9 * 3600,
                                          presenceSeconds: 11 * 3600)

check("准时下班满分", HappinessScore.dailyScore(for: onTime), 100)
check("加班一小时得 70 分", HappinessScore.dailyScore(for: oneHourOver), 70)
check("加班两小时得 40 分", HappinessScore.dailyScore(for: twoHoursOver), 40)
check("提前下班不超过满分", HappinessScore.dailyScore(for: .init(workday: "2026-11-13", plannedSeconds: 9 * 3600, presenceSeconds: 8 * 3600)), 100)
check("超长加班不低于零分", HappinessScore.dailyScore(for: .init(workday: "2026-11-14", plannedSeconds: 9 * 3600, presenceSeconds: 20 * 3600)), 0)

let summary = HappinessScore.weeklySummary(sessions: [onTime, oneHourOver, twoHoursOver])
check("本周分数按每日平均后四舍五入", summary.score, 70)
check("准时下班天数", summary.onTimeDays, 1)
check("累计加班时长", summary.overtimeSeconds, 3 * 3600)
check("70 分称号", summary.tier, .some("幸福被偷走一点"))
check("空周没有虚构分数", HappinessScore.weeklySummary(sessions: []).score, nil)

print(failures == 0 ? "全部通过" : "失败 \(failures) 项")
exit(failures == 0 ? 0 : 1)
