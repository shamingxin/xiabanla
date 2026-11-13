# 在岗时间文案 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the in-app actual-presence reporting experience from “屏幕时间” to “在岗时间” without changing calculation behavior.

**Architecture:** Keep Swift type names unchanged to avoid needless refactoring; update only user-visible copy, accessibility labels, and product documentation.

**Tech Stack:** SwiftUI, shell test runner, Markdown.

## Global Constraints

- “在岗时间” means company-computer presence segments; “工作时长” remains the configured daily plan.
- No changes to persistence, timing rules, or tests that assert timing behavior.
- Do not commit without explicit user authorization.

---

### Task 1: Replace presentation copy and documentation

**Files:**
- Modify: `Sources/下班啦/SettingsView.swift`
- Modify: `Sources/下班啦/ScreenTimeView.swift`
- Modify: `Sources/下班啦/HappinessIndexView.swift`
- Modify: `README.md`
- Modify: `docs/project-context/CURRENT.md`

- [ ] **Step 1: Replace the sidebar/page title and all chart copy** according to `2026-11-13-presence-time-copy-design.md`.
- [ ] **Step 2: Preserve “工作时长” only for the planned-hours setting** and change accessibility labels to “在岗时间”.
- [ ] **Step 3: Build and run tests** with `./Tests/run.sh && ./build.sh`; inspect the restarted settings page to confirm the sidebar, header, total card, chart, and happiness action use the new term.
