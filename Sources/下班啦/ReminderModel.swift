import Foundation
import Combine

/// 气泡提醒的两种类型，各自对应一个视频文件夹
enum ReminderKind: String, CaseIterable, Hashable {
    case water
    case egg
    case offWork

    var folderName: String {
        switch self {
        case .water: return "喝水"
        case .egg: return "彩蛋"
        case .offWork: return "下班"
        }
    }
}

/// 视频素材：只读取打包在 App 里的 Resources/Videos/{喝水,彩蛋}
/// 视频由开发者放进项目的 Assets/Videos 后重新打包，使用者无法自行添加
enum VideoLibrary {
    static let extensions: Set<String> = ["mp4", "mov", "m4v"]

    static func videos(_ kind: ReminderKind) -> [URL] {
        guard let resources = Bundle.main.resourceURL else { return [] }
        let folder = resources.appendingPathComponent("Videos/\(kind.folderName)", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                  options: [.skipsHiddenFiles])) ?? []
        return files.filter { extensions.contains($0.pathExtension.lowercased()) }
    }
}

/// 喝水提醒 + 小彩蛋：保存设置，并每秒检查是否到了该弹气泡的时间
final class ReminderModel: ObservableObject {

    // MARK: - 选项

    static let waterIntervals = [5, 10, 15, 30, 45, 60, 90, 120]
    static let eggIntervals = [5, 10, 15, 20, 30, 45, 60, 90, 120]
    /// 触发点过了多久以内仍会补弹（例如正被另一个气泡占着）；超过就跳过，避免启动时补一堆旧提醒
    static let fireWindow: TimeInterval = 120

    // MARK: - 持久化设置

    @Published var waterEnabled: Bool { didSet { save(waterEnabled, Keys.waterEnabled) } }
    @Published var waterIntervalMinutes: Int { didSet { save(waterIntervalMinutes, Keys.waterInterval) } }
    /// 常驻提醒：喝水动画循环播放，点 × 才关闭；默认开启
    @Published var waterSticky: Bool { didSet { save(waterSticky, Keys.waterSticky) } }

    @Published var eggEnabled: Bool { didSet { save(eggEnabled, Keys.eggEnabled) } }
    @Published var eggIntervalMinutes: Int { didSet { save(eggIntervalMinutes, Keys.eggInterval) } }

    @Published var offWorkEnabled: Bool { didSet { save(offWorkEnabled, Keys.offWorkEnabled) } }

    /// 各类型当前可用的视频数量（设置面板显示用）
    @Published private(set) var videoCounts: [ReminderKind: Int] = [:]

    // MARK: - 外部依赖

    /// 弹出气泡：返回 false 表示当前忙（已有气泡在播），调度器下一秒再试
    /// - force：强制替换当前气泡（预览、下班动画顶替常驻喝水）
    /// - loop：常驻循环播放
    /// - onDismiss：气泡收回时回调
    var present: ((_ url: URL, _ force: Bool, _ loop: Bool, _ onDismiss: (() -> Void)?) -> Bool)?
    /// 轮回随机挑一个视频，可替换以便测试
    lazy var videoProvider: (ReminderKind) -> URL? = { [weak self] kind in self?.pickVideo(kind) }

    private let work: WorkTimerModel
    private var timer: AnyCancellable?
    /// 常驻喝水气泡正挂着：期间喝水、彩蛋都不再弹，关闭后从关闭那一刻重新计时
    private var stickyWaterShowing = false
    /// 间隔计时的起点。存进 UserDefaults，重启 App（更新版本、开机）后接着算，不再从头等
    private var waterAnchor: Date? {
        didSet { saveAnchor(waterAnchor, Keys.waterAnchor) }
    }
    private var eggAnchor: Date? {
        didSet { saveAnchor(eggAnchor, Keys.eggAnchor) }
    }

    private enum Keys {
        static let waterEnabled = "reminder.water.enabled"
        static let waterInterval = "reminder.water.interval"
        static let waterSticky = "reminder.water.sticky"
        static let eggEnabled = "reminder.egg.enabled"
        static let eggInterval = "reminder.egg.interval"
        static let offWorkEnabled = "reminder.offWork.enabled"
        /// 记录的是具体下班时刻（而不是日期），改了上班/下班设置算出新的下班时刻后会重新触发一次
        static let offWorkFiredEnd = "reminder.offWork.firedEnd"
        static let waterAnchor = "reminder.water.anchor"
        static let eggAnchor = "reminder.egg.anchor"
    }

    init(work: WorkTimerModel) {
        self.work = work
        let d = UserDefaults.standard
        waterEnabled = d.bool(forKey: Keys.waterEnabled)
        waterIntervalMinutes = d.object(forKey: Keys.waterInterval) as? Int ?? 45
        waterSticky = d.object(forKey: Keys.waterSticky) as? Bool ?? true
        eggEnabled = d.bool(forKey: Keys.eggEnabled)
        eggIntervalMinutes = d.object(forKey: Keys.eggInterval) as? Int ?? 30
        offWorkEnabled = d.object(forKey: Keys.offWorkEnabled) as? Bool ?? true
        waterAnchor = d.object(forKey: Keys.waterAnchor) as? Date
        eggAnchor = d.object(forKey: Keys.eggAnchor) as? Date
        refreshVideoCounts()
    }

