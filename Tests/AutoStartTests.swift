// 自动计时判定测试：./Tests/run.sh
// 测纯函数 shouldAutoStart / launchCountsAsLogin / autoStartArrival，以及每日检查机会 AutoStartGate
// 真实锁屏/解锁通知时序仍需真机验收
import Foundation

var fails = 0
let cal = Calendar.current
func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int, _ mi: Int) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: day, hour: h, minute: mi))!
}
func check(_ name: String, _ got: Bool, _ want: Bool) {
    print((got == want ? "✅" : "❌") + " " + name)
    if got != want { fails += 1 }
}
func auto(_ at: Date, enabled: Bool = true, mode: WorkMode = .flexible, arrived: Bool = false,
          days: Set<Int> = WorkTimerModel.defaultAutoStartWeekdays) -> Bool {
    WorkTimerModel.shouldAutoStart(at: at, enabled: enabled, mode: mode, hasArrived: arrived,
                                   weekdays: days, startText: "10:00", latestText: "12:00")
}

print("— 倒计时样式 —")
check("待机时钟样式可选", CountdownStyle.allCases.contains(.standbyClock), true)
check("待机时钟持久化值", CountdownStyle.standbyClock.rawValue == "待机时钟", true)

// 2026-11-13 周五，11-14 周六，11-12 周四；上班区间 10:00–12:00
print("— 判定条件 —")
check("周五 09:50 → 开始", auto(d(2026,11,13,9,50)), true)
check("周五 10:25 → 开始", auto(d(2026,11,13,10,25)), true)
check("09:00 窗口起点 → 开始", auto(d(2026,11,13,9,0)), true)
check("12:00 窗口终点 → 开始", auto(d(2026,11,13,12,0)), true)
check("08:30 太早 → 不开始", auto(d(2026,11,13,8,30)), false)
check("12:10 太晚 → 不开始", auto(d(2026,11,13,12,10)), false)
check("周四加班到周五 01:00 → 不开始", auto(d(2026,11,13,1,0)), false)
check("周六未勾选 → 不开始", auto(d(2026,11,14,10,0)), false)
check("周六已勾选 → 开始", auto(d(2026,11,14,10,0), days: [7]), true)
check("开关关闭 → 不开始", auto(d(2026,11,13,10,0), enabled: false), false)
check("固定模式 → 不开始", auto(d(2026,11,13,10,0), mode: .fixed), false)
check("今天已到岗 → 不改写", auto(d(2026,11,13,10,0), arrived: true), false)

print("— 启动是否算开机登录 —")
let login = d(2026,11,13,9,48)
check("登录时打开 + 登录后 1 分钟启动 → 算", WorkTimerModel.launchCountsAsLogin(
    launchAtLogin: true, loginTime: login, now: d(2026,11,13,9,49)), true)
check("未开登录时打开，手动启动 → 不算", WorkTimerModel.launchCountsAsLogin(
    launchAtLogin: false, loginTime: login, now: d(2026,11,13,9,49)), false)
check("登录 2 小时后才手动打开 → 不算", WorkTimerModel.launchCountsAsLogin(
    launchAtLogin: true, loginTime: login, now: d(2026,11,13,11,48)), false)
check("读不到登录时间 → 不算", WorkTimerModel.launchCountsAsLogin(
    launchAtLogin: true, loginTime: nil, now: d(2026,11,13,9,49)), false)

