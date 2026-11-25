# Happiness Result Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore clear hover and pressed feedback to the two happiness-result actions while keeping their actions intact.

**Architecture:** A file-private SwiftUI `ButtonStyle` owns the interaction state so both capsule buttons render consistently. The existing result view remains responsible for its two actions: rerunning the measurement and switching to the weekly presence page.

**Tech Stack:** SwiftUI, AppKit cursor API, shell-based source regression tests.

## Global Constraints

- Preserve both 48pt equal-width capsule buttons and the configured theme accent.
- Use the existing settings-page hover language: a subtle accent treatment, not a layout change.
- Keep actions accessible with their existing labels.

---

### Task 1: Restore result-action affordance

**Files:**
- Modify: `Sources/下班啦/HappinessIndexView.swift:97-118`
- Modify: `Tests/HappinessResultPresentationTests.swift:15-20`

**Interfaces:**
- Produces: `HappinessActionButtonStyle`, a file-private `ButtonStyle` that accepts an action kind and reads `configuration.isPressed`.
- Consumes: `themeAccent` from the SwiftUI environment and `NSCursor.pointingHand` from AppKit.

- [ ] **Step 1: Write the failing test**

```swift
check("结果操作提供悬停与按下反馈", source.contains("HappinessActionButtonStyle") && source.contains("configuration.isPressed") && source.contains(".onHover"))
check("结果操作使用自定义交互样式", source.components(separatedBy: ".buttonStyle(HappinessActionButtonStyle").count == 3)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./Tests/run.sh`

Expected: the two new result-action checks fail because the source still uses `.buttonStyle(.plain)`.

- [ ] **Step 3: Write the minimal implementation**

```swift
private struct HappinessActionButtonStyle: ButtonStyle {
    @Environment(\.themeAccent) private var accent
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Capsule().fill(accent.opacity(configuration.isPressed ? 0.82 : (hovering ? 0.92 : 1))))
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }
}
```

Apply the style to both existing buttons without changing either action closure.

- [ ] **Step 4: Run the test suite and build**

Run: `./Tests/run.sh && ./build.sh && codesign --verify --deep --strict build/下班啦.app`

Expected: all tests, build, and signature verification exit successfully.