    private func saveAnchor(_ date: Date?, _ key: String) {
        if let date { UserDefaults.standard.set(date, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }

    /// 间隔提醒：到点就弹；App 关了很久（超过两个间隔）再打开时重新计时，不一启动就弹
    private func intervalDue(_ anchor: Date?, minutes: Int, now: Date) -> (due: Bool, reset: Bool) {
        guard let anchor else { return (false, true) }
        let elapsed = now.timeIntervalSince(anchor)
        let interval = Double(minutes) * 60
        if elapsed < 0 || elapsed > interval * 2 { return (false, true) }
        return (elapsed >= interval, false)
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    func start() {
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] in self?.tick($0) }
    }

    private func refreshVideoCounts() {
        var counts: [ReminderKind: Int] = [:]
        for kind in ReminderKind.allCases { counts[kind] = VideoLibrary.videos(kind).count }
        if counts != videoCounts { videoCounts = counts }
    }

    /// 设置面板里的「预览」：立即播放一个，替换正在播的气泡
    func preview(_ kind: ReminderKind) {
        guard let url = videoProvider(kind) else { return }
        // 预览只是看看动画内容，不常驻
        _ = present?(url, true, false, nil)
    }

    // MARK: - 调度

    func tick(_ now: Date) {
        var working = false
        if let start = work.progressStart, let end = work.endTime {
            working = now >= start && now < end
        }
        tickWater(now, working: working)
        tickEgg(now, working: working)
        tickOffWork(now)
    }

    /// 喝水：从开启（或开始上班）那一刻起，每隔 N 分钟提醒一次
    private func tickWater(_ now: Date, working: Bool) {
        guard waterEnabled, working else {
            waterAnchor = nil
            return
        }
        if stickyWaterShowing { return }
        let state = intervalDue(waterAnchor, minutes: waterIntervalMinutes, now: now)
        if state.reset { waterAnchor = now; return }
        if state.due, fireWater() { waterAnchor = now }
    }

    /// 小彩蛋：和喝水一样，上班期间每隔 N 分钟放一个
    private func tickEgg(_ now: Date, working: Bool) {
        guard eggEnabled, working else {
            eggAnchor = nil
            return
        }
        // 常驻喝水挂着时跳过，关闭后重新计时
        if stickyWaterShowing { return }
        let state = intervalDue(eggAnchor, minutes: eggIntervalMinutes, now: now)
        if state.reset { eggAnchor = now; return }
        if state.due, fire(.egg) { eggAnchor = now }
    }

    /// 下班提醒：倒计时结束（跨过下班时间）那一刻播放一次
    /// 按「具体下班时刻」而不是「日期」记重复，这样中途调整上班/固定时长等设置、算出新的下班时刻后，
    /// 会被当成一次新的下班时刻，重新播放一次（覆盖「一开始设置误触」导致漏播的情况）
    private func tickOffWork(_ now: Date) {
        guard offWorkEnabled, let end = work.endTime else { return }
        let key = Self.offWorkKey(for: end)
        guard UserDefaults.standard.string(forKey: Keys.offWorkFiredEnd) != key else { return }
        guard now >= end, now.timeIntervalSince(end) < Self.fireWindow else { return }
        // 常驻喝水挂着时直接顶替，不然下班动画会因为 2 分钟窗口过了而漏播
        guard fire(.offWork, force: stickyWaterShowing) else { return }
        UserDefaults.standard.set(key, forKey: Keys.offWorkFiredEnd)
    }

    /// 下班时刻的去重 key：精确到秒，避免浮点误差导致同一时刻被判定成两个不同 key
    private static func offWorkKey(for end: Date) -> String {
        String(Int(end.timeIntervalSinceReferenceDate.rounded()))
    }

    private func fire(_ kind: ReminderKind, force: Bool = false) -> Bool {
        // 没有视频就当作已提醒，避免每秒重试
        guard let url = videoProvider(kind) else { return true }
        return present?(url, force, false, nil) ?? false
    }

    /// 喝水：开了常驻就循环播放，并在关闭时重新计时
    private func fireWater() -> Bool {
        guard let url = videoProvider(.water) else { return true }
        guard waterSticky else { return present?(url, false, false, nil) ?? false }
        let shown = present?(url, false, true, { [weak self] in self?.stickyWaterClosed() }) ?? false
        if shown { stickyWaterShowing = true }
        return shown
    }

    /// 常驻喝水被关掉（点 × 或被下班动画顶替）：喝水、彩蛋都从这一刻重新计时
    private func stickyWaterClosed() {
        stickyWaterShowing = false
        let now = Date()
        if waterAnchor != nil { waterAnchor = now }
        if eggAnchor != nil { eggAnchor = now }
    }

    /// 轮回随机：一轮里每个视频都播一次、顺序随机，播完一轮再开下一轮
    /// - 本轮已播的文件名存在 UserDefaults，重启 App 后接着这一轮
    /// - 新加的视频自动进入当前轮；新一轮的第一个不和上一轮最后一个重复
    private func pickVideo(_ kind: ReminderKind) -> URL? {
        let all = VideoLibrary.videos(kind)
        guard !all.isEmpty else { return nil }
        let defaults = UserDefaults.standard
        let playedKey = "reminder.\(kind.folderName).played"
        let lastKey = "reminder.\(kind.folderName).last"
        var played = Set(defaults.stringArray(forKey: playedKey) ?? [])
        let last = defaults.string(forKey: lastKey)

        var pool = all.filter { !played.contains($0.lastPathComponent) }
        if pool.isEmpty {
            played = []
            pool = all.count > 1 ? all.filter { $0.lastPathComponent != last } : all
        }
        guard let pick = pool.randomElement() else { return nil }
        played.insert(pick.lastPathComponent)
        defaults.set(Array(played), forKey: playedKey)
        defaults.set(pick.lastPathComponent, forKey: lastKey)
        return pick
    }

    // MARK: - 工具

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayKey(_ date: Date) -> String { dayFormatter.string(from: date) }
}
