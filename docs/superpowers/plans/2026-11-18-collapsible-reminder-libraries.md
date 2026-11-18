# 可收起提醒动画库 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让提醒动画库默认收起，并在离开“提醒动画”设置分区后重置为收起。

**Architecture:** 在 `ReminderModel.swift` 中新增无 UI 依赖的纯 Swift 状态值，保存喝水与彩蛋库在当前设置页会话中的展开项。`SettingsView` 使用它决定是否渲染缩略图网格，并在侧边栏分区变更时清空状态；视频选择及持久化仍由 `ReminderModel` 管理。

**Tech Stack:** Swift 5、SwiftUI、现有纯 `swiftc` 测试脚本。

## Global Constraints

- macOS 13+，不使用 `#Preview`。
- 展开状态不得写入 `UserDefaults`。
- 保持“预览动画”、视频选择、最后一项保护及随机池行为不变；按钮按系统常规尺寸绘制为 22pt。
- 离开“提醒动画”分区后，两类动画库必须重新收起。

---

### Task 1: 提取动画库的瞬态展开状态

**Files:**
- Modify: `Sources/下班啦/ReminderModel.swift`
- Modify: `Tests/ReminderSelectionTests.swift`
- Modify: `Tests/run.sh`

**Interfaces:**
- Produces: `ReminderLibraryExpansionState` with `isExpanded(_:)`, `toggle(_:)`, and `collapseAll()`.
- Consumes: existing `ReminderKind` enum.

- [ ] **Step 1: Write the failing test**

```swift
func testReminderLibraryExpansionState() {
    var state = ReminderLibraryExpansionState()
    check("喝水动画库默认收起", !state.isExpanded(.water))
    check("彩蛋动画库默认收起", !state.isExpanded(.egg))
    state.toggle(.water)
    check("喝水动画库可以展开", state.isExpanded(.water))
    check("展开喝水不影响彩蛋", !state.isExpanded(.egg))
    state.toggle(.egg)
    check("彩蛋动画库独立展开", state.isExpanded(.egg))
    state.collapseAll()
    check("离开页面后两个动画库均收起", !state.isExpanded(.water) && !state.isExpanded(.egg))
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./Tests/run.sh`

Expected: compilation failure because `ReminderLibraryExpansionState` is not defined.

- [ ] **Step 3: Write the minimal implementation**

```swift
struct ReminderLibraryExpansionState {
    private var expandedKinds: Set<ReminderKind> = []

    func isExpanded(_ kind: ReminderKind) -> Bool { expandedKinds.contains(kind) }

    mutating func toggle(_ kind: ReminderKind) {
        if expandedKinds.contains(kind) { expandedKinds.remove(kind) }
        else { expandedKinds.insert(kind) }
    }

    mutating func collapseAll() { expandedKinds.removeAll() }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `./Tests/run.sh`

Expected: the new state test and existing tests pass.

### Task 2: 更新提醒动画库界面及分区切换复位

**Files:**
- Modify: `Sources/下班啦/SettingsView.swift:128-181,407-451`

**Interfaces:**
- Consumes: `ReminderLibraryExpansionState` from Task 1.
- Consumes: existing `ReminderModel.preview(_:)`, `ReminderModel.toggleVideo(_:for:)` and `ReminderKind`.

- [ ] **Step 1: Add SettingsView state and reset hook**

```swift
@State private var libraryExpansion = ReminderLibraryExpansionState()

.onChange(of: selectedSection) { section in
    if section != .reminderAnimations { libraryExpansion.collapseAll() }
}
```

- [ ] **Step 2: Render the two action buttons**

```swift
Button("预览动画") { reminders.preview(kind) }
    .controlSize(.regular)
    .disabled(videos.isEmpty)
Button(libraryExpansion.isExpanded(kind) ? "收起" : "选择动画") {
    libraryExpansion.toggle(kind)
}
    .controlSize(.regular)
    .disabled(videos.isEmpty)
```

- [ ] **Step 3: Gate the existing empty-state and 5-column grid**

```swift
if libraryExpansion.isExpanded(kind) {
    if videos.isEmpty {
        Text("暂无可用动画。")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    } else {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 5), spacing: 7) {
            ForEach(videos, id: \\.self) { url in
                ReminderAnimationThumbnail(url: url, selected: reminders.isVideoSelected(url, for: kind), accent: accent, palette: palette) {
                    if !reminders.toggleVideo(url, for: kind) { showToast("至少保留一个动画。", duration: 2) }
                }
            }
        }
    }
}
```

- [ ] **Step 4: Run full verification**

Run: `./Tests/run.sh && ./build.sh && codesign --verify --deep --strict build/下班啦.app`

Expected: all tests, package build, and signature verification exit successfully.
