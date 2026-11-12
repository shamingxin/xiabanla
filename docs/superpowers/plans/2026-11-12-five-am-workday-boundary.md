# 凌晨五点工作日分界 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把工作日边界改为 05:00，并提供可恢复、可验证的“休息中”状态与跨 05:00 自动开始规则。

**Architecture:** `WorkTimerModel` 持久化前一工作日是否已在下班后封存以及可信的解锁状态；在 05:00 先结算旧会话、再切换到新工作日。`CountdownCardView` 根据模型的工作状态显示“休息中”，屏幕时间统一按新的工作日 key 处理当前会话。

**Tech Stack:** Swift 5、SwiftUI、AppKit/NSWorkspace 通知、SQLite3、现有 `swiftc` 断言测试。

## Global Constraints

- macOS 13+，不新增依赖；只用现有 Command Line Tools 构建。
- 自动开始必须 fail-closed：05:00 自动开始只接受已记录的真实解锁证据，睡眠/锁屏后证据失效。
- 弹性模式的真实 05:00 到岗仍由 10:00–12:00 区间钳制下班时刻。
- 工作日从 05:00 到次日 05:00；旧历史记录不改写，2026-11-11 的人工修正保持不变。
- 不提交、推送或创建 Release，除非用户明确要求。

---

### Task 1: 以 05:00 作为纯函数工作日与自动开始窗口边界

**Files:**
- Modify: `Sources/下班啦/WorkTimerModel.swift:70-77,532-561,627-633`
- Modify: `Tests/AutoStartTests.swift:15-115`

**Interfaces:**
- `WorkTimerModel.dayCutoffHour == 5`。
- `WorkTimerModel.shouldAutoStart(...)` 的最早时刻为工作日 05:00，而非 `startText - 60 分钟`。

- [ ] **Step 1: 写失败测试**

```swift
check("04:59 仍属前一工作日", WorkTimerModel.workdayKey(for: d(2026, 11, 13, 4, 59)) == WorkTimerModel.workdayKey(for: d(2026, 11, 12, 10, 0)), true)
check("05:00 起属新工作日", WorkTimerModel.workdayKey(for: d(2026, 11, 13, 5, 0)) == fri, true)
check("05:00 自动开始", auto(d(2026, 11, 13, 5, 0)), true)
check("04:59 不自动开始", auto(d(2026, 11, 13, 4, 59)), false)
```

- [ ] **Step 2: 运行并确认失败**

Run: `./Tests/run.sh`

Expected: 03:00 边界与 09:00 自动开始的旧实现导致新增断言失败。

- [ ] **Step 3: 最小实现**

```swift
static let dayCutoffHour = 5
static let autoStartEarliestHour = 5

let from = Calendar.current.date(bySettingHour: autoStartEarliestHour, minute: 0,
                                second: 0, of: base)!
```

保留上班日、开关、弹性模式、当天未到岗和 `latestText` 终点检查。

- [ ] **Step 4: 运行并确认通过**

Run: `./Tests/run.sh`

Expected: 新增四项与全部既有断言均为 ✅。

### Task 2: 实现休息中与 05:00 会话切换

**Files:**
- Modify: `Sources/下班啦/WorkTimerModel.swift:176-425`
- Modify: `Sources/下班啦/ActivityStore.swift:147-193`
- Modify: `Tests/ActivityStoreTests.swift`
- Modify: `Tests/AutoStartTests.swift`

**Interfaces:**
- `WorkTimerModel.isResting: Bool`：下班后会话封存至下一个有效工作日开始前为真。
- `WorkTimerModel.prepareWorkdayTransition(at:)`：05:00 前封存旧会话，之后才清除旧状态。
- `ActivityStore.recordOfficePresenceEnd(workday:at:)` 继续保持首次结束不可覆盖。

- [ ] **Step 1: 写失败测试**

