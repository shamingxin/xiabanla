# Daily Presence Summary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show daily arrival time, off-work time, and overtime beside the existing total presence duration.

**Architecture:** Add a small pure `DailyPresenceSummary` type in `ScreenTimeSupport.swift` that derives display-ready daily fields from presence segments and a stored planned duration. `ScreenTimeView` consumes it for a three-column summary; SQLite recording and the existing total-duration calculation remain unchanged.

**Tech Stack:** Swift 5, SwiftUI, Foundation, existing shell-based `swiftc` tests.

## Global Constraints

- Keep actual-presence recording semantics unchanged: sleep, screen-off, and shutdown intervals never count.
- Use data captured in `work_sessions.planned_seconds` for historical overtime; never recalculate history from current settings.
- Chinese copy is exactly 「到岗时间」「下班时间」「加班时长」.
- Do not show segment rows, an explanatory paragraph, or a synthetic historical end time.
- Use settings-palette and theme-accent environment values in SwiftUI; do not hard-code UI colors.

---

### Task 1: Add and test the pure daily-summary calculation

**Files:**
- Modify: `Sources/下班啦/ScreenTimeSupport.swift`
- Modify: `Tests/ActivityStoreTests.swift`
- Modify: `Tests/run.sh`

**Interfaces:**
- Consumes: `[OfficePresenceSegment]`, `plannedSeconds: TimeInterval`, `now: Date`, `isCurrentWorkday: Bool`.
- Produces: `DailyPresenceSummary(arrivalTime: Date?, departure: DailyPresenceSummary.Departure, overtimeSeconds: TimeInterval?)`.

- [x] **Step 1: Write the failing tests**

```swift
let completedSummary = DailyPresenceSummary.make(
    segments: [OfficePresenceSegment(id: 1, workday: "2026-11-14", startedAt: date(14, 9), endedAt: date(14, 18, 30))],
    plannedSeconds: 9 * 3600, now: date(14, 22), isCurrentWorkday: false)
check("摘要显示到岗时间", completedSummary.arrivalTime, date(14, 9))
check("摘要显示下班时间", completedSummary.departure, .recorded(date(14, 18, 30)))
check("摘要显示加班时长", completedSummary.overtimeSeconds, 30 * 60)
```

Also test multi-segment aggregation, an open current segment yielding `.stillPresent`, and no segments yielding nil fields.

- [x] **Step 2: Run the focused test to verify it fails**

Run: `./Tests/run.sh`

Expected: compilation failure because `DailyPresenceSummary` does not exist.

- [x] **Step 3: Add the minimal summary type**

```swift
enum DailyPresenceSummary {
    enum Departure: Equatable { case recorded(Date), stillPresent, unavailable }
    static func make(segments: [OfficePresenceSegment], plannedSeconds: TimeInterval,
                     now: Date, isCurrentWorkday: Bool) -> Self { /* derive fields */ }
}
```

Calculate total using ended segments and the open segment only on the current workday; use the earliest `startedAt`, and only expose the latest end if no segment remains open.

- [x] **Step 4: Run the focused test to verify it passes**

Run: `./Tests/run.sh`

Expected: all existing suites pass, including the new daily-summary assertions.

### Task 2: Render the compact three-field daily card

**Files:**
- Modify: `Sources/下班啦/ScreenTimeView.swift`
- Test: `Tests/ActivityStoreTests.swift`

**Interfaces:**
- Consumes: `DailyPresenceSummary.make(...)` from Task 1.
- Produces: a day-only SwiftUI `HStack`/grid with labels, formatted values, and the existing summary card layout.

- [x] **Step 1: Add view assertions that define presentation values**

Add pure helper tests for no-overtime and unavailable-record cases, so the view consumes a bounded display model rather than duplicating date and duration rules.

- [x] **Step 2: Run tests to verify the new assertion fails**

Run: `./Tests/run.sh`

Expected: compilation failure for the new display helper or incorrect expected value.

- [x] **Step 3: Implement the day-only metrics**

Add a three-column metrics row below the existing day total:

```swift
if period == .day {
    DailyPresenceMetrics(summary: dailyPresenceSummary)
}
```

Format arrival/departure as `HH:mm`; map `.stillPresent` to 「仍在岗」 and unavailable fields to 「未记录」. Format positive overtime as existing hour/minute copy and all non-positive overtime as 「—」. Keep the week view unchanged.

- [x] **Step 4: Run tests to verify the presentation helper passes**

Run: `./Tests/run.sh`

Expected: all tests pass.

### Task 3: Verify build and local application result

**Files:**
- Modify: `docs/project-context/CURRENT.md`

**Interfaces:**
- Consumes: finished source and test changes from Tasks 1–2.
- Produces: rebuilt `build/下班啦.app` and project handoff note.

- [x] **Step 1: Build the macOS application**

Run: `./build.sh`

Expected: successful arm64 macOS 13+ build at `build/下班啦.app`.

- [x] **Step 2: Validate signature**

Run: `codesign --verify --deep --strict build/下班啦.app`

Expected: exit status 0.

- [x] **Step 3: Restart the built application**

Run: `pkill -x 下班啦 || true; open build/下班啦.app`

Expected: the rebuilt app is running; its day view shows only the three approved labels below total presence.

- [x] **Step 4: Record verification status**

Update `docs/project-context/CURRENT.md` with the feature, commands run, and any remaining real-device observation.
