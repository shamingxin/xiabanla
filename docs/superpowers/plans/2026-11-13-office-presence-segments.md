# 多段在岗续计 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Continue same-workday overtime after a sleep/shutdown and later valid unlock while excluding offline intervals.

**Architecture:** Add a backwards-compatible SQLite segment table, migrate legacy single presence rows into it, and make `ActivityStore` own all segment reads/writes. `WorkTimerModel` will keep one open segment at a time, end it on post-work departure, and start a new one when a later valid unlock occurs before the 05:00 boundary.

**Tech Stack:** Swift 5, Foundation, SQLite3, SwiftUI/AppKit, shell-based Swift assertion tests.

## Global Constraints

- Keep `work_sessions` and its legacy presence fields readable; never fabricate a historical shutdown time.
- Use 05:00 as the workday boundary; no external data, network, or location inference.
- Continue only on this company computer after valid unlock evidence; offline intervals are not work time.
- Do not commit without explicit user authorization.

---

### Task 1: Add and test segment persistence

**Files:**
- Modify: `Sources/下班啦/ActivityStore.swift`
- Modify: `Tests/ActivityStoreTests.swift`

**Produces:** `OfficePresenceSegment`, `startOfficePresenceSegment`, `endOpenOfficePresenceSegment`, `officePresenceSegments`, and `officePresenceSeconds`.

- [ ] **Step 1: Write failing tests** for two finished segments totaling 11 hours while a 90-minute offline gap is excluded; a repeated end must retain the first endpoint; legacy `presence_started_at`/`presence_ended_at` must appear once after migration.
- [ ] **Step 2: Run `./Tests/run.sh`** and verify the missing segment API fails.
- [ ] **Step 3: Create `office_presence_segments`** with `id INTEGER PRIMARY KEY`, `workday TEXT`, `started_at REAL`, `ended_at REAL`, a partial unique index for one open segment per workday, and a unique `(workday, started_at)` migration guard. Migrate legacy rows with `INSERT OR IGNORE`.
- [ ] **Step 4: Implement segment operations** using parameterized SQLite statements. Starting a segment does nothing when one is already open; ending updates only an open segment; reads sort by start time; total is the sum of completed segments plus the optional open segment through the supplied `now`.
- [ ] **Step 5: Run `./Tests/run.sh`** and verify all existing and new persistence tests pass.

### Task 2: Aggregate screen-time from segments

**Files:**
- Modify: `Sources/下班啦/ScreenTimeSupport.swift`
- Modify: `Sources/下班啦/ScreenTimeView.swift`
- Modify: `Tests/ActivityStoreTests.swift`

**Produces:** a segment-aware `ScreenTimeDuration.seconds` and week/day display based on ActivityStore totals.

- [ ] **Step 1: Write failing test** asserting two 9:00–19:00 / 20:30–21:30 segments display 11 hours, not the wall-clock 12.5 hours.
- [ ] **Step 2: Run `./Tests/run.sh`** and confirm the old single-session-only duration API cannot satisfy the test.
- [ ] **Step 3: Change the screen-time lookup** to call `activity.officePresenceSeconds(workday:now:isCurrentWorkday:)`; retain the planned-hours fallback only when no real segment exists.
- [ ] **Step 4: Run `./Tests/run.sh`** and verify all duration tests pass.

### Task 3: Resume overtime after valid same-day unlock

**Files:**
- Modify: `Sources/下班啦/WorkTimerModel.swift`
- Modify: `Tests/AutoStartTests.swift`

**Produces:** an ended current segment on departure and a fresh segment on valid post-work unlock before 05:00.

- [ ] **Step 1: Write failing pure-rule tests** for “post-work ended day + valid unlock before 05:00 resumes”, “unlock before planned end does not create an extra segment”, and “05:00 boundary never resumes the prior day”.
- [ ] **Step 2: Run `./Tests/run.sh`** and confirm the new resume rule is absent.
- [ ] **Step 3: Update WorkTimerModel** so departure calls `endOpenOfficePresenceSegment`; the existing `isResting` state reflects no open segment. In `checkAutoStart`, after validation of unlock evidence, start a segment when a current-day completed segment exists and `now >= endTime`; do not consume the first-arrival AutoStartGate path.
- [ ] **Step 4: Keep manual start behavior** opening the first segment, and ensure repeated sleep/wake notifications do not create duplicate opens or overwrite ends.
- [ ] **Step 5: Run `./Tests/run.sh && ./build.sh`** and verify compilation plus all assertions.

### Task 4: Launch and document

**Files:**
- Modify: `docs/project-context/CURRENT.md`

- [ ] **Step 1: Restart** with `pkill -x 下班啦 || true; open build/下班啦.app`.
- [ ] **Step 2: Inspect** current screen-time display and verify existing records remain readable after migration.
- [ ] **Step 3: Update** `CURRENT.md` with the segment behavior, test evidence, and the single real-world follow-up: sleep/valid-unlock/sleep on the company computer.
