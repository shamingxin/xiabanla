import Foundation
import Combine
import AppKit
import SwiftUI
import CoreGraphics

/// 背景样式（深浅模式）：深色 / 浅色
/// 曾支持「图片」第三态（.image），已下线；枚举保留该 case 仅用于老用户数据迁移兜底，不再对外暴露入口
enum AppBackground: String, CaseIterable, Identifiable, Codable {
    case dark = "黑色"
    case light = "白色"
    case image = "图片"

    var id: String { rawValue }
}

/// 主题色预设：控制开关、倒计时数字、选中态等强调色；用户也可以自定义十六进制颜色
/// 「已下班」固定绿色不受此影响（CardPalette.overtime 写死）
enum AccentPreset: String, CaseIterable, Identifiable {
    case neonGreen = "荧光绿"
    case rhineBlue = "莱茵蓝"
    case yellow = "黄"
    case pink = "粉"
    case red = "红"

    var id: String { rawValue }

    /// 预设色值（不含 #）
    var hex: String {
        switch self {
        case .neonGreen: return "39FF14"
        case .rhineBlue: return "0057FF"
        case .yellow: return "FED501"
        case .pink: return "FF6B9D"
        case .red: return "FF3B30"
        }
    }
}

/// 倒计时主卡片的数字呈现样式，只影响主卡片（CountdownCardView），不影响「今日工作」点阵面板
enum CountdownStyle: String, CaseIterable, Identifiable, Codable {
    /// 翻页数字牌：现状默认样式，数字变化时上下翻片
    case flip = "翻页"
    /// 仿灵动岛：粗体无衬线裸数字，变化时弹性缩放跳动
    case dynamicIsland = "灵动岛"
    /// 仿 iPhone 待机显示：深蓝十位与浅蓝个位，变化时自下接位、旧值上移淡出
    case standbyClock = "待机时钟"

    var id: String { rawValue }
}

/// 工时模式
/// - 弹性：在上班区间内到岗，满工作时长可下班；早于区间按开始算，晚于区间按结束算
/// - 固定：每天固定时间下班，和到岗早晚无关
enum WorkMode: String, CaseIterable, Identifiable {
    case flexible
    case fixed

    var id: String { rawValue }
    var title: String { self == .flexible ? "弹性" : "固定" }
}

/// 下班倒计时核心模型
///
/// 一个「工作日」从凌晨 5:00 开始，到次日 5:00 结束。
final class WorkTimerModel: ObservableObject {
    private let activityStore: ActivityStore

    /// 新工作日的分界点（凌晨 5 点）
    static let dayCutoffHour = 5
    static let autoStartEarliestHour = 5
    static let defaultStartText = "10:00"
    static let defaultLatestText = "12:00"
    /// 自动开始的默认上班日：周一至周五（Calendar weekday，1 = 周日 … 7 = 周六）
    static let defaultAutoStartWeekdays: Set<Int> = [2, 3, 4, 5, 6]
    /// 到工位缓冲：可选分钟数与默认值
    static let commuteBufferOptions = [1, 3, 5, 10, 15]
    static let defaultCommuteBufferMinutes = 5

    // MARK: - 持久化的设置项

    /// 工时模式，新用户默认弹性
    @Published var workMode: WorkMode {
        didSet {
            UserDefaults.standard.set(workMode.rawValue, forKey: Keys.workMode)
        }
    }

    /// 每日工作时长（小时），默认 9 小时
    @Published var workHours: Double {
        didSet { UserDefaults.standard.set(workHours, forKey: Keys.workHours) }
    }

    /// 上班时间："HH:mm"。固定模式下是上班时间，弹性模式下是上班区间的开始
    @Published private(set) var startText: String {
        didSet { UserDefaults.standard.set(startText, forKey: Keys.startTime) }
    }

    /// 弹性模式上班区间的结束（最晚按这个时间起算），"HH:mm"
    @Published private(set) var latestText: String {
        didSet { UserDefaults.standard.set(latestText, forKey: Keys.latestTime) }
    }

