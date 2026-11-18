# Reminder Animation Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users choose the water and easter-egg animations that participate in random playback.

**Architecture:** Keep a file-name selection set per `ReminderKind` in `ReminderModel`, persisted in `UserDefaults`. `VideoLibrary` supplies stable, sorted bundled files; the model filters that library before using the existing round-robin random picker. `SettingsView` consumes the model’s video list and selection bindings to render compact four-column thumbnail controls.

**Tech Stack:** Swift 5, SwiftUI, AppKit/AVFoundation, UserDefaults, existing shell-run Swift assertions.

## Global Constraints

- Water and egg libraries are independent and default to all bundled files selected.
- A library must always retain one selected animation.
- Actual reminders and random preview use the same selected-only pool.
- UI uses `cardPalette`, `settingsPalette`, and `themeAccent`; no hard-coded settings background or accent colors.
- The Settings window remains scrollable and preserves its existing sizing behavior.

---

### Task 1: Test and implement selected-video state

**Files:**
- Modify: `Tests/ReminderSelectionTests.swift`
- Modify: `Tests/run.sh`
- Modify: `Sources/下班啦/ReminderModel.swift`

**Interfaces:**
- Produces: `VideoSelectionState.selectedNames(_:available:) -> Set<String>`
- Produces: `VideoSelectionState.toggling(_:name:available:) -> Set<String>`
- Produces: `VideoSelectionState.filtered(_:selected:) -> [URL]`

- [ ] **Step 1: Write failing tests**

```swift
let urls = [url("a.mp4"), url("b.mp4")]
check("未存设置默认全选", VideoSelectionState.selectedNames(nil, available: urls) == ["a.mp4", "b.mp4"])
check("最后一项不可取消", VideoSelectionState.toggling(["a.mp4"], name: "a.mp4", available: urls) == ["a.mp4"])
check("过滤只留下选中动画", VideoSelectionState.filtered(urls, selected: ["b.mp4"]).map(\.lastPathComponent) == ["b.mp4"])
```

- [ ] **Step 2: Run tests and verify red**

Run: `./Tests/run.sh`

Expected: compilation fails because `VideoSelectionState` is undefined.

- [ ] **Step 3: Implement the minimal pure state helper and model API**

```swift
enum VideoSelectionState {
    static func selectedNames(_ saved: [String]?, available: [URL]) -> Set<String> { ... }
    static func toggling(_ selected: Set<String>, name: String, available: [URL]) -> Set<String> { ... }
    static func filtered(_ available: [URL], selected: Set<String>) -> [URL] { ... }
}
```

Add `videos(_:)`, `selectedVideoNames(_:)`, `isVideoSelected(_:for:)`, and `toggleVideo(_:for:)` to `ReminderModel`; update the picker to use `VideoSelectionState.filtered`.

- [ ] **Step 4: Run tests and verify green**

Run: `./Tests/run.sh`

Expected: `ReminderSelectionTests` and existing suites print `全部通过`.

### Task 2: Render a compact animation library in settings

**Files:**
- Modify: `Sources/下班啦/SettingsView.swift`

**Interfaces:**
- Consumes: `ReminderModel.videos(_:)`, `selectedVideoNames(_:)`, `isVideoSelected(_:for:)`, `toggleVideo(_:for:)`, and `preview(_:)`.
- Produces: `ReminderAnimationLibrary` with a four-column thumbnail grid.

- [ ] **Step 1: Add an animation-library view**

```swift
private func animationLibrary(_ kind: ReminderKind) -> some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
        ForEach(reminders.videos(kind), id: \.self) { url in
            ReminderAnimationThumbnail(url: url, selected: reminders.isVideoSelected(url, for: kind)) {
                reminders.toggleVideo(url, for: kind)
            }
        }
    }
}
```

- [ ] **Step 2: Replace the old count-only `videoRow`**

Keep random preview, display selected count, and add concise selected-only and minimum-one help text. Insert the library below the active water and egg setting rows.

- [ ] **Step 3: Ensure accessibility and theme behavior**

Give every thumbnail an action label that names the video and selected state. Render selected borders/checkmarks with `themeAccent`; derive unselected styling from the palette.

### Task 3: Verify and restart

**Files:**
- Verify: `Tests/ReminderSelectionTests.swift`, `Tests/run.sh`, `build.sh`

- [ ] **Step 1: Run all pure-function checks**

Run: `./Tests/run.sh`

Expected: exit 0 and every suite passes.

- [ ] **Step 2: Build and verify the signed application**

Run: `./build.sh && codesign --verify --deep --strict build/下班啦.app`

Expected: build completes and signature verification exits 0.

- [ ] **Step 3: Restart the local app**

Run: `pkill -x 下班啦 || true; open build/下班啦.app`

Expected: local build relaunches with the compact animation grids ready for visual review.
