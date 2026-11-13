import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum ActivityKind: String, Codable { case water }
enum ActivityAction: String, Codable, CaseIterable, Equatable { case prompted, completed, deferred }

struct ActivityEvent: Identifiable, Equatable {
    let id: Int64
    let occurredAt: Date
    let kind: ActivityKind
    let action: ActivityAction
}

struct ActivityDaySummary: Equatable {
    var prompted = 0
    var completed = 0
    var deferred = 0
    var total: Int { prompted + completed + deferred }
}

struct WorkSession: Equatable {
    let workday: String
    let startedAt: Date
    let plannedSeconds: TimeInterval
}

/// 真实在公司使用电脑的会话，独立于倒计时的到岗时间与到工位缓冲。
struct OfficePresenceSession: Equatable {
    let workday: String
    let startedAt: Date
    let endedAt: Date?
}

/// 同一工作日的一段实际在岗时间；睡眠/关机间隔由相邻片段的空隙表达，绝不计入工时。
struct OfficePresenceSegment: Equatable, Identifiable {
    let id: Int64
    let workday: String
    let startedAt: Date
    let endedAt: Date?
}

/// 本地行为事件库。数据库不可用时静默降级，提醒本身不应被统计能力阻塞。
final class ActivityStore {
    private var database: OpaquePointer?
    private let calendar: Calendar

