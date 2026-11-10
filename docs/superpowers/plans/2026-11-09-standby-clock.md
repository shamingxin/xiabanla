# 待机时钟倒计时样式 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为下班啦新增保持固定卡片宽度、支持秒级平滑更新的「待机时钟」倒计时样式。

**Architecture:** 在现有 `CountdownStyle` 枚举中加入持久化 case；主卡片用独立的 `StandbyDigitGroup` 承担两层数字的显示状态与动画生命周期。设置页继续由枚举驱动，并新增静态预览分支。

**Tech Stack:** Swift 5、SwiftUI、AppKit、现有 shell 测试脚本。

## Global Constraints

- 最低系统为 macOS 13，不能依赖较新的 SwiftUI 动画 API。
- 只影响主卡片，不影响「今日工作」面板、工时计算与提醒逻辑。
- 三种样式的数字区总宽度必须保持一致。
- 新样式没有 spring 缩放或排队的延迟回调；快速更新时不得显示过期数字。
- 主题色不支配待机时钟的蓝色层；已下班态仍使用现有绿色。

---

### Task 1: 持久化样式枚举

**Files:**
- Modify: `Sources/下班啦/WorkTimerModel.swift:41-47`
- Modify: `Tests/AutoStartTests.swift`

**Interfaces:**
- Produces: `CountdownStyle.standbyClock`，raw value 为 `"待机时钟"`。
- Consumes: `WorkTimerModel` 现有的 `countdownStyle` 默认和 `UserDefaults` 恢复逻辑。

- [ ] **Step 1: 写失败测试**

在 `Tests/AutoStartTests.swift` 的顶层断言区加入：

```swift
check("待机时钟样式可选", CountdownStyle.allCases.contains(.standbyClock), true)
check("待机时钟持久化值", CountdownStyle.standbyClock.rawValue == "待机时钟", true)
```

- [ ] **Step 2: 运行测试并确认失败**

运行：`./Tests/run.sh`

预期：编译失败，提示 `CountdownStyle` 没有成员 `standbyClock`。

- [ ] **Step 3: 最小实现**

在 `CountdownStyle` 中加入：

```swift
case standbyClock = "待机时钟"
```

并更新枚举注释，明确现有 dynamicIsland 保持兼容。

- [ ] **Step 4: 运行测试并确认通过**

运行：`./Tests/run.sh`

预期：包括两项新增断言在内的全部测试通过。

### Task 2: 实现待机时钟数字过渡

**Files:**
- Modify: `Sources/下班啦/CountdownCardView.swift:94-111, 137-147, 483-518`

**Interfaces:**
- Consumes: `value: String`（两位数字）、`color: Color`、`label: String`、`Metrics.tileSize`。
- Produces: `StandbyDigitGroup` 和 `StandbyColonSeparator`，每一组固定占用 `Metrics.tileSize × Metrics.tileSize`，每个冒号固定占用 `Metrics.tileGap × Metrics.tileSize`。

- [ ] **Step 1: 建立人工失败验收**

在构建前记录当前 `dynamicIsland` 行为：其数字缩放并向上弹起，不符合待机时钟规格。此步骤的验收标准是新 case 在 `switch` 中尚未出现，无法被选择或展示。

- [ ] **Step 2: 添加新样式分支与固定布局**

在 `CountdownCardView` 的样式 `switch` 中添加：

```swift
case .standbyClock:
    HStack(spacing: 0) {
        StandbyDigitGroup(value: parts.0, color: digitColor, label: "小时")
        StandbyColonSeparator(color: digitColor)
        StandbyDigitGroup(value: parts.1, color: digitColor, label: "分钟")
        StandbyColonSeparator(color: digitColor)
        StandbyDigitGroup(value: parts.2, color: digitColor, label: "秒")
    }
```

`StandbyDigitGroup` 用两个位置相同但着色、偏移不同的 `Text` 层绘制静态值。前景为浅蓝色阶、后景为深蓝色阶；`color` 为已下班绿色时两层基于该颜色生成较亮/较深透明色阶。两层均使用 `.rounded`、`.bold` 和 `.monospacedDigit()`，不画数字牌。

