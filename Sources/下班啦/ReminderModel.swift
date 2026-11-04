import Foundation
import Combine

/// 气泡提醒的两种类型，各自对应一个视频文件夹
enum ReminderKind: String, CaseIterable, Hashable {
    case water
    case egg

    var folderName: String { self == .water ? "喝水" : "彩蛋" }
}

/// 小彩蛋的触发方式
enum EggMode: String, CaseIterable, Identifiable {
    case interval       // 每隔 N 分钟播放一个
    case random         // 上班期间随机出现
    case fixedTime      // 每天固定时间
    case beforeOffWork  // 临近下班：下班前 N 分钟（0 = 下班那一刻）

    var id: String { rawValue }

    var title: String {
        switch self {
        case .interval: return "每隔一段时间"
        case .random: return "上班期间随机"
        case .fixedTime: return "每天固定时间"
        case .beforeOffWork: return "临近下班"
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

    static let waterIntervals = [15, 30, 45, 60, 90, 120]
    static let eggCounts = [1, 2, 3]
    static let eggIntervals = [5, 10, 15, 20, 30, 45, 60, 90, 120]
    static let eggLeadOptions = [0, 5, 10, 15, 30]
    /// 触发点过了多久以内仍会补弹（例如正被另一个气泡占着）；超过就跳过，避免启动时补一堆旧提醒
    static let fireWindow: TimeInterval = 120

    // MARK: - 持久化设置

    @Published var waterEnabled: Bool { didSet { save(waterEnabled, Keys.waterEnabled) } }
    @Published var waterIntervalMinutes: Int { didSet { save(waterIntervalMinutes, Keys.waterInterval) } }
    @Published var waterOnlyDuringWork: Bool { didSet { save(waterOnlyDuringWork, Keys.waterOnlyWork) } }

    @Published var eggEnabled: Bool { didSet { save(eggEnabled, Keys.eggEnabled) } }
    @Published var eggMode: EggMode { didSet { save(eggMode.rawValue, Keys.eggMode) } }
    @Published var eggIntervalMinutes: Int { didSet { save(eggIntervalMinutes, Keys.eggInterval) } }
    @Published var eggRandomCount: Int { didSet { save(eggRandomCount, Keys.eggCount) } }
    @Published var eggFixedTimeText: String { didSet { save(eggFixedTimeText, Keys.eggFixedTime) } }
    @Published var eggLeadMinutes: Int { didSet { save(eggLeadMinutes, Keys.eggLead) } }
    @Published var eggOnlyDuringWork: Bool { didSet { save(eggOnlyDuringWork, Keys.eggOnlyWork) } }

    /// 各类型当前可用的视频数量（设置面板显示用）
    @Published private(set) var videoCounts: [ReminderKind: Int] = [:]

    // MARK: - 外部依赖

    /// 弹出气泡：返回 false 表示当前忙（已有气泡在播），调度器下一秒再试；force 为预览时强制替换
    var present: ((URL, Bool) -> Bool)?
    /// 随机挑一个视频，可替换以便测试
    lazy var videoProvider: (ReminderKind) -> URL? = { [weak self] kind in self?.pickVideo(kind) }
    private var lastPlayed: [ReminderKind: URL] = [:]

    private let work: WorkTimerModel
    private var timer: AnyCancellable?
    private var waterAnchor: Date?
    private var eggAnchor: Date?
    private var firedKeys: Set<String> = []
    private var randomPlan: (key: String, times: [Date])?

    private enum Keys {
        static let waterEnabled = "reminder.water.enabled"
        static let waterInterval = "reminder.water.interval"
        static let waterOnlyWork = "reminder.water.onlyWork"
        static let eggEnabled = "reminder.egg.enabled"
        static let eggMode = "reminder.egg.mode"
        static let eggCount = "reminder.egg.count"
        static let eggInterval = "reminder.egg.interval"
        static let eggFixedTime = "reminder.egg.fixedTime"
        static let eggLead = "reminder.egg.lead"
        static let eggOnlyWork = "reminder.egg.onlyWork"
    }

    init(work: WorkTimerModel) {
        self.work = work
        let d = UserDefaults.standard
        waterEnabled = d.bool(forKey: Keys.waterEnabled)
        waterIntervalMinutes = d.object(forKey: Keys.waterInterval) as? Int ?? 45
        waterOnlyDuringWork = d.object(forKey: Keys.waterOnlyWork) as? Bool ?? true
        eggEnabled = d.bool(forKey: Keys.eggEnabled)
        eggMode = d.string(forKey: Keys.eggMode).flatMap(EggMode.init(rawValue:)) ?? .interval
        eggIntervalMinutes = d.object(forKey: Keys.eggInterval) as? Int ?? 30
        eggRandomCount = d.object(forKey: Keys.eggCount) as? Int ?? 1
        eggFixedTimeText = d.string(forKey: Keys.eggFixedTime) ?? "15:00"
        eggLeadMinutes = d.object(forKey: Keys.eggLead) as? Int ?? 10
        eggOnlyDuringWork = d.object(forKey: Keys.eggOnlyWork) as? Bool ?? true
        refreshVideoCounts()
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
        _ = present?(url, true)
    }

    // MARK: - 调度

    func tick(_ now: Date) {
        var working = false
        if let start = work.todayStartTime, let end = work.endTime {
            working = now >= start && now < end
        }
        tickWater(now, working: working)
        tickEgg(now, working: working)
    }

    /// 喝水：从开启（或开始上班）那一刻起，每隔 N 分钟提醒一次
    private func tickWater(_ now: Date, working: Bool) {
        guard waterEnabled, !waterOnlyDuringWork || working else {
            waterAnchor = nil
            return
        }
        guard let anchor = waterAnchor else {
            waterAnchor = now
            return
        }
        if now.timeIntervalSince(anchor) >= Double(waterIntervalMinutes) * 60, fire(.water) {
            waterAnchor = now
        }
    }

    private func tickEgg(_ now: Date, working: Bool) {
        guard eggEnabled else {
            eggAnchor = nil
            return
        }
        let day = Self.dayKey(now)
        switch eggMode {
        case .interval:
            guard !eggOnlyDuringWork || working else {
                eggAnchor = nil
                return
            }
            guard let anchor = eggAnchor else {
                eggAnchor = now
                return
            }
            if now.timeIntervalSince(anchor) >= Double(eggIntervalMinutes) * 60, fire(.egg) {
                eggAnchor = now
            }

        case .fixedTime:
            guard !eggOnlyDuringWork || working,
                  let target = Self.time(eggFixedTimeText, on: now) else { return }
            fireOnce("\(day)|fixed|\(eggFixedTimeText)", at: target, now: now)

        case .beforeOffWork:
            guard let end = work.endTime else { return }
            let target = end.addingTimeInterval(-Double(eggLeadMinutes) * 60)
            fireOnce("\(day)|before|\(Int(target.timeIntervalSince1970))", at: target, now: now)

        case .random:
            // 在「到岗 30 分钟后」到「下班前 15 分钟」之间随机挑时间点
            guard working, let start = work.todayStartTime, let end = work.endTime else { return }
            // 只用到岗/下班时间做标识：跨过午夜也不会重新生成计划
            let planKey = "random|\(Int(start.timeIntervalSince1970))|\(Int(end.timeIntervalSince1970))|\(eggRandomCount)"
            if randomPlan?.key != planKey {
                randomPlan = (planKey, Self.randomTimes(count: eggRandomCount,
                                                        from: start.addingTimeInterval(30 * 60),
                                                        to: end.addingTimeInterval(-15 * 60),
                                                        notBefore: now.addingTimeInterval(60)))
            }
            for (index, time) in (randomPlan?.times ?? []).enumerated() {
                if fireOnce("\(planKey)|\(index)", at: time, now: now) { break }
            }
        }
    }

    @discardableResult
    private func fireOnce(_ key: String, at target: Date, now: Date) -> Bool {
        guard !firedKeys.contains(key), now >= target,
              now.timeIntervalSince(target) < Self.fireWindow else { return false }
        guard fire(.egg) else { return false }
        firedKeys.insert(key)
        return true
    }

    private func fire(_ kind: ReminderKind) -> Bool {
        // 没有视频就当作已提醒，避免每秒重试
        guard let url = videoProvider(kind) else { return true }
        return present?(url, false) ?? false
    }

    /// 随机挑一个视频；有多个时不连续播同一个
    private func pickVideo(_ kind: ReminderKind) -> URL? {
        let all = VideoLibrary.videos(kind)
        let pool = all.count > 1 ? all.filter { $0 != lastPlayed[kind] } : all
        let pick = pool.randomElement()
        lastPlayed[kind] = pick
        return pick
    }

    // MARK: - 工具

    /// 把时间窗口均分成 count 段，每段里随机取一个点，避免几次彩蛋挤在一起
    static func randomTimes(count: Int, from lower: Date, to upper: Date, notBefore: Date) -> [Date] {
        let lo = max(lower, notBefore)
        guard count > 0, upper > lo else { return [] }
        let span = upper.timeIntervalSince(lo) / Double(count)
        return (0..<count).map { i in
            lo.addingTimeInterval(span * (Double(i) + Double.random(in: 0.1...0.9)))
        }
    }

    static func time(_ text: String, on day: Date) -> Date? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayKey(_ date: Date) -> String { dayFormatter.string(from: date) }
}
