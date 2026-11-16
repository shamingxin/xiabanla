# 默认开机自动倒计时 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 v1.8.1 用户升级后的下一次启动及新安装的首次启动中，默认开启登录时打开和工作日自动计时，同时允许迁移后用户自行关闭。

**Architecture:** 在 `WorkTimerModel` 中增加一个以独立 UserDefaults 标记保护的一次性迁移函数。它在模型读取设置之前写入两项开关与默认工作日，并通过闭包隔离 macOS 登录项注册，使迁移副作用可用隔离的 UserDefaults 单元测试。初始化时将闭包连接到既有 `LoginItemManager`。

**Tech Stack:** Swift 5、SwiftUI、AppKit、ServiceManagement、UserDefaults、现有 `swiftc` 断言测试脚本。

## Global Constraints

- 保持 macOS 13+ 和 Command Line Tools 构建方式，不新增依赖。
- 不改变自动计时现有安全条件：弹性模式、所选上班日、05:00 至上班区间结束、当天尚未开始、有效登录或解锁证据。
- 迁移只执行一次；迁移后设置页中的开关和上班日仍由用户控制。
- 不提交，除非用户明确要求。

---

### Task 1: 为一次性默认迁移建立回归测试

**Files:**
- Modify: `Tests/AutoStartTests.swift`
- Test: `Tests/run.sh`

**Interfaces:**
- Consumes: `WorkTimerModel.applyAutomaticStartupDefaultMigration(defaults:registerLoginItem:) -> Bool`
- Produces: 覆盖首次迁移、已迁移后保留用户关闭状态和默认周一至周五的可执行断言。

- [ ] **Step 1: 在 `Tests/AutoStartTests.swift` 的“启动是否算开机登录”段落后写入失败测试**

```swift
print("— 默认开机自动倒计时迁移 —")
let migrationSuite = "xiabanla.migration.tests.\(UUID().uuidString)"
let migrationDefaults = UserDefaults(suiteName: migrationSuite)!
defer { migrationDefaults.removePersistentDomain(forName: migrationSuite) }
var registrations: [Bool] = []

check("首次启动迁移会执行", WorkTimerModel.applyAutomaticStartupDefaultMigration(
    defaults: migrationDefaults,
    registerLoginItem: { registrations.append($0) }), true)
check("首次启动默认登录时打开", migrationDefaults.bool(forKey: "launchAtLogin"), true)
check("首次启动默认自动计时", migrationDefaults.bool(forKey: "autoStartEnabled"), true)
check("首次启动默认周一至周五", Set(migrationDefaults.array(forKey: "autoStartWeekdays") as? [Int] ?? [])
    == WorkTimerModel.defaultAutoStartWeekdays, true)
check("首次迁移注册登录项", registrations == [true], true)

migrationDefaults.set(false, forKey: "launchAtLogin")
migrationDefaults.set(false, forKey: "autoStartEnabled")
check("已迁移后不覆盖用户关闭选择", WorkTimerModel.applyAutomaticStartupDefaultMigration(
    defaults: migrationDefaults,
    registerLoginItem: { registrations.append($0) }), false)
check("已迁移后登录时打开仍关闭", migrationDefaults.bool(forKey: "launchAtLogin"), false)
check("已迁移后自动计时仍关闭", migrationDefaults.bool(forKey: "autoStartEnabled"), false)
check("已迁移后不重复注册", registrations == [true], true)
```

- [ ] **Step 2: 运行测试，确认它因接口不存在而失败**

Run: `./Tests/run.sh`

Expected: 编译失败并提示 `WorkTimerModel` 没有 `applyAutomaticStartupDefaultMigration`。

- [ ] **Step 3: 不修改生产代码，确认失败原因只来自缺失接口**

Expected: 所有原有断言尚未执行；失败信息只指向新迁移函数。

### Task 2: 实现一次性迁移并接入模型初始化

**Files:**
- Modify: `Sources/下班啦/WorkTimerModel.swift:200-240`
- Test: `Tests/AutoStartTests.swift`

**Interfaces:**
- Produces: `static func applyAutomaticStartupDefaultMigration(defaults: UserDefaults, registerLoginItem: (Bool) -> Void) -> Bool`
- Consumes: `LoginItemManager.setEnabled(_:)` 和 `WorkTimerModel.defaultAutoStartWeekdays`。

- [ ] **Step 1: 在 `Keys` 中添加一次性迁移标记**

```swift
static let automaticStartupDefaultsMigrated = "automaticStartupDefaultsMigrated"
```

- [ ] **Step 2: 在 `WorkTimerModel` 中、`init` 之前添加可测试迁移函数**

```swift
@discardableResult
static func applyAutomaticStartupDefaultMigration(defaults: UserDefaults,
                                                  registerLoginItem: (Bool) -> Void) -> Bool {
    guard !defaults.bool(forKey: Keys.automaticStartupDefaultsMigrated) else { return false }
    defaults.set(true, forKey: Keys.launchAtLogin)
    defaults.set(true, forKey: Keys.autoStartEnabled)
    if defaults.array(forKey: Keys.autoStartWeekdays) == nil {
        defaults.set(defaultAutoStartWeekdays.sorted(), forKey: Keys.autoStartWeekdays)
    }
    defaults.set(true, forKey: Keys.automaticStartupDefaultsMigrated)
    registerLoginItem(true)
    return true
}
```

- [ ] **Step 3: 在 `init(activityStore:)` 读取 `launchAtLogin` 前调用迁移函数**

```swift
let defaults = UserDefaults.standard
Self.applyAutomaticStartupDefaultMigration(defaults: defaults,
                                           registerLoginItem: LoginItemManager.setEnabled)
self.workMode = WorkMode(rawValue: defaults.string(forKey: Keys.workMode) ?? "") ?? .flexible
```

保持其余属性从同一个 `defaults` 读取，确保第一次初始化可见迁移后的值。

- [ ] **Step 4: 运行完整自动测试，确认新旧断言通过**

Run: `./Tests/run.sh`

Expected: 输出所有测试通过，且“默认开机自动倒计时迁移”中的 9 条断言均为 `✅`。

- [ ] **Step 5: 检查变更范围**

Run: `git diff --check && git diff -- Sources/下班啦/WorkTimerModel.swift Tests/AutoStartTests.swift`

Expected: 无空白错误；仅包含一次性迁移实现与其测试。

### Task 3: 构建并验证实际 App 产物

**Files:**
- Modify: `docs/project-context/CURRENT.md`
- Test: `build.sh`, `Tests/run.sh`

**Interfaces:**
- Consumes: Task 2 的迁移函数。
- Produces: 可本机构建、签名校验过的 App；项目记录更新为默认自动启动策略。

- [ ] **Step 1: 更新 `docs/project-context/CURRENT.md` 的产品规则与验证状态**

在“已确认的产品规则”中加入：首次启动或升级后的一次性迁移默认开启「登录时打开」与「自动计时」，默认上班日为周一至周五；迁移后可手动关闭。

- [ ] **Step 2: 运行全量逻辑测试**

Run: `./Tests/run.sh`

Expected: exit code 0，输出“全部通过”。

- [ ] **Step 3: 重新构建 App**

Run: `./build.sh`

Expected: exit code 0，输出 `构建完成:` 及 `build/下班啦.app`。

- [ ] **Step 4: 验证构建产物签名结构**

Run: `codesign --verify --deep --strict build/下班啦.app`

Expected: exit code 0，无输出。

- [ ] **Step 5: 最终审阅工作区**

Run: `git status --short && git diff --check`

Expected: 只有计划、规格、源代码、测试和接力文档的预期变更；无空白错误。
