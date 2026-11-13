# 本周幸福指数 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a playful, testable weekly happiness-index measurement flow to the macOS settings window.

**Architecture:** Keep score calculation in a Foundation-only support file so SQLite and UI code only supply sessions and render results. Extend `ActivityStore` with one range query, then add one self-contained SwiftUI view that owns the idle/loading/result state and connects to the existing settings sidebar.

**Tech Stack:** Swift 5, SwiftUI, AppKit, SQLite3, Command Line Tools, shell-based Swift assertion tests.

## Global Constraints

- Support arm64 macOS 13+; do not add package dependencies or external imagery.
- Use recorded `WorkSession.plannedSeconds` and only ended `OfficePresenceSession` records; no system screen-time or network data.
- Follow existing `SettingsPalette`, `themeAccent`, light/dark mode, and Reduce Motion conventions.
- Keep existing screen-time behavior and SQLite schema unchanged.
- Do not create a Git commit without explicit user authorization.
- Bundle the user-supplied MP4 locally; it must be muted, looped, control-free, and never affect reminder-bubble playback.

---

### Task 1: Implement and test the score domain

**Files:**
- Create: `Sources/下班啦/HappinessScore.swift`
- Create: `Tests/HappinessScoreTests.swift`
- Modify: `Tests/run.sh`

**Consumes:** `WorkSession`, `OfficePresenceSession` from `ActivityStore.swift`.

**Produces:** `HappinessScore.Day`, `HappinessScore.WeeklySummary`, `HappinessScore.weeklySummary(sessions:)`, and deterministic score/tier/copy inputs.

- [ ] **Step 1: Write failing tests**

```swift
let onTime = HappinessScore.Session(workday: "2026-11-10", plannedSeconds: 9 * 3600,
                                    presenceSeconds: 9 * 3600)
check("准时下班满分", HappinessScore.dailyScore(for: onTime), 100)
check("加班一小时扣至 70", HappinessScore.dailyScore(for: .init(workday: "2026-11-11", plannedSeconds: 9 * 3600, presenceSeconds: 10 * 3600)), 70)
check("一周取平均并忽略未封存", HappinessScore.weeklySummary(sessions: [onTime, overHour, open]).score, 85)
```

- [ ] **Step 2: Run the new test target and confirm it fails because `HappinessScore` is absent.**

Run: extend `Tests/run.sh`, then run `./Tests/run.sh`.

- [ ] **Step 3: Add the domain types and calculation.**

```swift
enum HappinessScore {
    struct Session: Equatable { let workday: String; let plannedSeconds, presenceSeconds: TimeInterval }
    struct WeeklySummary: Equatable { let days: [Day]; var score: Int?; var overtimeSeconds: TimeInterval; var onTimeDays: Int }
    static func dailyScore(for session: Session) -> Int {
        max(0, min(100, Int((100 - max(0, session.presenceSeconds - session.plannedSeconds) / 60 * 0.5).rounded())))
    }
}
```

Build the weekly summary from supplied, ended sessions only; use rounded arithmetic mean and the tiers specified in the approved design.

- [ ] **Step 4: Run `./Tests/run.sh` and confirm all score tests pass.**

### Task 2: Read completed work sessions by week

**Files:**
- Modify: `Sources/下班啦/ActivityStore.swift`
- Modify: `Tests/ActivityStoreTests.swift`

**Consumes:** ISO workday strings and SQLite `work_sessions` rows.

**Produces:** `ActivityStore.completedOfficeSessions(from:through:) -> [HappinessScore.Session]`.

- [ ] **Step 1: Add failing SQLite fixture assertions.**

Record two planned sessions, end only one presence session, query an inclusive week range, and assert that only the ended row is returned with its persisted plan and duration.

- [ ] **Step 2: Implement one parameterized query.**

```sql
SELECT workday, planned_seconds, presence_started_at, presence_ended_at
FROM work_sessions
WHERE workday >= ? AND workday <= ?
  AND presence_started_at IS NOT NULL AND presence_ended_at IS NOT NULL
ORDER BY workday ASC
```

Convert each row to `HappinessScore.Session`, clamp duration to zero, and return `[]` when SQLite is unavailable.

- [ ] **Step 3: Run `./Tests/run.sh` and confirm database and score suites pass.**

### Task 3: Build the happiness measurement experience

**Files:**
- Create: `Sources/下班啦/HappinessIndexView.swift`
- Modify: `Sources/下班啦/SettingsView.swift`

**Consumes:** `ActivityStore.completedOfficeSessions(from:through:)`, `HappinessScore.weeklySummary(sessions:)`, `SettingsPalette`, and `themeAccent`.

**Produces:** Initial invitation state, 2-second staged loading state, result-card state, and a callback to select “屏幕时间”.

