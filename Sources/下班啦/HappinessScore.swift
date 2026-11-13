import Foundation

/// 将已封存的实际在岗时长换算为轻量化的“本周幸福指数”。
/// 它只评估下班啦自己的工时记录，并不代表真实心理健康状态。
enum HappinessScore {
    struct Session: Equatable {
        let workday: String
        let plannedSeconds: TimeInterval
        let presenceSeconds: TimeInterval
    }

    struct Day: Equatable, Identifiable {
        let session: Session
        let score: Int
        let overtimeSeconds: TimeInterval
        var id: String { session.workday }
    }

    struct WeeklySummary: Equatable {
        let days: [Day]
        let score: Int?
        let overtimeSeconds: TimeInterval
        let onTimeDays: Int

        var tier: String? {
            guard let score else { return nil }
            switch score {
            case 100: return "下班自由人"
            case 80...99: return "还算有盼头"
            case 60...79: return "幸福被偷走一点"
            case 40...59: return "公司欠你一场晚霞"
            default: return "建议立刻下班"
            }
        }
    }

    static func dailyScore(for session: Session) -> Int {
        let overtimeMinutes = max(0, session.presenceSeconds - session.plannedSeconds) / 60
        return min(100, max(0, Int((100 - overtimeMinutes * 0.5).rounded())))
    }

    static func weeklySummary(sessions: [Session]) -> WeeklySummary {
        let days = sessions.map { session in
            Day(session: session,
                score: dailyScore(for: session),
                overtimeSeconds: max(0, session.presenceSeconds - session.plannedSeconds))
        }
        let score = days.isEmpty ? nil : Int((Double(days.map(\.score).reduce(0, +)) / Double(days.count)).rounded())
        return WeeklySummary(days: days,
                             score: score,
                             overtimeSeconds: days.map(\.overtimeSeconds).reduce(0, +),
                             onTimeDays: days.filter { $0.overtimeSeconds == 0 }.count)
    }
}
