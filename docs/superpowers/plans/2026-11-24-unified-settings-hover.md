# Unified Settings Hover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every interactive settings control one visible, non-blocking hover state in light and dark appearances.

**Architecture:** A SwiftUI-owned hover surface is the sole renderer. Native AppKit controls retain input and menu behavior but call bindings that update the surrounding SwiftUI state.

**Tech Stack:** SwiftUI, AppKit, Swift command-line regression tests.

## Global Constraints

- Do not change timer, reminder, navigation, accessibility, or persistence behavior.
- Do not stage, commit, reset, stash, or overwrite existing changes.
- Hover layers must use `.allowsHitTesting(false)`.
- Keep native popup menus and date picker stepping behavior.

---

### Task 1: Define a failing regression guard for one visual owner

**Files:**
- Modify: `Tests/NeutralGlassMaterialTests.swift`
- Test: `Tests/run.sh`

**Interfaces:**
- Consumes: `SettingsView.swift` source text.
- Produces: a static guard requiring one shared picker hover surface and callback-driven native controls.

- [x] **Step 1: Write the failing test**

Add source checks that require `SettingsPicker` to use `palette.hoverSurface`, `palette.hoverStroke`, and the native popup to expose hover only through `onHover`.

- [x] **Step 2: Run test to verify it fails**

Run: `Tests/run.sh`

Expected: FAIL because the native popup still calls `applyHoverAppearance` and the picker still uses separate `Color.primary` values.

### Task 2: Consolidate picker and time-field hover rendering

**Files:**
- Modify: `Sources/下班啦/SettingsView.swift`
- Test: `Tests/NeutralGlassMaterialTests.swift`

**Interfaces:**
- Consumes: `SettingsPalette.hoverSurface`, `SettingsPalette.hoverStroke`, and native `onHover` callbacks.
- Produces: `SettingsPicker` and `TimeField` whose SwiftUI host owns visible hover feedback.

- [x] **Step 1: Implement the minimal visual owner**

Replace each picker's local `Color.primary` hover fill/stroke with palette tokens. Remove direct layer painting from `HoverPopUpButton`; retain its tracking area and `onHover` callback. Add an equivalent SwiftUI wrapper state for `TimeField` and make `HoverDatePicker` report hover through a callback.

- [x] **Step 2: Run the regression suite**

Run: `Tests/run.sh`

Expected: all tests pass.

### Task 3: Verify full interactive coverage and app artifact

**Files:**
- Modify: `Sources/下班啦/SettingsView.swift` only if a currently interactive control lacks the shared modifier.

**Interfaces:**
- Consumes: `SettingsHoverFeedback` and the picker/time-field host surface.
- Produces: common rendering for buttons, switches, option grids, popups, and time fields.

- [x] **Step 1: Inspect all interactive settings controls**

Run: `rg -n '\\.settingsHoverFeedback|SettingsPicker\\(|SettingsSwitch\\(|TimeField\\(' Sources/下班啦/SettingsView.swift`

Expected: every custom button/switch has `settingsHoverFeedback`, while each native field exposes its SwiftUI hover host.

- [x] **Step 2: Build and verify**

Run: `Tests/run.sh && ./build.sh && codesign --verify --deep --strict build/下班啦.app && git diff --check`

Expected: all commands exit 0 and the launched app is the rebuilt workspace artifact.