- [ ] **Step 3: 实现无队列的旧/新值过渡**

`StandbyDigitGroup` 内保存 `displayedValue`、`outgoingValue`、`progress` 和 `impactScale`。`onChange(of: value)` 时在禁用隐式动画的 transaction 中先将当前 `displayedValue` 赋给 `outgoingValue`，再更新 `displayedValue` 并重置 `progress`；以 `progress` 驱动旧组上移淡出、新组从下向上归位。数值更新后可用受守卫的短延迟触发一次高阻尼 spring 回位，产生压缩—回弹反馈；减少动态效果时不运行动画。

- [ ] **Step 4: 加入冒号组件**

实现 `StandbyColonSeparator(color:)`：两颗 10pt 圆点在 `Metrics.tileGap` 宽的固定 frame 内垂直排布。普通状态使用由白到灰的 `LinearGradient`；已下班时改用 `color` 的明暗色阶，避免白色冒号脱离绿色状态。

- [ ] **Step 5: 构建并人工检查**

运行：`./build.sh && pkill -x 下班啦 && open build/下班啦.app`

预期：构建成功。选择待机时钟后，数字区宽度与翻页相同；秒钟每次更新只移动秒组，且连续 10 秒无缩放回弹、闪白、过期数字回弹或卡片宽度跳动。

### Task 3: 将待机时钟接入设置预览

**Files:**
- Modify: `Sources/下班啦/SettingsView.swift:1248-1318`

**Interfaces:**
- Consumes: `CountdownStyle.standbyClock`、现有 `light` 与 `CardPalette`。
- Produces: 「外观」页可选的待机时钟缩略图。

- [ ] **Step 1: 建立人工失败验收**

先完成 Task 1 后构建，`ForEach(CountdownStyle.allCases)` 会显示第三个选项，但 `CountdownStylePreview.content` 的 switch 不穷尽，编译器会报错；该失败证明预览必须被接入。

- [ ] **Step 2: 加入静态预览分支**

在 `case .standbyClock` 中，用 `HStack(spacing: 0)` 画 `08:42:16`。每个两位组拆成深蓝十位、浅蓝个位的 `.rounded`、`.heavy`、`.monospacedDigit()` 文本，以负间距轻微交叠。两个冒号使用双圆点渐变，所有元素总宽度小于预览卡片可用宽度。

- [ ] **Step 3: 构建并人工检查**

运行：`./build.sh && pkill -x 下班啦 && open build/下班啦.app`

预期：外观页出现三个样式，待机时钟预览在深浅模式下均可读，选中描边仍跟随主题色。

### Task 4: 最终回归与文档同步

**Files:**
- Modify: `README.md`
- Modify: `docs/project-context/CURRENT.md`
- Modify: `docs/project-context/BACKLOG.md`（仅当新增未验证项）

**Interfaces:**
- Consumes: 完成的 `CountdownStyle.standbyClock`、构建产物与人工观察。
- Produces: 与当前代码及验证状态一致的项目文档。

- [ ] **Step 1: 更新 README 样式文案**

将外观条目的倒计时样式列为「翻页 / 灵动岛 / 待机时钟」，明确待机时钟是深蓝十位/浅蓝个位的秒级流动效果。

- [ ] **Step 2: 更新项目接力文档**

在 `CURRENT.md` 记录本次新增的第三种样式、构建与自动测试结果、尚待用户截图确认的视觉项；如有未确认项，新增到 `BACKLOG.md`。

- [ ] **Step 3: 跑完整验证**

运行：`./Tests/run.sh && ./build.sh`

预期：测试全部通过，构建输出 `build/下班啦.app`。

- [ ] **Step 4: 检查工作区**

运行：`git status --short`

预期：只包含本计划列出的源代码、测试和文档修改。按项目规则，未经用户明确同意，不创建提交。
