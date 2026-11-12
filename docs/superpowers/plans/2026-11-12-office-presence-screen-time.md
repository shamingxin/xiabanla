# 实际在公司工作时长 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让屏幕时间以有效登录/解锁到下班后首次离开电脑的真实跨度统计当天与未来工作日。

**Architecture:** 扩展 SQLite 的 `work_sessions`，把“倒计时到岗”与“在岗电脑会话”分开保存。`WorkTimerModel` 在既有有效解锁路径记录实际在岗起点，并在睡眠、熄屏或应用退出的路径中，只有越过计划下班后才封存结束时刻；`ScreenTimeView` 优先读取该跨度，旧记录继续回退计划时长。

**Tech Stack:** Swift 5、SwiftUI、AppKit/NSWorkspace 通知、SQLite3、现有 `swiftc` 断言测试脚本。

## Global Constraints

- 保持 macOS 13+ 与 Command Line Tools 构建；不得引入依赖。
- 仅记录本次功能上线后的数据，不猜测、修改或补写旧记录。
- 开始必须使用既有自动计时的解锁证据与时间/工作日资格；手动到岗和到工位缓冲不能改写该时刻。
- 结束仅允许发生于计划下班后第一次关机、熄屏或系统睡眠；已封存记录不可覆盖。
- 不提交代码，除非用户另行明确要求。

---

### Task 1: 为在岗会话建立可迁移的存储接口

**Files:**
- Modify: `Sources/下班啦/ActivityStore.swift`
- Modify: `Tests/ActivityStoreTests.swift`
- Modify: `Tests/run.sh`

**Interfaces:**
- Produces `OfficePresenceSession(workday: String, startedAt: Date, endedAt: Date?)`。
- Produces `ActivityStore.recordOfficePresenceStart(workday:at:)`、`recordOfficePresenceEnd(workday:at:)` 与 `officePresenceSession(workday:)`。

- [ ] **Step 1: 写出失败的 SQLite 存储测试**

```swift
store.recordOfficePresenceStart(workday: "2026-11-10", at: date(10, 9))
store.recordOfficePresenceEnd(workday: "2026-11-10", at: date(10, 20, 58))
let presence = store.officePresenceSession(workday: "2026-11-10")
check("保存实际在岗起点", presence?.startedAt, date(10, 9))
check("保存实际在岗终点", presence?.endedAt, date(10, 20, 58))
store.recordOfficePresenceEnd(workday: "2026-11-10", at: date(10, 22))
check("首次离开后不覆盖结束", store.officePresenceSession(workday: "2026-11-10")?.endedAt, date(10, 20, 58))
```

- [ ] **Step 2: 运行测试确认失败**

Run: `./Tests/run.sh`

Expected: `ActivityStoreTests.swift` 因 `recordOfficePresenceStart`、`recordOfficePresenceEnd` 和 `officePresenceSession` 不存在而编译失败。

- [ ] **Step 3: 最小化实现 SQLite 迁移和 API**

```swift
execute("ALTER TABLE work_sessions ADD COLUMN presence_started_at REAL")
execute("ALTER TABLE work_sessions ADD COLUMN presence_ended_at REAL")

func recordOfficePresenceStart(workday: String, at date: Date) {
    // 仅填空的 presence_started_at；不改变现有 started_at/planned_seconds。
}

func recordOfficePresenceEnd(workday: String, at date: Date) {
    // 仅当 presence_started_at 非空且 presence_ended_at 为空时写入。
}
```

`ALTER TABLE` 的重复列错误须被现有静默 `execute` 吸收，使新旧数据库都能打开；`officePresenceSession` 读取两个新字段并在起点为空时返回 `nil`。

- [ ] **Step 4: 运行测试确认通过**

Run: `./Tests/run.sh`

Expected: 活动存储段输出新增三项 ✅，其余测试保持通过。

- [ ] **Step 5: 保持改动未提交**

Run: `git status --short`

Expected: 仅显示当前未提交功能、设计与计划文档改动；不要运行 `git commit`。

### Task 2: 在有效解锁和离开电脑事件中封存会话

**Files:**
- Modify: `Sources/下班啦/WorkTimerModel.swift`
- Modify: `Tests/AutoStartTests.swift`
- Modify: `Tests/run.sh`

**Interfaces:**
- Consumes Task 1 的 `ActivityStore` 在岗会话 API。
- Produces `WorkTimerModel.recordOfficePresenceStartIfEligible(at:)` 与 `recordOfficePresenceEndIfEligible(at:)`（内部方法）。
- Produces纯函数 `WorkTimerModel.shouldEndOfficePresence(at:plannedEnd:) -> Bool`，便于断言下班前/后分支。

- [ ] **Step 1: 写出失败的资格与结束判定测试**

```swift
check("下班前熄屏不结束在岗记录",
      WorkTimerModel.shouldEndOfficePresence(at: date(14, 19, 20), plannedEnd: date(14, 19, 21)), false)
check("下班后熄屏结束在岗记录",
      WorkTimerModel.shouldEndOfficePresence(at: date(14, 20, 58), plannedEnd: date(14, 19, 21)), true)
```

