# 幸福指数收藏卡 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变周度幸福指数计算的前提下，将结果卡呈现为带顶部视频封面、星级、评分和短评的收藏卡。

**Architecture:** 星级映射是 `HappinessIndexView.swift` 内的纯展示辅助函数，唯一输入为既有 0–100 分数。`HappinessResultCard` 复用现有静音视频播放器作为封面，并在分数与统计之间新增该映射的星级行。

**Tech Stack:** SwiftUI、AppKit、现有 `HappinessScore`、`HappinessVideoView`、纯 Swift 呈现测试、`build.sh`。

## Global Constraints

- 不修改 `HappinessScore`、数据库 schema、工时数据或版本号。
- 星级使用现有整数分数映射到 0–5 星的半星增量，且不影响分数。
- 测试版复用内置「幸福指数」视频，不使用用户参考图作为应用素材。
- 无数据态不显示星级或虚构结果；重测和跳转行为保持不变。
- 不新增依赖，不提交、不发布。

---

### Task 1: 锁定评分到星级的展示规则

**Files:**
- Modify: `Tests/HappinessResultPresentationTests.swift`
- Modify: `Sources/下班啦/HappinessIndexView.swift`

**Interfaces:**
- Produces: `starRating(for score: Int) -> Double`，输出限制在 `0...5` 且以 `0.5` 为步长。
- Consumes: `HappinessScore.WeeklySummary.score`。

- [ ] **Step 1: 写入失败的映射测试**

在 `Tests/HappinessResultPresentationTests.swift` 新增源码断言，要求源文件定义 `starRating(for score: Int)` 并包含 `rounded() / 2`，表示半星量化。

- [ ] **Step 2: 运行测试，确认它因缺少映射而失败**

Run: `./Tests/run.sh`

Expected: `❌ 结果卡按半星展示评分`，退出码为 1。

- [ ] **Step 3: 写入最小实现**

在 `HappinessIndexView.swift` 增加：

```swift
private func starRating(for score: Int) -> Double {
    (min(100, max(0, Double(score))) / 20 * 2).rounded() / 2
}
```

- [ ] **Step 4: 运行测试，确认映射存在且既有呈现断言通过**

Run: `./Tests/run.sh`

Expected: 退出码 0，输出 `全部通过`。

### Task 2: 组装结果收藏卡

**Files:**
- Modify: `Sources/下班啦/HappinessIndexView.swift`
- Modify: `Tests/HappinessResultPresentationTests.swift`

**Interfaces:**
- Consumes: `HappinessVideoView`、`starRating(for:)`、`HappinessScore.WeeklySummary`。
- Produces: 有分数卡片的“视频封面 → 星级 → 分数和称号 → 短评 → 统计”顺序。

- [ ] **Step 1: 写入失败的结构测试**

在呈现测试添加源码断言，要求结果卡包含 `HappinessVideoView()`、本地 `SketchStar` 和 `starRating(for: score)`，以确保封面、手绘星级和既有分数输入连接。

- [ ] **Step 2: 运行测试，确认新结构断言失败**

Run: `./Tests/run.sh`

Expected: `❌ 结果卡包含视频封面与星级评分`，退出码为 1。

- [ ] **Step 3: 实现最小布局**

在 `HappinessResultCard` 的有分数分支顶部放置 156pt 高的 `HappinessVideoView()`，连续圆角裁切；其下用五个本地 `SketchStar` 按 `starRating(for: score)` 显示暖黄色半填充、紫色描边的不规则手绘星形；随后保留分数、称号、短评和统计。星级为次要强调，不取代数字分数，也不复用参考图素材。

- [ ] **Step 4: 运行完整回归与构建**

Run: `./Tests/run.sh && ./build.sh`

Expected: 全部断言输出 `全部通过`，构建输出 `构建完成`。

- [ ] **Step 5: 启动本地测试 App**

Run: `pkill -x 下班啦 || true; open build/下班啦.app`

Expected: 新构建的 App 启动；用户可在设置的「幸福指数」页查看测试版。