```swift
check("加班跨 05:00 前一天会话截止", WorkTimerModel.presenceBoundary(
    previousStart: d(2026, 11, 12, 10, 0), at: d(2026, 11, 13, 5, 0)), d(2026, 11, 13, 5, 0))
check("下班后封存进入休息中", WorkTimerModel.restingAfterPresenceEnds(true), true)
check("锁屏后 05:00 不自动开始", WorkTimerModel.canCarryRestingUnlockAcrossBoundary(
    unlockConfirmed: true, screenAsleep: true, locked: false), false)
```

- [ ] **Step 2: 运行并确认失败**

Run: `./Tests/run.sh`

Expected: 新增纯函数不存在而失败。

- [ ] **Step 3: 最小实现状态机**

在睡眠、熄屏或正常退出封存成功后设 `isResting = true`；锁屏或睡眠撤销“已解锁到 05:00”的携带资格。`tick` 发现工作日变化时必须先用旧 `workdayKey` 和旧 `endTime` 封存仍在加班的旧会话到 05:00，再清空当日倒计时状态。

若 `isResting` 且已确认解锁、屏幕亮、会话未锁，到 05:00 时以 05:00 写入新会话并按自动开始规则开始倒计时；否则进入新工作日待开始。

- [ ] **Step 4: 运行并确认通过**

Run: `./Tests/run.sh`

Expected: 所有新增 05:00、休息、封存与重复写入断言为 ✅。

### Task 3: 展示休息中并按工作日实时统计

**Files:**
- Modify: `Sources/下班啦/CountdownCardView.swift:76-252`
- Modify: `Sources/下班啦/ScreenTimeView.swift:88-110`
- Modify: `Sources/下班啦/ScreenTimeSupport.swift:13-28`
- Modify: `Tests/ActivityStoreTests.swift`

**Interfaces:**
- 主卡片和菜单栏在 `model.isResting` 时显示“休息中”，没有倒欠数字或进度条。
- `ScreenTimeView` 以 `workdayKey == WorkTimerModel.workdayKey(for: model.now)` 判断实时工作日，而非 `Calendar.isDateInToday`。

- [ ] **Step 1: 写失败测试**

```swift
check("工作日相同的凌晨会话持续增长", ScreenTimeDuration.seconds(for: openPresence,
      plannedSeconds: 9 * 3600, now: d(2026, 11, 13, 4, 30), isCurrentWorkday: true), 19 * 3600 + 30 * 60)
```

- [ ] **Step 2: 运行并确认失败**

Run: `./Tests/run.sh`

Expected: `isCurrentWorkday` 参数尚不存在而失败。

- [ ] **Step 3: 最小实现**

```swift
enum ScreenTimeDuration {
    static func seconds(for presence: OfficePresenceSession?, plannedSeconds: TimeInterval,
                        now: Date, isCurrentWorkday: Bool, fallbackStartedAt: Date? = nil) -> TimeInterval
}
```

休息中返回固定的已封存会话；主卡片使用灰色时钟图标与“休息中”，数字显示 `--:--:--`，不显示开始上班按钮直到新工作日。

- [ ] **Step 4: 完整验证并重启**

Run: `./Tests/run.sh && ./build.sh && pkill -x 下班啦 || true; open build/下班啦.app`

Expected: 所有断言通过，构建输出“构建完成”，应用以最新包重启。

### Task 4: 更新项目交接信息，不提交

**Files:**
- Modify: `README.md`
- Modify: `docs/project-context/CURRENT.md`
- Modify: `docs/project-context/BACKLOG.md`

- [ ] **Step 1: 写入准确规则**

记录 05:00 工作日、05:00–上班区间结束的自动开始窗口、休息中与跨 05:00 封存规则，并把凌晨边界真机验收项更新为 05:00。

- [ ] **Step 2: 核对工作区**

Run: `git diff --check && git status --short`

Expected: 无空白错误；保留未提交改动。
