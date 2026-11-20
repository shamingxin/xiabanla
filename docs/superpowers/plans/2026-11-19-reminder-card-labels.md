# 提醒卡标题与动画提醒 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让喝水、放松与下班提醒三张设置卡片使用统一标题和「动画提醒」选择区，并让下班动画选择真正参与预览和提醒播放。

**Architecture:** `ReminderModel` 已按 `ReminderKind` 泛化了视频库、选择持久化与随机池；此次只需在既有通用选择逻辑上补下班类别测试，并在 `SettingsView` 将下班卡接入同一个动画库。文案统一在视图层完成，提醒调度仍通过 `pickVideo(.offWork)` 自动使用已选下班动画。

**Tech Stack:** Swift 5、SwiftUI、Foundation、现有 shell 驱动的纯 Swift 断言测试。

## Global Constraints

- 不修改已有喝水量统计、设置 hover 与安全重启的未提交行为。
- 现有用户未保存动画选择时必须默认全选；每类最后一项不得取消。
- 保持既有提醒计时、强制喝水、下班时刻去重和 5 列缩略图交互不变。
- 不提交任何改动，除非用户明确要求提交。

---

### Task 1: 统一三张提醒卡的文案与下班动画设置行

**Files:**
- Modify: `Sources/下班啦/SettingsView.swift:405-438`
- Test: `Tests/ReminderSelectionTests.swift`

**Interfaces:**
- Consumes: `animationLibrary(_ kind: ReminderKind) -> some View`、`reminders.preview(_:)`、`reminders.toggleVideo(_:for:)`。
- Produces: 三张卡片首行标题为「喝水提醒／放松提醒／下班提醒」，且启用后都有相同的「动画提醒」行。

- [x] **Step 1: 写入文本层面的失败测试或检查项**

在 `Tests/ReminderSelectionTests.swift` 中增加以下源文件检查，确保迁移后的可见文案存在：

```swift
let settingsSource = try! String(contentsOfFile: "Sources/下班啦/SettingsView.swift")
check("提醒卡使用放松提醒标题", settingsSource.contains("SettingsRow(\\\"放松提醒\\\")"))
check("动画设置统一叫动画提醒", settingsSource.contains("Text(\\\"动画提醒\\\")"))
check("下班提醒接入动画库", settingsSource.contains("animationLibrary(.offWork)"))
```

同一测试文件追加下班选择状态断言，覆盖已保存选择、最后一项保护和随机候选过滤：

```swift
let offWorkSelected = VideoSelectionState.selectedNames(saved: ["b.mp4"], available: available)
check("下班动画可恢复已保存选择", offWorkSelected == ["b.mp4"])
check("下班动画最后一项不可取消",
      VideoSelectionState.toggling(["b.mp4"], name: "b.mp4", available: available) == ["b.mp4"])
check("下班随机池只保留已选动画",
      VideoSelectionState.filtered(available, selected: offWorkSelected).map(\.lastPathComponent) == ["b.mp4"])
```

- [x] **Step 2: 运行测试并确认失败**

Run: `./Tests/run.sh`

Expected: 失败于上述三个界面检查，因为当前源码仍含「随机彩蛋」「播放动画」，且下班卡未调用动画库。

- [x] **Step 3: 实现最小视图改动**

```swift
SettingsRow("放松提醒") { SettingsSwitch(isOn: $reminders.eggEnabled) }

if reminders.offWorkEnabled {
    SettingsDivider()
    animationLibrary(.offWork)
}

Text("动画提醒").font(.system(size: 13))
```

保留 `animationLibrary` 的展开、缩略图、预览与 toast 实现。由于 `ReminderKind.offWork` 已属于 `allCases`，无需修改模型即可持久化并用已选下班动画预览/播放。

- [x] **Step 4: 运行全套测试，确认通过**

Run: `./Tests/run.sh`

Expected: 输出 `全部通过`。

### Task 2: 构建并作运行时检查

**Files:**
- Modify: `docs/project-context/CURRENT.md` only if verification status materially changes.
- Build output: `build/下班啦.app`

**Interfaces:**
- Consumes: `./build.sh`、`codesign --verify --deep --strict build/下班啦.app`。
- Produces: 可运行且签名有效的应用构建。

- [x] **Step 1: 静态检查差异**

Run: `git diff --check -- Sources/下班啦/SettingsView.swift Tests/ReminderSelectionTests.swift`

Expected: 无输出。

- [x] **Step 2: 构建应用**

Run: `./build.sh`

Expected: 成功生成并启动 `build/下班啦.app`；脚本会安全结束旧实例。

- [x] **Step 3: 校验签名**

Run: `codesign --verify --deep --strict build/下班啦.app`

Expected: 退出码 0。

- [x] **Step 4: 不提交**

保持改动未提交，等待用户基于实际界面确认效果后再决定是否提交。
