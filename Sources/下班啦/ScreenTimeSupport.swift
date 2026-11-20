import Foundation

enum ScreenTimePeriod: String, CaseIterable, Identifiable {
    case day
    case week

    static let defaultPeriod: ScreenTimePeriod = .week

    var id: String { rawValue }
}

/// 周图从周一开始排序，并只显示用户选作上班日的日期。
enum WorkweekChartLabels {
    private static let weekdaysStartingMonday = [2, 3, 4, 5, 6, 7, 1]
    private static let labels = [2: "一", 3: "二", 4: "三", 5: "四", 6: "五", 7: "六", 1: "日"]

    static func selectedLabels(for selectedWeekdays: Set<Int>) -> [String] {
        weekdaysStartingMonday.compactMap { selectedWeekdays.contains($0) ? labels[$0] : nil }
    }

    static func label(for weekday: Int) -> String {
        labels[weekday] ?? ""
    }
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
        guard isCurrentWorkday else { return 0 }
        return max(0, now.timeIntervalSince(presence.startedAt))
    }
}

/// 按天视图的精简摘要。只从实际在岗片段推导，不改写或补猜历史记录。
struct DailyPresenceSummary: Equatable {
    enum Departure: Equatable {
        case recorded(Date)
        case stillPresent
        case incomplete
        case unavailable
    }

    let arrivalTime: Date?
    let departure: Departure
    /// 实际在岗累计加上到工位缓冲；中间离线间隔仍不在这里。
    let creditedSeconds: TimeInterval?
    let overtimeSeconds: TimeInterval?

    static func make(segments: [OfficePresenceSegment], countdownArrival: Date? = nil,
                     plannedSeconds: TimeInterval?,
                     now: Date, isCurrentWorkday: Bool) -> DailyPresenceSummary {
        guard !segments.isEmpty else {
            return DailyPresenceSummary(arrivalTime: nil, departure: .unavailable,
                                        creditedSeconds: nil, overtimeSeconds: nil)
        }

        let hasOpenSegment = segments.contains { $0.endedAt == nil }
        let accumulated = segments.reduce(0) { total, segment in
            if let endedAt = segment.endedAt {
                return total + max(0, endedAt.timeIntervalSince(segment.startedAt))
            }
            guard isCurrentWorkday else { return total }
            return total + max(0, now.timeIntervalSince(segment.startedAt))
        }
        let departure: Departure
        if hasOpenSegment, isCurrentWorkday {
            departure = .stillPresent
        } else if hasOpenSegment {
            departure = .incomplete
        } else if !hasOpenSegment, let lastEnd = segments.compactMap(\.endedAt).max() {
            departure = .recorded(lastEnd)
        } else {
            departure = .unavailable
        }
        let firstSegmentStart = segments.map(\.startedAt).min()!
        let commuteCredit = countdownArrival.map { max(0, firstSegmentStart.timeIntervalSince($0)) } ?? 0
        let creditedSeconds = departure == .incomplete ? nil : accumulated + commuteCredit
        let overtime = creditedSeconds == nil || plannedSeconds == nil
            ? nil : max(0, creditedSeconds! - max(0, plannedSeconds!))
        return DailyPresenceSummary(arrivalTime: countdownArrival ?? firstSegmentStart, departure: departure,
                                    creditedSeconds: creditedSeconds, overtimeSeconds: overtime)
    }
}

/// 按天摘要的展示文案，与 SwiftUI 布局分离以保证空记录和在岗状态可测试。
struct DailyPresenceMetricText: Equatable {
    let arrival: String
    let departure: String
    let overtime: String

    init(summary: DailyPresenceSummary) {
        arrival = summary.arrivalTime.map(Self.timeFormatter.string(from:)) ?? "未记录"
        switch summary.departure {
        case .recorded(let time): departure = Self.timeFormatter.string(from: time)
        case .stillPresent: departure = "仍在岗"
        case .incomplete: departure = "记录未结束"
        case .unavailable: departure = "未记录"
        }
        guard let overtimeSeconds = summary.overtimeSeconds, overtimeSeconds > 0 else {
            overtime = "—"
            return
        }
        let minutes = Int(overtimeSeconds / 60)
        overtime = minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分钟" : "\(minutes) 分钟"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