    /// 是否开机自动启动
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin)
            LoginItemManager.setEnabled(launchAtLogin)
        }
    }

    /// 背景样式
    @Published var background: AppBackground {
        didSet { UserDefaults.standard.set(background.rawValue, forKey: Keys.background) }
    }

    /// 自定义背景图片的本地路径（background == .image 时使用）
    @Published var backgroundImagePath: String? {
        didSet {
            if let path = backgroundImagePath {
                UserDefaults.standard.set(path, forKey: Keys.backgroundImagePath)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.backgroundImagePath)
            }
        }
    }

    /// 主题色十六进制字符串（不含 #），默认黄色，兼容老用户的固定黄色强调色
    @Published var accentColorHex: String {
        didSet { UserDefaults.standard.set(accentColorHex, forKey: Keys.accentColorHex) }
    }

    /// 主题色实际颜色；十六进制解析失败时退回默认黄色
    var accentColor: Color {
        Self.color(fromHex: accentColorHex) ?? Self.color(fromHex: AccentPreset.yellow.hex)!
    }

    var accentNSColor: NSColor { NSColor(accentColor) }

    /// 倒计时主卡片样式，默认沿用现状「翻页」
    @Published var countdownStyle: CountdownStyle {
        didSet { UserDefaults.standard.set(countdownStyle.rawValue, forKey: Keys.countdownStyle) }
    }

    /// 弹性模式下早晨回到电脑前自动开始上班；默认关闭，老用户升级后仍手动开始
    @Published var autoStartEnabled: Bool {
        didSet { UserDefaults.standard.set(autoStartEnabled, forKey: Keys.autoStartEnabled) }
    }

    /// 自动开始的上班日（Calendar weekday），按工作日（凌晨 5 点分界）判断是星期几
    @Published var autoStartWeekdays: Set<Int> {
        didSet { UserDefaults.standard.set(autoStartWeekdays.sorted(), forKey: Keys.autoStartWeekdays) }
    }

    /// 到工位缓冲：自动开始成功时，把上班时间往前回拨一段（楼下打卡到解锁 Mac 的时间）；默认关闭
    /// 只影响自动开始记录的时间，不参与「是否自动开始」的判断，手动开始/补填不回拨
    @Published var commuteBufferEnabled: Bool {
        didSet { UserDefaults.standard.set(commuteBufferEnabled, forKey: Keys.commuteBufferEnabled) }
    }

    /// 到工位缓冲分钟数，取值见 commuteBufferOptions
    @Published var commuteBufferMinutes: Int {
        didSet { UserDefaults.standard.set(commuteBufferMinutes, forKey: Keys.commuteBufferMinutes) }
    }

    // MARK: - 当日状态

    /// 今天实际到岗时间，nil 表示今天还没记录
    @Published private(set) var todayStartTime: Date?

    /// 当前时间（定时刷新用于驱动倒计时 UI）
    @Published private(set) var now: Date = Date()
    @Published private(set) var isResting = false
    @Published private(set) var isWaitingForUnlock = false

    /// 下班后不计入「公司倒欠你」的秒数：熄屏、睡眠、关机、App 没运行的时段
    private var pausedSeconds: Double = 0
    /// 上一次计时心跳的时间，用来发现睡眠/关机造成的空档
    private var lastAlive: Date?
    /// 屏幕是否已熄灭（系统没睡、只是熄屏时计时器还在跑，需要单独判断）
    private var screenAsleep = false
    /// 自动计时的解锁证据 + 每个工作日一次的检查机会（持久化）
    private let autoStartGate = AutoStartGate()
    /// 收到非公开锁屏通知、还没收到解锁通知：视为仍在锁屏（和会话锁定状态双重保护，拿不准就不自动开始）
    private var lockedByNotification = false
    private var restingUnlockActive = false
    /// 当前工作日标识，变化时清空当日状态
    private var workdayKey: String

    private var timer: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    private enum Keys {
        static let workMode = "workMode"
        static let workHours = "workHours"
        /// 沿用旧版「参考上班时间」的 key，老用户升级后设置不丢
        static let startTime = "defaultStartTime"
        static let latestTime = "latestStartTime"
        static let launchAtLogin = "launchAtLogin"
        static let background = "background"
        static let backgroundImagePath = "backgroundImagePath"
        static let accentColorHex = "accentColorHex"
        static let countdownStyle = "countdownStyle"
        static let todayStartTime = "todayStartTime"
        static let todayStartDay = "todayStartDay"
        static let pausedSeconds = "overtimePausedSeconds"
        static let pausedDay = "overtimePausedDay"
        static let lastAlive = "lastAlive"
        static let autoStartEnabled = "autoStartEnabled"
        static let autoStartWeekdays = "autoStartWeekdays"
        /// 旧版「离开开始时间」，4 小时规则已移除，启动时清掉
        static let legacyAwayStart = "awayStart"
        static let commuteBufferEnabled = "autoStartCommuteBufferEnabled"
        static let commuteBufferMinutes = "autoStartCommuteBufferMinutes"
    }

    init(activityStore: ActivityStore = ActivityStore()) {
        self.activityStore = activityStore
        let defaults = UserDefaults.standard
        self.workMode = WorkMode(rawValue: defaults.string(forKey: Keys.workMode) ?? "") ?? .flexible
        self.workHours = defaults.object(forKey: Keys.workHours) as? Double ?? 9.0
        self.startText = defaults.string(forKey: Keys.startTime) ?? Self.defaultStartText
        self.latestText = defaults.string(forKey: Keys.latestTime) ?? Self.defaultLatestText
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        var restoredBackground = AppBackground(rawValue: defaults.string(forKey: Keys.background) ?? "") ?? .dark
        // 图片背景已下线：老用户如果停留在图片态，自动回退深色，不再读取图片路径
        if restoredBackground == .image { restoredBackground = .dark }
        self.background = restoredBackground
        self.backgroundImagePath = defaults.string(forKey: Keys.backgroundImagePath)
        self.accentColorHex = defaults.string(forKey: Keys.accentColorHex) ?? AccentPreset.yellow.hex
        self.countdownStyle = CountdownStyle(rawValue: defaults.string(forKey: Keys.countdownStyle) ?? "") ?? .flip
        self.autoStartEnabled = defaults.bool(forKey: Keys.autoStartEnabled)
        self.autoStartWeekdays = (defaults.array(forKey: Keys.autoStartWeekdays) as? [Int]).map(Set.init)
            ?? Self.defaultAutoStartWeekdays
        self.commuteBufferEnabled = defaults.bool(forKey: Keys.commuteBufferEnabled)
        let savedBuffer = defaults.integer(forKey: Keys.commuteBufferMinutes)
        self.commuteBufferMinutes = Self.commuteBufferOptions.contains(savedBuffer)
            ? savedBuffer : Self.defaultCommuteBufferMinutes
        self.workdayKey = Self.workdayKey(for: Date())

        // 老数据里区间可能是反的（旧版没有区间结束），直接恢复默认
        if Self.minutes(latestText) < Self.minutes(startText) {
            latestText = max(startText, Self.defaultLatestText)
        }

        restoreTodayState()
        if let start = todayStartTime {
            activityStore.recordWorkStart(workday: workdayKey, at: start, plannedSeconds: workHours * 3600)
        }
        // 非正常关机/强制结束时来不及收到睡眠或退出通知：下次启动用最后一次心跳封存。
        // 只在已过计划下班时处理，不能把下班前的异常退出伪造成“已下班”。
        if activityStore.hasOpenOfficePresenceSegment(workday: workdayKey),
           let lastAlive,
           Self.shouldRecoverOpenOfficePresence(lastAlive: lastAlive, plannedEnd: endTime) {
            activityStore.endOpenOfficePresenceSegment(workday: workdayKey, at: lastAlive)
        }
        isResting = activityStore.hasCompletedOfficePresenceSegment(workday: workdayKey)
            && !activityStore.hasOpenOfficePresenceSegment(workday: workdayKey)
        // 这台 App 只在公司电脑使用：下班后已封存、同一工作日再次启动 App，
        // 就表示用户回到公司继续加班。新片段从本次启动开始，绝不把关机间隔算进去。
        let launchedAt = Date()
        if isResting,
           Self.shouldResumeOfficePresence(at: launchedAt, plannedEnd: endTime,
                                           hasCompletedSegment: activityStore.hasCompletedOfficePresenceSegment(workday: workdayKey)) {
            activityStore.startOfficePresenceSegment(workday: workdayKey, at: launchedAt)
            isResting = false
        }
        observeScreen()
        startClock()
    }

    deinit {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
    }

    // MARK: - 设置

    /// 修改上班时间。弹性模式下如果区间结束早于开始，恢复默认区间并返回 false（由界面弹 toast）
    @discardableResult
    func setStartText(_ text: String) -> Bool {
        if workMode == .fixed {
            startText = text
            // 固定模式看不到区间结束，悄悄跟上，切回弹性时不会出现反向区间
            if Self.minutes(latestText) < Self.minutes(text) { latestText = text }
            return true
        }
        return applyRange(start: text, latest: latestText)
    }

    /// 修改弹性区间结束。早于区间开始时恢复默认区间并返回 false
    @discardableResult
    func setLatestText(_ text: String) -> Bool {
        applyRange(start: startText, latest: text)
    }

    private func applyRange(start: String, latest: String) -> Bool {
        guard Self.minutes(latest) >= Self.minutes(start) else {
            startText = Self.defaultStartText
            latestText = Self.defaultLatestText
            return false
        }
        startText = start
        latestText = latest
        return true
    }

    /// 用户点击「开始上班」；到工位缓冲开启时，往前回拨到到岗时间
    func startWork() {
        let clickedAt = Date()
        setStartTime(Self.autoStartArrival(at: clickedAt, bufferEnabled: commuteBufferEnabled,
                                           bufferMinutes: commuteBufferMinutes),
                     presenceStartedAt: clickedAt)
    }

    /// 设置或修改今天的到岗时间（随时可在设置里补填、修改）
    /// 只取时分，落在当前工作日；晚于现在时按现在算
    func setStartTime(_ date: Date, presenceStartedAt: Date? = nil) {
        let current = Date()
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        var start = Calendar.current.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0,
                                          of: Self.workdayBase(for: current)) ?? date
        // 0~5 点属于当前工作日的「次日凌晨」
        if (c.hour ?? 0) < Self.dayCutoffHour { start = start.addingTimeInterval(24 * 3600) }
        start = min(start, current)
        todayStartTime = start
        now = current
        let defaults = UserDefaults.standard
        defaults.set(start, forKey: Keys.todayStartTime)
        defaults.set(workdayKey, forKey: Keys.todayStartDay)
        if let presenceStartedAt {
            activityStore.recordManualWorkStart(workday: workdayKey, countdownStartedAt: start,
                                                plannedSeconds: workHours * 3600,
                                                presenceStartedAt: presenceStartedAt)
        } else {
            activityStore.recordWorkStart(workday: workdayKey, at: start, plannedSeconds: workHours * 3600)
        }
    }

    // MARK: - 计时

    private func restoreTodayState() {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: Keys.todayStartDay) == workdayKey,
           let saved = defaults.object(forKey: Keys.todayStartTime) as? Date {
            todayStartTime = saved
        }
        if defaults.string(forKey: Keys.pausedDay) == workdayKey {
            pausedSeconds = defaults.double(forKey: Keys.pausedSeconds)
        }
        lastAlive = defaults.object(forKey: Keys.lastAlive) as? Date
        defaults.removeObject(forKey: Keys.legacyAwayStart)
        // 登录项在登录后不久拉起 = 用户刚输完密码，算一次有效回到桌面
        // 手动打开 App（或登录很久后才启动）不算，用户在场可以自己点
        if Self.launchCountsAsLogin(launchAtLogin: launchAtLogin, loginTime: Self.consoleLoginTime(), now: Date()) {
            autoStartGate.confirmUnlock()
            if isResting { restingUnlockActive = true }
        }
        tick(Date())
    }

    /// 熄屏 / 睡眠时暂停「公司倒欠你」
    private func observeScreen() {
        let center = NSWorkspace.shared.notificationCenter
        let sleepNames: [Notification.Name] = [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification]
        let wakeNames: [Notification.Name] = [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification]
        for name in sleepNames {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.endOfficePresenceIfNeeded(at: Date())
                self?.screenAsleep = true
                self?.restingUnlockActive = false
                self?.autoStartGate.revokeUnlock()
            })
        }
        for name in wakeNames {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.tick(Date())
                self?.screenAsleep = false
            })
        }

        // 非公开的锁屏/解锁通知：只用来辅助判断「还在锁屏」，不当作唯一依据
        let distributed = DistributedNotificationCenter.default()
        distributedObservers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"),
                                                            object: nil, queue: .main) { [weak self] _ in
            self?.lockedByNotification = true
            self?.restingUnlockActive = false
            self?.autoStartGate.revokeUnlock()
        })
        distributedObservers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"),
                                                            object: nil, queue: .main) { [weak self] _ in
            self?.lockedByNotification = false
            self?.autoStartGate.confirmUnlock()
            if self?.isResting == true { self?.restingUnlockActive = true }
            self?.tick(Date())
        })
    }

    /// 有效回到桌面（有解锁证据 + 屏幕亮着且未锁定）时，消耗今天唯一一次检查机会
    /// 只亮锁屏界面时桌面条件不满足，不会消耗证据和检查机会，等真正解锁再处理
    private func checkAutoStart(_ date: Date) {
        guard autoStartGate.unlockConfirmed, !screenAsleep, !lockedByNotification,
              !Self.sessionIsLocked() else { return }
        // 公司电脑在下班后再次有效解锁：这是新的加班片段，不是第二次“早晨自动开始”。
        // 不消耗 AutoStartGate，直到凌晨 05:00 前都可睡眠后继续累计，离线间隔不算工时。
        if isResting,
           Self.shouldResumeOfficePresence(at: date, plannedEnd: endTime,
                                           hasCompletedSegment: activityStore.hasCompletedOfficePresenceSegment(workday: workdayKey)) {
            activityStore.startOfficePresenceSegment(workday: workdayKey, at: date)
            isResting = false
            restingUnlockActive = false
            isWaitingForUnlock = false
            return
        }
        guard autoStartGate.takeCheck(workday: workdayKey,
                                      active: autoStartEnabled && workMode == .flexible) else { return }
        if Self.shouldAutoStart(at: date, enabled: autoStartEnabled, mode: workMode,
                                hasArrived: todayStartTime != nil, weekdays: autoStartWeekdays,
                                startText: startText, latestText: latestText) {
            // 在岗时间的起点与自动倒计时成功启动是同一次有效解锁；不使用缓冲回拨后的到岗时间。
            activityStore.recordOfficePresenceStart(workday: workdayKey, at: date)
            setStartTime(Self.autoStartArrival(at: date, bufferEnabled: commuteBufferEnabled,
                                               bufferMinutes: commuteBufferMinutes))
            isWaitingForUnlock = false
        }
    }

    /// 关机前、熄屏或系统睡眠时调用；只有已过实际下班时间才把当天在岗记录封存。
    func endOfficePresenceIfNeeded(at date: Date = Date()) {
        tick(date)
        guard Self.shouldEndOfficePresence(at: date, plannedEnd: endTime) else { return }
        activityStore.recordOfficePresenceEnd(workday: workdayKey, at: date)
        isResting = true
        restingUnlockActive = false
    }

    /// 每秒刷新一次，驱动倒计时数字和进度条跳动
    private func startClock() {
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in self?.tick(date) }
    }

    private func tick(_ date: Date) {
        let key = Self.workdayKey(for: date)
        if key != workdayKey {
            let boundary = Self.workdayBase(for: date).addingTimeInterval(Double(Self.dayCutoffHour) * 3600)
            let wasOvertime = !isResting && endTime.map { boundary >= $0 } == true
            let carry = (wasOvertime || (isResting && restingUnlockActive)) && !screenAsleep && !lockedByNotification
            if wasOvertime { activityStore.recordOfficePresenceEnd(workday: workdayKey, at: boundary) }
            workdayKey = key
            todayStartTime = nil
            // 跨过凌晨 5 点不算回到桌面：通宵加班的解锁证据作废，要新一天真正解锁/登录才检查
            autoStartGate.revokeUnlock()
            pausedSeconds = 0
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: Keys.todayStartTime)
            defaults.removeObject(forKey: Keys.todayStartDay)
            let wasResting = isResting
            isResting = false
            restingUnlockActive = false
            isWaitingForUnlock = Self.shouldWaitForUnlockAfterBoundary(wasResting: wasResting,
                                                                        carriedIntoNewDay: carry)
            now = date
            if carry, Self.shouldAutoStart(at: boundary, enabled: autoStartEnabled, mode: workMode,
                                           hasArrived: false, weekdays: autoStartWeekdays,
                                           startText: startText, latestText: latestText) {
                activityStore.recordOfficePresenceStart(workday: workdayKey, at: boundary)
                setStartTime(Self.autoStartArrival(at: boundary, bufferEnabled: commuteBufferEnabled,
                                                   bufferMinutes: commuteBufferMinutes))
            }
            return
        }

        // 熄屏期间，或两次心跳间隔过长（睡眠、关机、App 未运行），这段时间不计入倒欠
        if let last = lastAlive, date > last, screenAsleep || date.timeIntervalSince(last) > 3,
           let end = endTime {
            let from = max(last, end)
            if date > from { pausedSeconds += date.timeIntervalSince(from) }
        }
        lastAlive = date

        let defaults = UserDefaults.standard
        defaults.set(date, forKey: Keys.lastAlive)
        defaults.set(pausedSeconds, forKey: Keys.pausedSeconds)
        defaults.set(workdayKey, forKey: Keys.pausedDay)

        now = date
        checkAutoStart(date)
    }

    // MARK: - 派生状态

    /// 今天按规则使用的上班区间
    private var ruleStart: Date { Self.time(startText, on: Self.workdayBase(for: now)) }
    private var ruleLatest: Date { Self.time(latestText, on: Self.workdayBase(for: now)) }

    /// 计算下班时间用的起点
    /// - 固定：规则里的上班时间
    /// - 弹性：到岗时间限制在上班区间内
    var effectiveStart: Date? {
        switch workMode {
        case .fixed:
            return ruleStart
        case .flexible:
            guard let arrival = todayStartTime else { return nil }
            return min(max(arrival, ruleStart), ruleLatest)
        }
    }

    /// 今天是否已经开始倒计时：固定模式始终开始；弹性模式要有到岗时间
    var hasStarted: Bool { effectiveStart != nil }

    /// 今天是否记录了到岗时间
    var hasArrived: Bool { todayStartTime != nil }

    /// 进度条起点：有到岗时间就从到岗算，固定模式没填就从上班时间算
    var progressStart: Date? { todayStartTime ?? (workMode == .fixed ? ruleStart : nil) }

    /// 今天的可下班时间
    var endTime: Date? {
        effectiveStart?.addingTimeInterval(workHours * 3600)
    }

    /// 剩余秒数
    var remainingSeconds: Int {
        guard let end = endTime else { return 0 }
        return max(0, Int(end.timeIntervalSince(now).rounded()))
    }

    /// 是否已经下班
    var isOffWork: Bool {
        guard let end = endTime else { return false }
        return now >= end
    }

    /// 公司倒欠你的秒数：下班后经过的时间，扣掉熄屏、睡眠、关机时段
    var overtimeSeconds: Int {
        guard let end = endTime, now > end else { return 0 }
        return max(0, Int(now.timeIntervalSince(end) - pausedSeconds))
    }

    /// 进度：已工作 / 应工作，下班后会超过 1（如 1.01 = 101%）
    var progress: Double {
        guard let start = progressStart, let end = endTime else { return 0 }
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return now >= end ? 1 : 0 }
        // 下班后按扣掉暂停时段的倒欠时间累加，和数字保持一致
        let elapsed = isOffWork ? total + Double(overtimeSeconds) : now.timeIntervalSince(start)
        return max(0, elapsed / total)
    }

    /// 截至指定时刻的正常工作秒数；下班后的倒欠时间不计入在岗时间统计。
    func workedSeconds(at date: Date = Date()) -> TimeInterval {
        guard let start = progressStart, let end = endTime else { return 0 }
        return max(0, min(date, end).timeIntervalSince(start))
    }

    /// 格式化剩余时间为 HH:mm:ss
    var remainingText: String { Self.clock(remainingSeconds) }

    /// 菜单栏文案
    var statusText: String {
        if isWaitingForUnlock { return "休息中，等待解锁" }
        if isResting { return "休息中" }
        if !hasStarted { return "未开始" }
        if isOffWork { return "已下班，公司倒欠你 " + Self.compact(overtimeSeconds) }
        return "下班倒计时：" + Self.compact(remainingSeconds)
    }

    /// 今天到岗时间文案，如 "09:58"
    var startTimeText: String { todayStartTime.map(Self.hhmm) ?? "--:--" }

    /// 规则里的上班时间，如 "10:00"
    var ruleStartText: String { startText }

    /// 弹性区间结束，如 "12:00"
    var latestTextForUI: String { latestText }

    /// 今天可下班时间文案，如 "19:00"
    var endTimeText: String { endTime.map(Self.hhmm) ?? "--:--" }

    /// 规则里的下班时间：固定为 "19:00"，弹性为 "19:00 – 21:00"
    var ruleEndText: String {
        let first = Self.hhmm(ruleStart.addingTimeInterval(workHours * 3600))
        guard workMode == .flexible else { return first }
        return first + " – " + Self.hhmm(ruleLatest.addingTimeInterval(workHours * 3600))
    }

    // MARK: - 自动开始上班

    /// 自动开始上班的判定（纯函数，便于测试），条件全部满足才开始：
    /// 开关开启、弹性模式、今天还没到岗、今天是上班日、时间在「上班区间开始前 1 小时 ～ 区间结束」内
    /// 「今天第一次有效回到桌面」由 AutoStartGate 负责，不在这里判断
    static func shouldAutoStart(at date: Date, enabled: Bool, mode: WorkMode, hasArrived: Bool,
                                weekdays: Set<Int>, startText: String, latestText: String) -> Bool {
        guard enabled, mode == .flexible, !hasArrived else { return false }
        return shouldRecordOfficePresence(at: date, weekdays: weekdays,
                                          startText: startText, latestText: latestText)
    }

    /// 是否位于上班日及自动开始的时间窗口内。在岗时间记录复用此资格，
    /// 但不依赖自动倒计时开关或是否已手动到岗。
    static func shouldRecordOfficePresence(at date: Date, weekdays: Set<Int>,
                                           startText: String, latestText: String) -> Bool {
        let base = workdayBase(for: date)
        guard weekdays.contains(Calendar.current.component(.weekday, from: base)) else { return false }
        let from = Calendar.current.date(bySettingHour: autoStartEarliestHour, minute: 0,
                                           second: 0, of: base)!
        let to = time(latestText, on: base)
        return date >= from && date <= to
    }

    /// 只允许在计划下班后，以第一次离开电脑的时刻封存当天的实际在岗记录。
    static func shouldEndOfficePresence(at date: Date, plannedEnd: Date?) -> Bool {
        guard let plannedEnd else { return false }
        return date >= plannedEnd
    }

    /// 同一工作日下班后，已封存过的公司电脑再次得到有效解锁证据时续开加班片段。
    static func shouldResumeOfficePresence(at date: Date, plannedEnd: Date?, hasCompletedSegment: Bool) -> Bool {
        guard hasCompletedSegment, let plannedEnd else { return false }
        return date >= plannedEnd
    }

    /// 异常关机后用持久化的最后心跳收口；不猜测离线期间的时长。
    static func shouldRecoverOpenOfficePresence(lastAlive: Date, plannedEnd: Date?) -> Bool {
        shouldEndOfficePresence(at: lastAlive, plannedEnd: plannedEnd)
    }

    static func shouldWaitForUnlockAfterBoundary(wasResting: Bool, carriedIntoNewDay: Bool) -> Bool {
        wasResting && !carriedIntoNewDay
    }

    /// 自动开始成功后要记录的到岗时间（纯函数）：缓冲关闭 = 当前时刻；开启 = 当前时刻 − 缓冲分钟数
    /// 回拨不会越过凌晨 5 点的工作日分界，避免被算到前一天
    static func autoStartArrival(at date: Date, bufferEnabled: Bool, bufferMinutes: Int) -> Date {
        guard bufferEnabled, bufferMinutes > 0 else { return date }
        let dayStart = workdayBase(for: date).addingTimeInterval(Double(dayCutoffHour) * 3600)
        return max(date.addingTimeInterval(-Double(bufferMinutes) * 60), dayStart)
    }

    /// 登录后多久内启动 App 才算「登录项拉起」
    static let loginLaunchWindow: TimeInterval = 5 * 60

    /// 本次启动是否算开机登录：必须开了「登录时打开」，且启动时间在本次控制台登录后 5 分钟内
    static func launchCountsAsLogin(launchAtLogin: Bool, loginTime: Date?, now: Date) -> Bool {
        guard launchAtLogin, let loginTime else { return false }
        let elapsed = now.timeIntervalSince(loginTime)
        return elapsed >= 0 && elapsed <= loginLaunchWindow
    }

    /// 当前用户本次在控制台（本机屏幕）登录的时间，读不到返回 nil
    static func consoleLoginTime() -> Date? {
        let me = NSUserName()
        var latest: Date?
        setutxent()
        defer { endutxent() }
        while let ptr = getutxent() {
            var e = ptr.pointee
            guard e.ut_type == USER_PROCESS else { continue }
            let user = withUnsafeBytes(of: &e.ut_user) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            let line = withUnsafeBytes(of: &e.ut_line) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            guard user == me, line == "console" else { continue }
            let t = Date(timeIntervalSince1970: TimeInterval(e.ut_tv.tv_sec))
            if latest == nil || t > latest! { latest = t }
        }
        return latest
    }

    /// 会话是否可能在锁屏：明确锁定、不在控制台、登录未完成、或读不到会话信息，都按锁定处理
    /// 注意：未锁屏时系统根本不给 CGSSessionScreenIsLocked 键，所以「没有这个键」不能当成已解锁的证据，
    /// 解锁证据由 unlockConfirmed 单独提供，这里只负责排除明确的锁定状态
    static func sessionIsLocked() -> Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
        if (info["CGSSessionScreenIsLocked"] as? Bool) == true { return true }
        guard (info[kCGSessionOnConsoleKey as String] as? Bool) == true else { return true }
        guard (info[kCGSessionLoginDoneKey as String] as? Bool) == true else { return true }
        return false
    }

    // MARK: - 工具

    /// 十六进制字符串（6 位，不含 #）转 Color；格式不对返回 nil
    static func color(fromHex hex: String) -> Color? {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        return Color(red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// 工作日的零点：凌晨 5 点前算前一天
    static func workdayBase(for date: Date) -> Date {
        Calendar.current.startOfDay(for: date.addingTimeInterval(-Double(dayCutoffHour) * 3600))
    }

    static func workdayKey(for date: Date) -> String {
        dayFormatter.string(from: workdayBase(for: date))
    }

    static func minutes(_ text: String) -> Int {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        return (parts.first ?? 0) * 60 + (parts.count > 1 ? parts[1] : 0)
    }

    static func time(_ text: String, on base: Date) -> Date {
        base.addingTimeInterval(Double(minutes(text)) * 60)
    }

    static func hhmm(_ date: Date) -> String { timeFormatter.string(from: date) }

    static func clock(_ s: Int) -> String {
        String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    /// 菜单栏短格式 "H:MM"，不显示秒，避免宽度跳动
    static func compact(_ s: Int) -> String {
        String(format: "%d:%02d", s / 3600, (s % 3600) / 60)
    }
}

/// 自动计时的检查机会：每个工作日只在第一次有效回到桌面时检查一次
/// - 解锁证据：开机登录（登录项拉起）或收到解锁通知时给出；熄屏、睡眠、锁屏、跨过凌晨 5 点时作废
/// - 检查机会：按工作日标识持久化到 UserDefaults，退出、重启 App 同一天也不会恢复；新工作日自然重置
/// - 第一次检查时即使太早、太晚、非上班日没开始，也算用掉了
final class AutoStartGate {
    static let checkedDayKey = "autoStartCheckedDay"
    private let defaults: UserDefaults
    /// 本次是否有「用户已输入密码」的证据，只在内存里，App 重启后要重新拿到
    private(set) var unlockConfirmed = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func confirmUnlock() { unlockConfirmed = true }
    func revokeUnlock() { unlockConfirmed = false }

    /// 今天的检查机会是否已经用过
    func hasChecked(workday: String) -> Bool {
        defaults.string(forKey: Self.checkedDayKey) == workday
    }

    /// 在有效回到桌面时调用：消耗解锁证据；功能开启且今天还没检查过时，记下「今天已检查」并返回 true
    /// active = 自动计时开启且为弹性模式；功能没开时不占用今天的检查机会
    func takeCheck(workday: String, active: Bool) -> Bool {
        guard unlockConfirmed else { return false }
        unlockConfirmed = false
        guard active, !hasChecked(workday: workday) else { return false }
        defaults.set(workday, forKey: Self.checkedDayKey)
        return true
    }
}
