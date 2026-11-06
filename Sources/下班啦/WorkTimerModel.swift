import Foundation
import Combine
import AppKit
import SwiftUI

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
/// 一个「工作日」从凌晨 3:00 开始，到次日 3:00 结束：
/// 半夜加班不会被当成第二天，3:00 自动清空到岗时间和「公司倒欠你」的计时。
final class WorkTimerModel: ObservableObject {

    /// 新工作日的分界点（凌晨 3 点）
    static let dayCutoffHour = 3
    static let defaultStartText = "10:00"
    static let defaultLatestText = "12:00"

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

    // MARK: - 当日状态

    /// 今天实际到岗时间，nil 表示今天还没记录
    @Published private(set) var todayStartTime: Date?

    /// 当前时间（定时刷新用于驱动倒计时 UI）
    @Published private(set) var now: Date = Date()

    /// 下班后不计入「公司倒欠你」的秒数：熄屏、睡眠、关机、App 没运行的时段
    private var pausedSeconds: Double = 0
    /// 上一次计时心跳的时间，用来发现睡眠/关机造成的空档
    private var lastAlive: Date?
    /// 屏幕是否已熄灭（系统没睡、只是熄屏时计时器还在跑，需要单独判断）
    private var screenAsleep = false
    /// 当前工作日标识，变化时清空当日状态
    private var workdayKey: String

    private var timer: AnyCancellable?
    private var observers: [NSObjectProtocol] = []

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
    }

    init() {
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
        self.workdayKey = Self.workdayKey(for: Date())

        // 老数据里区间可能是反的（旧版没有区间结束），直接恢复默认
        if Self.minutes(latestText) < Self.minutes(startText) {
            latestText = max(startText, Self.defaultLatestText)
        }

        restoreTodayState()
        observeScreen()
        startClock()
    }

    deinit {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
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

    /// 用户点击「开始上班」
    func startWork() {
        setStartTime(Date())
    }

    /// 设置或修改今天的到岗时间（随时可在设置里补填、修改）
    /// 只取时分，落在当前工作日；晚于现在时按现在算
    func setStartTime(_ date: Date) {
        let current = Date()
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        var start = Calendar.current.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0,
                                          of: Self.workdayBase(for: current)) ?? date
        // 0~3 点属于当前工作日的「次日凌晨」
        if (c.hour ?? 0) < Self.dayCutoffHour { start = start.addingTimeInterval(24 * 3600) }
        start = min(start, current)
        todayStartTime = start
        now = current
        let defaults = UserDefaults.standard
        defaults.set(start, forKey: Keys.todayStartTime)
        defaults.set(workdayKey, forKey: Keys.todayStartDay)
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
        tick(Date())
    }

    /// 熄屏 / 睡眠时暂停「公司倒欠你」
    private func observeScreen() {
        let center = NSWorkspace.shared.notificationCenter
        let sleepNames: [Notification.Name] = [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification]
        let wakeNames: [Notification.Name] = [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification]
        for name in sleepNames {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.tick(Date())
                self?.screenAsleep = true
            })
        }
        for name in wakeNames {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.tick(Date())
                self?.screenAsleep = false
            })
        }
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
            // 凌晨 3 点：新的一天，清空到岗时间和倒欠计时
            workdayKey = key
            todayStartTime = nil
            pausedSeconds = 0
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: Keys.todayStartTime)
            defaults.removeObject(forKey: Keys.todayStartDay)
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

    /// 格式化剩余时间为 HH:mm:ss
    var remainingText: String { Self.clock(remainingSeconds) }

    /// 菜单栏文案
    var statusText: String {
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

    /// 工作日的零点：凌晨 3 点前算前一天
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
