import Foundation
import Combine

/// 主题色选项
enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case green = "绿色"
    case blue = "蓝色"
    case orange = "橙色"
    case purple = "紫色"

    var id: String { rawValue }
}

/// 下班倒计时核心模型
/// 逻辑：手动点击"开始上班"记录起点时间，固定工作时长后计算下班时间，
/// 倒计时持续跳动直到归零，归零后进入"已下班"态。
final class WorkTimerModel: ObservableObject {

    // MARK: - 持久化的设置项

    /// 每日工作时长（小时），默认 9 小时
    @Published var workHours: Double {
        didSet {
            UserDefaults.standard.set(workHours, forKey: Keys.workHours)
            syncDefaultEndTime()
        }
    }

    /// 默认上班时间参考（仅展示用，不影响实际计时），格式 "HH:mm"
    @Published var defaultStartTimeText: String {
        didSet {
            UserDefaults.standard.set(defaultStartTimeText, forKey: Keys.defaultStartTime)
            syncDefaultEndTime()
        }
    }

    /// 默认下班时间参考 = 参考上班时间 + 每日工作时长，自动联动，不单独编辑
    @Published private(set) var defaultEndTimeText: String = "19:00"

    /// 是否开机自动启动
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin)
            LoginItemManager.setEnabled(launchAtLogin)
        }
    }

    /// 主题色
    @Published var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Keys.theme) }
    }

    // MARK: - 当日状态

    /// 今天的"开始上班"时间，nil 表示今天还没点击开始
    @Published private(set) var todayStartTime: Date?

    /// 当前时间（定时刷新用于驱动倒计时 UI）
    @Published private(set) var now: Date = Date()

    private var timer: AnyCancellable?

    private enum Keys {
        static let workHours = "workHours"
        static let defaultStartTime = "defaultStartTime"
        static let defaultEndTime = "defaultEndTime"
        static let launchAtLogin = "launchAtLogin"
        static let theme = "theme"
        static let todayStartTime = "todayStartTime"
        static let todayStartDay = "todayStartDay"
    }

    init() {
        let defaults = UserDefaults.standard
        self.workHours = defaults.object(forKey: Keys.workHours) as? Double ?? 9.0
        self.defaultStartTimeText = defaults.string(forKey: Keys.defaultStartTime) ?? "10:00"
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        if let themeRaw = defaults.string(forKey: Keys.theme), let t = AppTheme(rawValue: themeRaw) {
            self.theme = t
        } else {
            self.theme = .green
        }

        syncDefaultEndTime()
        restoreTodayStartTimeIfNeeded()
        startClock()
    }

    /// 根据参考上班时间和工作时长重新计算参考下班时间（跨过午夜时按 24 小时取模）
    private func syncDefaultEndTime() {
        let parts = defaultStartTimeText.split(separator: ":").compactMap { Int($0) }
        let startMinutes = (parts.first ?? 0) * 60 + (parts.count > 1 ? parts[1] : 0)
        let total = (startMinutes + Int((workHours * 60).rounded())) % (24 * 60)
        defaultEndTimeText = String(format: "%02d:%02d", total / 60, total % 60)
        UserDefaults.standard.set(defaultEndTimeText, forKey: Keys.defaultEndTime)
    }

    /// 从 UserDefaults 恢复今天的开始时间（如果是同一天记录的）
    private func restoreTodayStartTimeIfNeeded() {
        let defaults = UserDefaults.standard
        guard let savedDay = defaults.string(forKey: Keys.todayStartDay),
              savedDay == Self.dayKey(for: Date()),
              let savedTime = defaults.object(forKey: Keys.todayStartTime) as? Date else {
            todayStartTime = nil
            return
        }
        todayStartTime = savedTime
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// 每秒刷新一次，驱动倒计时数字和进度条跳动
    private func startClock() {
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                self?.tick(date)
            }
    }

    private func tick(_ date: Date) {
        // 跨天自动清空今天的开始时间，等待用户重新点击"开始上班"
        if let start = todayStartTime, Self.dayKey(for: start) != Self.dayKey(for: date) {
            todayStartTime = nil
            UserDefaults.standard.removeObject(forKey: Keys.todayStartTime)
            UserDefaults.standard.removeObject(forKey: Keys.todayStartDay)
        }
        now = date
    }

    /// 用户点击"开始上班"
    func startWork() {
        setStartTime(Date())
    }

    /// 设置或修改今天的到岗时间（早上忘了点"开始上班"时补填用）
    /// 到岗时间不能晚于现在，晚于现在时按现在算
    func setStartTime(_ date: Date) {
        let current = Date()
        let start = min(date, current)
        todayStartTime = start
        now = current
        let defaults = UserDefaults.standard
        defaults.set(start, forKey: Keys.todayStartTime)
        defaults.set(Self.dayKey(for: start), forKey: Keys.todayStartDay)
    }

    /// 今天到岗时间文案，如 "09:58"
    var startTimeText: String {
        guard let start = todayStartTime else { return "--:--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: start)
    }

    // MARK: - 派生状态

    /// 今天是否已经开始上班计时
    var hasStarted: Bool { todayStartTime != nil }

    /// 今天的下班时间点
    var endTime: Date? {
        guard let start = todayStartTime else { return nil }
        return start.addingTimeInterval(workHours * 3600)
    }

    /// 剩余秒数（已下班则为 0 或负数）
    var remainingSeconds: Int {
        guard let end = endTime else { return 0 }
        return max(0, Int(end.timeIntervalSince(now).rounded()))
    }

    /// 是否已经下班
    var isOffWork: Bool {
        guard let end = endTime else { return false }
        return now >= end
    }

    /// 进度百分比 0~1（已工作时长 / 总工作时长）
    var progress: Double {
        guard let start = todayStartTime else { return 0 }
        let total = workHours * 3600
        let elapsed = now.timeIntervalSince(start)
        return min(1, max(0, elapsed / total))
    }

    /// 格式化剩余时间为 HH:mm:ss
    var remainingText: String {
        let s = remainingSeconds
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        return String(format: "%02d:%02d:%02d", h, m, sec)
    }

    /// 菜单栏短文案，如 "2:34"
    var compactRemainingText: String {
        let s = remainingSeconds
        let h = s / 3600
        let m = (s % 3600) / 60
        return String(format: "%d:%02d", h, m)
    }

    /// 下班时间文案，如 "19:00"
    var endTimeText: String {
        guard let end = endTime else { return "--:--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: end)
    }
}
