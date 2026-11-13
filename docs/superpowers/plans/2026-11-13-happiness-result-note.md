# 深色便签幸福结果卡 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将幸福指数结果页改为纯中文、深石墨便签卡，并提供更大的等宽胶囊操作按钮。

**Architecture:** 只调整 `HappinessIndexView.swift` 内的结果呈现层，不改变 `HappinessScore`、SQLite 读取、测量状态或页面跳转闭包。卡片保持固定深色身份；主题色只用于跳转到在岗时间的主按钮。

**Tech Stack:** SwiftUI、AppKit、现有 `SettingsPalette` / `themeAccent` 环境值、`build.sh`。

## Global Constraints

- 保持现有本周统计、人格文案随机化和 `reduceMotion` 行为不变。
- 结果卡不得出现英文、黄色/米黄色背景或高饱和状态色。
- 卡片仅展示本周幸福指数、分数、称号、参与天数、准时下班、加班时间和一句人格文案。
- 两个操作按钮必须 48pt 高、等宽、完整胶囊圆角；“查看本周在岗”保留主题色。
- 不改变数据库 schema、评分规则、视频播放器或设置侧边栏结构。

---

### Task 1: 重构结果卡与操作区

**Files:**
- Modify: `Sources/下班啦/HappinessIndexView.swift:99-240`
- Verify: `./build.sh`

**Interfaces:**
- Consumes: `HappinessScore.WeeklySummary`（`score`、`tier`、`days`、`onTimeDays`、`overtimeSeconds`）和 `HappinessPersona`。
- Produces: 保持 `HappinessResultCard(summary:persona:scheme:)` 的调用签名不变；`resultView` 继续调用 `reroll` 与 `showScreenTime`。

- [ ] **Step 1: 建立视觉验收基线**

  记录现状：卡片包含 `XIABANLA / WEEKLY REPORT`、`THIS WEEK`、黄褐色背景，且两个按钮为系统紧凑尺寸。验收目标为这些英文和黄褐色卡面均不再出现，按钮高度为 48pt。

- [ ] **Step 2: 改写结果操作区**

  在 `resultView` 使用等宽 `HStack`：两个按钮均以 `.buttonStyle(.plain)` 自绘圆角矩形背景，`frame(maxWidth: .infinity, minHeight: 48)`，整体宽度限制在 440pt。左按钮使用深灰半透明底与主文字色；右按钮使用 `accent`。

- [ ] **Step 3: 改写结果卡层级**

  从 `HappinessResultCard` 删除英文页眉，替换为中文标题、大号 `score` + 「分」、称号胶囊、三列统计和底部人格结语。卡片背景改为固定近黑石墨，描边为白色低透明度；保持 24pt 连续圆角和 24pt 内边距。无分数状态沿用同一卡片与纯中文空态文案。

- [ ] **Step 4: 编译验证**

  Run: `./build.sh`

  Expected: exit code 0，输出 `构建完成`。

- [ ] **Step 5: 离屏视觉验证**

  使用临时 `NSHostingView.cacheDisplay` 渲染有分数与空数据两种结果卡，确认：无英文、无黄褐色背景、三项数据在同一行、两个按钮等宽且高度 48pt。验证后删除临时文件。

- [ ] **Step 6: 回归验证**

  Run: `./Tests/run.sh && ./build.sh`

  Expected: 所有断言输出 `全部通过`，构建成功。

- [ ] **Step 7: Commit**

  ```bash
  git add Sources/下班啦/HappinessIndexView.swift docs/superpowers/plans/2026-11-13-happiness-result-note.md
  git commit -m "优化幸福指数结果卡"
  ```