    convenience init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("下班啦", isDirectory: true)
        self.init(databaseURL: support.appendingPathComponent("activity.sqlite"))
    }

    init(databaseURL: URL, calendar: Calendar = .current) {
        self.calendar = calendar
        try? FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            database = nil
            return
        }
        execute("""
        CREATE TABLE IF NOT EXISTS activity_events (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          occurred_at REAL NOT NULL,
          kind TEXT NOT NULL,
          action TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS activity_events_date ON activity_events(occurred_at);
        CREATE TABLE IF NOT EXISTS work_sessions (
          workday TEXT PRIMARY KEY,
          started_at REAL NOT NULL,
          planned_seconds REAL NOT NULL,
          presence_started_at REAL,
          presence_ended_at REAL
        );
        """)
        // v1.6 已创建的数据库没有这两个列。重复添加时 SQLite 会报错，
        // execute 会静默忽略，因此新旧数据库都能安全打开。
        execute("ALTER TABLE work_sessions ADD COLUMN presence_started_at REAL")
        execute("ALTER TABLE work_sessions ADD COLUMN presence_ended_at REAL")
        execute("""
        CREATE TABLE IF NOT EXISTS office_presence_segments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          workday TEXT NOT NULL,
          started_at REAL NOT NULL,
          ended_at REAL
        );
        CREATE UNIQUE INDEX IF NOT EXISTS office_presence_segment_start
          ON office_presence_segments(workday, started_at);
        CREATE UNIQUE INDEX IF NOT EXISTS office_presence_segment_open
          ON office_presence_segments(workday) WHERE ended_at IS NULL;
        """)
        // 将 v1.7 单段真实在岗记录无损迁入多段表。唯一索引保证多次启动不会重复。
        execute("""
        INSERT OR IGNORE INTO office_presence_segments (workday, started_at, ended_at)
        SELECT workday, presence_started_at, presence_ended_at
        FROM work_sessions WHERE presence_started_at IS NOT NULL;
        """)
    }

    deinit { sqlite3_close(database) }

    func record(kind: ActivityKind, action: ActivityAction, at date: Date = Date()) {
        guard let database else { return }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database,
                                 "INSERT INTO activity_events (occurred_at, kind, action) VALUES (?, ?, ?)",
                                 -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_double(statement, 1, date.timeIntervalSinceReferenceDate)
        sqlite3_bind_text(statement, 2, kind.rawValue, -1, sqliteTransient)
        sqlite3_bind_text(statement, 3, action.rawValue, -1, sqliteTransient)
        sqlite3_step(statement)
    }

    func summary(for day: Date) -> ActivityDaySummary {
        var summary = ActivityDaySummary()
        for event in events(on: day) {
            switch event.action {
            case .prompted: summary.prompted += 1
            case .completed: summary.completed += 1
            case .deferred: summary.deferred += 1
            }
        }
        return summary
    }

    func events(on day: Date) -> [ActivityEvent] {
        guard let database else { return [] }
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database,
                                 "SELECT id, occurred_at, kind, action FROM activity_events WHERE occurred_at >= ? AND occurred_at < ? ORDER BY occurred_at ASC, id ASC",
                                 -1, &statement, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_double(statement, 1, start.timeIntervalSinceReferenceDate)
        sqlite3_bind_double(statement, 2, end.timeIntervalSinceReferenceDate)
        var result: [ActivityEvent] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let kindText = sqlite3_column_text(statement, 2),
                  let actionText = sqlite3_column_text(statement, 3),
                  let kind = ActivityKind(rawValue: String(cString: kindText)),
                  let action = ActivityAction(rawValue: String(cString: actionText)) else { continue }
            result.append(ActivityEvent(id: sqlite3_column_int64(statement, 0),
                                        occurredAt: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 1)),
                                        kind: kind, action: action))
        }
        return result
    }

    /// 同一工作日允许用户补填或修正到岗时间，因此覆盖该日旧记录。
    func recordWorkStart(workday: String, at date: Date, plannedSeconds: TimeInterval) {
        guard let database else { return }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "INSERT INTO work_sessions (workday, started_at, planned_seconds) VALUES (?, ?, ?) ON CONFLICT(workday) DO UPDATE SET started_at = excluded.started_at, planned_seconds = excluded.planned_seconds"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(statement, 1, workday, -1, sqliteTransient)
        sqlite3_bind_double(statement, 2, date.timeIntervalSinceReferenceDate)
        sqlite3_bind_double(statement, 3, plannedSeconds)
        sqlite3_step(statement)
    }

    /// 用户主动点「开始上班」时，同时保存倒计时起点和真实到电脑前的时刻。
    /// 前者可受缓冲回拨影响，后者必须是点击发生的真实时刻，供下班后熄屏时封存实际在岗工时。
    func recordManualWorkStart(workday: String, countdownStartedAt: Date,
                               plannedSeconds: TimeInterval, presenceStartedAt: Date) {
        recordWorkStart(workday: workday, at: countdownStartedAt, plannedSeconds: plannedSeconds)
        recordOfficePresenceStart(workday: workday, at: presenceStartedAt)
    }

    func workSession(workday: String) -> WorkSession? {
        guard let database else { return nil }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "SELECT started_at, planned_seconds FROM work_sessions WHERE workday = ?", -1, &statement, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(statement, 1, workday, -1, sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return WorkSession(workday: workday,
                           startedAt: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 0)),
                           plannedSeconds: sqlite3_column_double(statement, 1))
    }

    /// 自动倒计时成功后，记录用户真正解锁/登录到桌面的时刻。
    /// 只填首次起点，防止当日后续解锁覆盖早晨到公司的时间。
    func recordOfficePresenceStart(workday: String, at date: Date) {
        guard let database else { return }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "INSERT INTO work_sessions (workday, started_at, planned_seconds, presence_started_at) VALUES (?, ?, 0, ?) ON CONFLICT(workday) DO UPDATE SET presence_started_at = COALESCE(work_sessions.presence_started_at, excluded.presence_started_at)"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(statement, 1, workday, -1, sqliteTransient)
        sqlite3_bind_double(statement, 2, date.timeIntervalSinceReferenceDate)
        sqlite3_bind_double(statement, 3, date.timeIntervalSinceReferenceDate)
        sqlite3_step(statement)
        startOfficePresenceSegment(workday: workday, at: date)
    }

    /// 仅在已有真实起点且还未结束时写入；熄屏/睡眠可能重复通知，首个时刻即为最终结果。
    func recordOfficePresenceEnd(workday: String, at date: Date) {
        guard let database else { return }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "UPDATE work_sessions SET presence_ended_at = ? WHERE workday = ? AND presence_started_at IS NOT NULL AND presence_ended_at IS NULL"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_double(statement, 1, date.timeIntervalSinceReferenceDate)
        sqlite3_bind_text(statement, 2, workday, -1, sqliteTransient)
        sqlite3_step(statement)
        endOpenOfficePresenceSegment(workday: workday, at: date)
    }

    /// 开始一段在岗；该工作日已有开放片段时忽略，防止睡醒通知重复创建。
    func startOfficePresenceSegment(workday: String, at date: Date) {
        guard let database else { return }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "INSERT OR IGNORE INTO office_presence_segments (workday, started_at) VALUES (?, ?)"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(statement, 1, workday, -1, sqliteTransient)
        sqlite3_bind_double(statement, 2, date.timeIntervalSinceReferenceDate)
        sqlite3_step(statement)
    }

    /// 封存当前开放片段；重复的睡眠/关机通知不会覆盖第一次离开时刻。
    func endOpenOfficePresenceSegment(workday: String, at date: Date) {
        guard let database else { return }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "UPDATE office_presence_segments SET ended_at = ? WHERE workday = ? AND ended_at IS NULL"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_double(statement, 1, date.timeIntervalSinceReferenceDate)
        sqlite3_bind_text(statement, 2, workday, -1, sqliteTransient)
        sqlite3_step(statement)
    }

    func officePresenceSegments(workday: String) -> [OfficePresenceSegment] {
        guard let database else { return [] }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "SELECT id, started_at, ended_at FROM office_presence_segments WHERE workday = ? ORDER BY started_at ASC, id ASC"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_text(statement, 1, workday, -1, sqliteTransient)
        var result: [OfficePresenceSegment] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let endedAt: Date? = sqlite3_column_type(statement, 2) == SQLITE_NULL ? nil : Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 2))
            result.append(OfficePresenceSegment(id: sqlite3_column_int64(statement, 0), workday: workday,
                                                startedAt: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 1)), endedAt: endedAt))
        }
        return result
    }

    func hasCompletedOfficePresenceSegment(workday: String) -> Bool {
        officePresenceSegments(workday: workday).contains { $0.endedAt != nil }
    }

    func hasOpenOfficePresenceSegment(workday: String) -> Bool {
        officePresenceSegments(workday: workday).contains { $0.endedAt == nil }
    }

    func officePresenceSeconds(workday: String, now: Date, includeOpenSegment: Bool) -> TimeInterval {
        officePresenceSegments(workday: workday).reduce(0) { total, segment in
            if let endedAt = segment.endedAt { return total + max(0, endedAt.timeIntervalSince(segment.startedAt)) }
            return includeOpenSegment ? total + max(0, now.timeIntervalSince(segment.startedAt)) : total
        }
    }

    func officePresenceSession(workday: String) -> OfficePresenceSession? {
        let segments = officePresenceSegments(workday: workday)
        if let first = segments.first {
            return OfficePresenceSession(workday: workday, startedAt: first.startedAt,
                                         endedAt: segments.contains { $0.endedAt == nil } ? nil : segments.last?.endedAt)
        }
        guard let database else { return nil }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "SELECT presence_started_at, presence_ended_at FROM work_sessions WHERE workday = ? AND presence_started_at IS NOT NULL"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(statement, 1, workday, -1, sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        let endedAt: Date? = sqlite3_column_type(statement, 1) == SQLITE_NULL
            ? nil : Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 1))
        return OfficePresenceSession(workday: workday,
                                     startedAt: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 0)),
                                     endedAt: endedAt)
    }

    /// 返回区间内已封存的真实在岗记录，供幸福指数等历史统计使用。
    /// 未结束的今天、旧版本缺少真实在岗时间的记录都不会被当作完整工作日。
    func completedOfficeSessions(from firstWorkday: String, through lastWorkday: String) -> [HappinessScore.Session] {
        guard let database else { return [] }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = """
        SELECT workday, planned_seconds, presence_started_at, presence_ended_at
        FROM work_sessions
        WHERE workday >= ? AND workday <= ?
        ORDER BY workday ASC
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_text(statement, 1, firstWorkday, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, lastWorkday, -1, sqliteTransient)
        var result: [HappinessScore.Session] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let workdayText = sqlite3_column_text(statement, 0) else { continue }
            let workday = String(cString: workdayText)
            let segments = officePresenceSegments(workday: workday)
            if !segments.isEmpty {
                guard !segments.contains(where: { $0.endedAt == nil }) else { continue }
                let seconds = officePresenceSeconds(workday: workday, now: Date(), includeOpenSegment: false)
                result.append(HappinessScore.Session(workday: workday,
                                                     plannedSeconds: max(0, sqlite3_column_double(statement, 1)),
                                                     presenceSeconds: seconds))
            } else if sqlite3_column_type(statement, 2) != SQLITE_NULL,
                      sqlite3_column_type(statement, 3) != SQLITE_NULL {
                let started = sqlite3_column_double(statement, 2)
                let ended = sqlite3_column_double(statement, 3)
                result.append(HappinessScore.Session(workday: workday,
                                                     plannedSeconds: max(0, sqlite3_column_double(statement, 1)),
                                                     presenceSeconds: max(0, ended - started)))
            }
        }
        return result
    }

    private func execute(_ sql: String) {
        guard let database else { return }
        sqlite3_exec(database, sql, nil, nil, nil)
    }
}
