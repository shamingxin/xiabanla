import Foundation

enum ScreenTimePeriod: String, CaseIterable, Identifiable {
    case day
    case week

    static let defaultPeriod: ScreenTimePeriod = .week

    var id: String { rawValue }
}

/// 在岗时间展示规则与 SwiftUI 视图分离，保证实际在岗记录的优先级可独立测试。
enum ScreenTimeDuration {
    static func seconds(for presence: OfficePresenceSession?, plannedSeconds: TimeInterval,
                        now: Date, isCurrentWorkday: Bool, fallbackStartedAt: Date? = nil) -> TimeInterval {
        guard let presence else {
            guard isCurrentWorkday, let fallbackStartedAt else { return max(0, plannedSeconds) }
            return max(0, now.timeIntervalSince(fallbackStartedAt))
        }
        if let endedAt = presence.endedAt {
            return max(0, endedAt.timeIntervalSince(presence.startedAt))
        }
        guard isCurrentWorkday else { return max(0, plannedSeconds) }
        return max(0, now.timeIntervalSince(presence.startedAt))
    }
}
