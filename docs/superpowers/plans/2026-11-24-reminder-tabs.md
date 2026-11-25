# Reminder Tabs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the stacked reminder categories with a screenshot-inspired segmented control for water, rest, and off-work reminders.

**Architecture:** `SettingsView` owns non-persisted tab state, resetting to water when the user leaves the reminder page. A focused `ReminderTabControl` renders the three-way capsule selector; the existing row builders remain the source of each category's settings and switches.

**Tech Stack:** SwiftUI, AppKit cursor feedback, existing shell-based regression tests.

## Global Constraints

- Use the existing `SettingsPalette` and theme-aware colors; do not hard-code a page background.
- The segmented control lives beneath the page title, with the screenshot's compact capsule treatment.
- Retain each category's existing “动画提醒” switch and settings behavior inside its selected tab.
- Default to and reset to “喝水” when returning to the reminder page.

---

### Task 1: Add reminder category tabs

**Files:**
- Modify: `Sources/下班啦/SettingsView.swift:130-460`
- Modify: `Tests/ReminderSelectionTests.swift:56-75`

**Interfaces:**
- Produces: `ReminderTab` (`water`, `rest`, `offWork`) and `ReminderTabControl(selection:)`.
- Consumes: Existing `waterReminderSection`, `eggRows`, `offWorkRows`, `SettingsCard`, and `SettingsSwitch`.

- [ ] **Step 1: Write the failing source regression tests**

```swift
check("提醒页提供喝水休息下班三个分段 Tab", settingsSource.contains("private enum ReminderTab: String, CaseIterable"))
check("提醒页只展示当前 Tab 的设置", settingsSource.contains("ReminderTabControl(selection: $selectedReminderTab)") && settingsSource.contains("switch selectedReminderTab"))
```

- [ ] **Step 2: Verify the tests fail**

Run: `./Tests/run.sh`

Expected: the new tab checks fail because the current page renders all three categories in one vertical stack.

- [ ] **Step 3: Implement the smallest focused view change**

```swift
ReminderTabControl(selection: $selectedReminderTab)
switch selectedReminderTab {
case .water: waterReminderSection
case .rest: SettingsCard { eggRows }
case .offWork: SettingsCard { offWorkRows }
}
```

Implement the accompanying `ReminderTabControl` with a capsule outline, selected neutral fill, 34pt height, separators, pointer cursor, and accessible selected state.

- [ ] **Step 4: Verify behavior and build**

Run: `./Tests/run.sh && ./build.sh && codesign --verify --deep --strict build/下班啦.app`

Expected: all tests, compilation, and signature verification succeed.