另为 `ActivityStore` 临时数据库创建 `WorkTimerModel`，调用有效解锁处理并断言：在自动开始允许的工作日/时间创建 `presence_started_at`，而 `autoStartArrival(...bufferEnabled: true...)` 不影响该存储值。

- [ ] **Step 2: 运行测试确认失败**

Run: `./Tests/run.sh`

Expected: 因 `shouldEndOfficePresence` 缺失而失败。

- [ ] **Step 3: 最小化实现事件状态机**

```swift
static func shouldEndOfficePresence(at date: Date, plannedEnd: Date?) -> Bool {
    guard let plannedEnd else { return false }
    return date >= plannedEnd
}
```

在 `checkAutoStart(_:)` 成功通过既有自动计时门控、消耗当日检查机会并满足 `shouldAutoStart` 后，先以未回拨的 `date` 写 `recordOfficePresenceStart`，再调用 `setStartTime`；因此必须开启自动计时并为弹性模式，且到工位缓冲不能污染真实起点。

在 `willSleep`、`screensDidSleep` 的 observer 以及应用终止入口调用结束方法；该方法只在 `shouldEndOfficePresence` 返回 `true` 时写入。结束 API 的“只写一次”语义负责重复通知去重。

- [ ] **Step 4: 运行测试确认通过**

Run: `./Tests/run.sh`

Expected: 新增“下班前不结束”“下班后结束”“真实解锁起点不受缓冲影响”均为 ✅，原 40 项自动计时测试均保持通过。

- [ ] **Step 5: 保持改动未提交**

Run: `git diff --check && git status --short`

Expected: 无空白错误；不要运行 `git commit`。

### Task 3: 让屏幕时间优先使用真实会话

**Files:**
- Modify: `Sources/下班啦/ScreenTimeView.swift`
- Modify: `Tests/ActivityStoreTests.swift`

**Interfaces:**
- Consumes `OfficePresenceSession`。
- `ScreenTimeView.workSeconds(on:)` 对已结束会话返回 `endedAt.timeIntervalSince(startedAt)`；对当天未结束会话返回 `Date().timeIntervalSince(startedAt)`；只对无真实会话的旧记录回退 `plannedSeconds`。

- [ ] **Step 1: 写出失败的会话时长测试**

```swift
let actualSeconds = presence!.endedAt!.timeIntervalSince(presence!.startedAt)
check("实际在岗时间不再封顶计划时长", actualSeconds, 11 * 3600 + 58 * 60)
```

测试使用 09:00 到 20:58，明确证明 11 小时 58 分钟不会被回退成 9 小时。

- [ ] **Step 2: 运行测试确认失败或缺少预期展示路径**

Run: `./Tests/run.sh`

Expected: 在 Task 1 未实施前失败；实施后该测试通过，再继续为 UI 查询接入真实会话。

- [ ] **Step 3: 实现优先级明确的查询分支**

```swift
if let presence = activity.officePresenceSession(workday: key) {
    let end = presence.endedAt ?? (calendar.isDateInToday(day) ? Date() : nil)
    if let end { return max(0, end.timeIntervalSince(presence.startedAt)) }
}
return session.plannedSeconds
```

保留未来日期返回零；当前自然日仍从 `model.now` 或 `Date()` 刷新，以便 SwiftUI 重绘。

- [ ] **Step 4: 运行完整验证并重新构建启动**

Run: `./Tests/run.sh && ./build.sh && pkill -x 下班啦 || true; open build/下班啦.app`

Expected: 全部断言通过，构建输出“构建完成”，应用重新启动。

- [ ] **Step 5: 更新交接状态但不提交**

Modify: `docs/project-context/CURRENT.md`, `docs/project-context/BACKLOG.md`

记录新行为与尚待真实验收的“下班后熄屏封存”场景；保留未提交状态，等待用户体验确认。

### Task 4: 默认打开本周视图

**Files:**
- Modify: `Sources/下班啦/ScreenTimeView.swift`
- Modify: `Tests/ActivityStoreTests.swift`

**Interfaces:**
- `ScreenTimeState.period` 的初始值为 `.week`，日期控件保留对 `.day` 的显式切换能力。

- [ ] **Step 1: 写出失败的默认状态测试**

```swift
let screenTimeState = ScreenTimeState()
check("屏幕时间默认显示本周", screenTimeState.period, .week)
```

- [ ] **Step 2: 运行测试确认失败**

Run: `./Tests/run.sh`

Expected: 断言失败，现有初始值为 `.day`。

- [ ] **Step 3: 最小化实现**

```swift
final class ScreenTimeState: ObservableObject {
    @Published var period: ScreenTimeView.Period = .week
    @Published var selectedDate = Date()
}
```

- [ ] **Step 4: 运行最终验证与构建**

Run: `./Tests/run.sh && ./build.sh && pkill -x 下班啦 || true; open build/下班啦.app`

Expected: 新增默认状态断言为 ✅，完整测试和构建通过，应用重启。