- [ ] **Step 1: Add the sidebar case.**

Add `.happinessIndex = "幸福指数"` directly after `.screenTime`, with `face.smiling.fill` and an amber tint. Add `case .happinessIndex` in every sidebar switch, creating `HappinessIndexView(activity: reminders.activityStore, showScreenTime: { selectedSection = .screenTime })`.

- [ ] **Step 2: Create the view state and weekly data lookup.**

```swift
private enum MeasurementState { case invitation, measuring(Int), result(HappinessScore.WeeklySummary, CardPersona) }
private var weekStart: Date { /* Monday for current local calendar week */ }
private func measure() { /* staged Task sleeps: 0, 0.65, 1.3, 2.0 seconds */ }
```

Use three static status strings from the approved spec. Query Monday through Sunday when measurement begins; do not create or persist data.

- [ ] **Step 3: Render the two visual states.**

Create a lightweight vector `HappinessMascot` from circles, strokes, and SF Symbols. In invitation state show randomized opener copy and `测一下本周幸福指数`; in measuring state use a progress capsule and staged message. Honor `accessibilityReduceMotion` by replacing repeat animations with opacity.

Create `HappinessResultCard` as a large rounded paper-like card showing the English masthead, large score or no-data text, days measured, on-time days, overtime, tier, and persona-specific interpretation. Keep the card warm neutral in light mode and charcoal-paper in dark mode; use the environment accent only for small decorative details.

- [ ] **Step 4: Add result actions.**

`再测一次` replaces the persona and card doodle without recalculating score; `查看本周记录` invokes `showScreenTime`. For no data, retain the first action but hide numeric-only rows and describe why there is no score.

- [ ] **Step 5: Build and run all tests.**

Run: `./Tests/run.sh && ./build.sh`.

Expected: all assertion lines report success and `build/下班啦.app` is rebuilt without compiler errors.

### Task 4: Verify product integration

**Files:**
- Modify: `docs/project-context/CURRENT.md`

**Consumes:** built application and the implemented page.

**Produces:** an accurate handoff note describing implementation and remaining visual confirmation.

- [ ] **Step 1: Launch the rebuilt app using the repository command.**

Run: `pkill -x 下班啦 || true; open build/下班啦.app`.

- [ ] **Step 2: Inspect the sidebar, initial measurement view, staged loading, result card, no-data result, and screen-time navigation.**

Use the actual settings window. Confirm both dark and light modes manually if available.

- [ ] **Step 3: Update `CURRENT.md` with build/test evidence and list only visual checks that require the user screenshot.**

### Task 5: Replace the mascot with a native media preview and tighten layout

**Files:**
- Create: `Assets/Videos/幸福指数/幸福指数.mp4`
- Modify: `build.sh`
- Modify: `Sources/下班啦/HappinessIndexView.swift`
- Modify: `docs/project-context/CURRENT.md`

**Consumes:** the supplied `/Users/shasha/Downloads/视频28_1112_182851.mp4` and AppKit `AVPlayerLayer` / `AVQueuePlayer`.

**Produces:** a self-contained, muted looping `HappinessVideoView`, shared by invitation and measuring states, and Apple-settings-style content spacing.

- [ ] **Step 1: Copy the supplied video into the happiness asset folder.**

Use `cp` only for this user-provided binary asset. Keep its original bytes; do not transcode because the app already packages `Assets/Videos` recursively.

- [ ] **Step 2: Add a standalone native looping-video wrapper.**

```swift
struct HappinessVideoView: NSViewRepresentable {
    func makeNSView(context: Context) -> LoopingVideoHost { ... }
    func updateNSView(_ view: LoopingVideoHost, context: Context) { view.setVisible(isVisible) }
}
```

`LoopingVideoHost` owns one muted `AVQueuePlayer`, `AVPlayerLooper`, and `AVPlayerLayer`; use `.resizeAspectFill`, `videoGravity`, `layer.cornerRadius`, and `masksToBounds`. Pause on `viewDidMoveToWindow` when no window is attached and resume only while visible.

- [ ] **Step 3: Recompose the three page states.**

Replace both `HappinessMascot` placements in invitation/measuring states with one 16:9 `HappinessMediaCard` using `HappinessVideoView`. Set a centered content column with max width 440pt; use 16pt media-to-copy spacing, 24–28pt section spacing, a 40pt content-width primary button, and secondary explanatory copy. Keep result-card actions 16pt below the card and preserve the existing tested score flow.

- [ ] **Step 4: Build and visually verify.**

Run `./Tests/run.sh && ./build.sh`, restart the app, enter 「幸福指数」, confirm muted looping preview, compact invitation layout, unchanged staged measurement and result actions. Then record the outcome in `CURRENT.md`.