print("— 到工位缓冲 —")
func arrival(_ at: Date, on: Bool, _ minutes: Int = 5) -> Date {
    WorkTimerModel.autoStartArrival(at: at, bufferEnabled: on, bufferMinutes: minutes)
}
/// 和 WorkTimerModel.effectiveStart 相同的弹性钳制，用来核对下班时间
func offWork(_ arrival: Date, day: Int) -> Date {
    let s = d(2026,11,day,10,0), l = d(2026,11,day,12,0)
    return min(max(arrival, s), l).addingTimeInterval(9 * 3600)
}
func checkTime(_ name: String, _ got: Date, _ want: Date) {
    print((got == want ? "✅" : "❌") + " " + name)
    if got != want { fails += 1 }
}
checkTime("缓冲关闭：10:25 记录 10:25", arrival(d(2026,11,13,10,25), on: false), d(2026,11,13,10,25))
checkTime("缓冲 5 分钟：10:25 记录 10:20", arrival(d(2026,11,13,10,25), on: true), d(2026,11,13,10,20))
checkTime("缓冲 5 分钟：10:25 下班 19:20", offWork(arrival(d(2026,11,13,10,25), on: true), day: 13), d(2026,11,13,19,20))
checkTime("缓冲 5 分钟：09:50 记录 09:45", arrival(d(2026,11,13,9,50), on: true), d(2026,11,13,9,45))
checkTime("缓冲 5 分钟：09:50 下班仍 19:00", offWork(arrival(d(2026,11,13,9,50), on: true), day: 13), d(2026,11,13,19,0))
checkTime("缓冲 5 分钟：11:58 下班 20:53", offWork(arrival(d(2026,11,13,11,58), on: true), day: 13), d(2026,11,13,20,53))
checkTime("缓冲 15 分钟：10:25 记录 10:10", arrival(d(2026,11,13,10,25), on: true, 15), d(2026,11,13,10,10))
checkTime("回拨不越过凌晨 3 点分界", arrival(d(2026,11,13,3,5), on: true, 15), d(2026,11,13,3,0))
check("可选值为 1/3/5/10/15，默认 5", WorkTimerModel.commuteBufferOptions == [1,3,5,10,15]
      && WorkTimerModel.defaultCommuteBufferMinutes == 5, true)
// 缓冲不参与判定：shouldAutoStart 没有缓冲参数，08:30 / 12:10 仍不开始（见上方判定条件用例）

print("— 每个工作日只检查一次 —")
let suite = "xiabanla.tests.\(UUID().uuidString)"
let store = UserDefaults(suiteName: suite)!
defer { store.removePersistentDomain(forName: suite) }
let fri = WorkTimerModel.workdayKey(for: d(2026,11,13,10,0))
let sat = WorkTimerModel.workdayKey(for: d(2026,11,14,10,0))

var gate = AutoStartGate(defaults: store)
check("只亮锁屏（没有解锁证据）→ 不消耗检查机会", gate.takeCheck(workday: fri, active: true), false)
check("只亮锁屏后今天仍未检查", gate.hasChecked(workday: fri), false)
gate.confirmUnlock()
check("第一次有效解锁（离开仅几分钟也算）→ 检查", gate.takeCheck(workday: fri, active: true), true)
gate.confirmUnlock()
check("当天再次锁屏再解锁 → 不再检查（太早/太晚也不补触发）", gate.takeCheck(workday: fri, active: true), false)
gate = AutoStartGate(defaults: store)
gate.confirmUnlock()
check("重启 App 后同一天 → 检查机会不恢复", gate.takeCheck(workday: fri, active: true), false)
check("凌晨 3 点后新工作日 → 检查机会重置", gate.takeCheck(workday: sat, active: true), false)
gate.confirmUnlock()
check("新工作日有效解锁 → 检查", gate.takeCheck(workday: sat, active: true), true)
let sun = WorkTimerModel.workdayKey(for: d(2026,11,15,10,0))
gate.confirmUnlock()
check("自动计时关闭时解锁 → 不检查", gate.takeCheck(workday: sun, active: false), false)
check("自动计时关闭时不占用当天检查机会", gate.hasChecked(workday: sun), false)
check("周五 02:59 仍属周四工作日", WorkTimerModel.workdayKey(for: d(2026,11,13,2,59)) == WorkTimerModel.workdayKey(for: d(2026,11,12,10,0)), true)
check("周五 03:00 起属周五工作日", WorkTimerModel.workdayKey(for: d(2026,11,13,3,0)) == fri, true)

print(fails == 0 ? "全部通过" : "失败 \(fails) 项")
exit(fails == 0 ? 0 : 1)
