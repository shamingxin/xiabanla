# 屏幕时间与喝水记录 Implementation Plan

> 状态：2026-11-12 已在本地实现并通过 `Tests/run.sh` 与 `build.sh`。以下清单保留为实施历史；当前接力入口以 `docs/project-context/CURRENT.md` 为准。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local activity history, actionable water reminders, and a Screen Time-style settings page for work and water statistics.

**Architecture:** `ActivityStore` owns append-only SQLite events and query-safe day/week aggregates. `ReminderModel` records and resets water cycles through that store; `BubbleController` supplies explicit water actions. `ScreenTimeView` consumes immutable summaries plus the existing work model and remains presentation-only.

**Tech Stack:** Swift 5, SwiftUI/AppKit, SQLite3, AVFoundation, existing shell-based `swiftc` tests.

## Global Constraints

- macOS 13+, arm64; do not use `#Preview` or Swift Charts.
- Settings values remain UserDefaults; activity data uses Application Support SQLite only.
- Current worktree is `main` with explicit user authorization; preserve unrelated project-context document edits.
- Keep the existing fixed 678pt settings width and palette/theme environment values.
- Do not implement arbitrary custom reminders, upload, cloud sync, or export/import in this release.

---

### Task 1: Add an independently testable activity event store

**Files:**
- Create: `Sources/下班啦/ActivityStore.swift`
- Create: `Tests/ActivityStoreTests.swift`
- Modify: `Tests/run.sh`

**Interfaces:**
- Produces `ActivityAction`, `ActivityEvent`, `ActivityDaySummary`, `ActivityStore.record(kind:action:at:)`, `summary(for:)`, and `events(on:)`.

- [ ] Write tests that record prompted/completed/deferred events at supplied dates and assert date-local totals, chronological records, and a zero-data day.
- [ ] Run the isolated activity test command and confirm it fails because `ActivityStore` does not exist.
- [ ] Implement SQLite database-directory creation, schema creation, parameter-bound inserts, reads, and deterministic aggregate helpers.
- [ ] Run activity tests and `./Tests/run.sh`; both must pass.

### Task 2: Make strong water reminders record explicit responses

**Files:**
- Modify: `Sources/下班啦/BubbleController.swift`
- Modify: `Sources/下班啦/ReminderModel.swift`
- Modify: `Sources/下班啦/AppDelegate.swift`
- Modify: `Tests/ActivityStoreTests.swift`

**Interfaces:**
- Consumes `ActivityStore`.
- Produces `ReminderModel.respondToWater(_:)` and `BubbleController.show(..., actions:)`.

- [ ] Write failing tests that a shown water reminder records `prompted`; either response records exactly its selected action and resets the injected anchors to the response time.
- [ ] Run the test and confirm the failure is missing response support, not a compiler error.
- [ ] Extend the bubble presentation payload with optional primary/secondary actions; show buttons only for sticky water; wire callbacks to `ReminderModel` and dismiss the panel.
- [ ] Preserve automatic/non-sticky video behavior and off-work forced replacement; run all tests.

### Task 3: Add current-work duration and history-friendly summary APIs

**Files:**
- Modify: `Sources/下班啦/WorkTimerModel.swift`
- Modify: `Tests/ActivityStoreTests.swift`

**Interfaces:**
- Produces `WorkTimerModel.workedSeconds(at:)` and `WorkTimerModel.weekdayWorkSeconds(reference:)`.

- [ ] Write failing tests for no arrival, an active shift, and post-end cutoff so overtime is excluded.
- [ ] Implement the smallest pure duration helpers using existing `progressStart`/`endTime` semantics, injecting `Date` for tests.
- [ ] Run the test suite and confirm all current auto-start tests remain green.

### Task 4: Add the Screen Time settings page

**Files:**
- Create: `Sources/下班啦/ScreenTimeView.swift`
- Modify: `Sources/下班啦/SettingsView.swift`
- Modify: `Sources/下班啦/AppDelegate.swift`

**Interfaces:**
- Consumes `WorkTimerModel`, `ActivityStore`, palette and theme-accent environments.
- Produces `ScreenTimeView` with daily/weekly modes and empty states.

- [ ] Add the `screenTime` sidebar item with a purple `hourglass` icon and route it to the new view.
- [ ] Implement SwiftUI-drawn weekly bars, average rule, hourly stacked event bars, summary metrics and event list without fabricated values.
- [ ] Use semantic labels for the switcher, bars and response counts; apply the shared palette rather than hardcoded white/black.
- [ ] Build with `./build.sh` and manually inspect both deep and light mode.

### Task 5: Update copy and perform end-to-end verification

**Files:**
- Modify: `Sources/下班啦/SettingsView.swift`
- Modify: `README.md`
- Modify: `docs/project-context/CURRENT.md`

**Interfaces:**
- Documents final wording: 「屏幕时间」「我喝啦」「还不渴」 and the local-only data policy.

- [ ] Verify water reminder copy no longer says “需手动关闭动画”; use “需要回应提醒” instead.
- [ ] Run `./Tests/run.sh`, `./build.sh`, and relaunch the built app with `pkill -x 下班啦 && open build/下班啦.app`.
- [ ] Visually verify the sidebar icon, daily/weekly switcher, no-data display, both water actions and next-cycle reset.

## Self-review

- Spec coverage: Tasks 1–2 cover durable actions and reminder behavior; Task 3 supplies work-time semantics; Task 4 covers the visual dashboard; Task 5 covers copy and verification.
- Scope: custom reminder creation, importing media, cloud sync and backup are intentionally excluded from this plan.
- Type consistency: `ActivityStore` is injected into `ReminderModel`, then passed into `ScreenTimeView` by `SettingsView`; no view directly opens SQLite.
