# Neutral Glass Material Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply a neutral Apple-style glass material to the settings window and countdown card without changing interaction or timer behavior.

**Architecture:** Keep visual tokens local to the existing `SettingsPalette` and `CardPalette` types. Inject a fixed system-blue interaction color only at the settings root, while retaining the model's stored accent data untouched.

**Tech Stack:** SwiftUI, AppKit `NSVisualEffectView`, Command Line Tools Swift compiler.

## Global Constraints

- Do not change timer, reminder, navigation, accessibility, or persistence behavior.
- Do not reset, stash, checkout, stage, commit, or overwrite existing user changes.
- Keep the settings window's fixed width and 500–1000 pt height behavior.
- Use fixed system blue only for settings interaction states; no user-selected theme color in the affected settings visuals.

---

### Task 1: Add material regression checks

**Files:**
- Create: `Tests/NeutralGlassMaterialTests.swift`
- Modify: `Tests/run.sh`

**Interfaces:**
- Consumes: source text in `SettingsView.swift`, `WidgetContainer.swift`, and `CountdownCardView.swift`.
- Produces: static guards for the neutral palette, fixed settings blue, retained blur, and card material.

- [ ] **Step 1: Write the failing test**

Create checks that require `systemBlue`, `SettingsBlurBackground`, `VisualEffectBackground`, and explicit card/glass palette values.

- [ ] **Step 2: Run test to verify it fails**

Run: `swiftc Tests/NeutralGlassMaterialTests.swift -o /tmp/neutral-glass-tests && /tmp/neutral-glass-tests`

Expected: FAIL because fixed system-blue and the new neutral palette tokens do not yet exist.

- [ ] **Step 3: Add the test to the project runner**

Append the same compiler invocation pattern used by `HappinessResultPresentationTests.swift` to `Tests/run.sh`.

### Task 2: Apply neutral settings-window material

**Files:**
- Modify: `Sources/下班啦/SettingsView.swift`

**Interfaces:**
- Consumes: `SettingsPalette`, `SettingsBlurBackground`, and the existing `themeAccent` environment key.
- Produces: a `SettingsPalette` with warmer light and graphite-dark tint values, a `systemBlue` interaction color, and a settings root that injects it.

- [ ] **Step 1: Run the Task 1 test and confirm its fixed-blue assertion is red**

Run: `Tests/run.sh`

Expected: neutral-glass static assertions fail; unrelated tests remain green.

- [ ] **Step 2: Implement the smallest visual-token change**

Set `SettingsPalette.light` and `.dark` tint, card, divider, and border opacity values to the approved material levels. Add a fixed `systemBlue` color and inject it instead of `model.accentColor`. Remove the visible `AccentColorPicker` row while leaving all model state and helper code intact.

- [ ] **Step 3: Run the full test suite**

Run: `Tests/run.sh`

Expected: all tests pass.

### Task 3: Apply matching countdown-card material

**Files:**
- Modify: `Sources/下班啦/WidgetContainer.swift`
- Modify: `Sources/下班啦/CountdownCardView.swift`

**Interfaces:**
- Consumes: `CardPalette` and `VisualEffectBackground`.
- Produces: warmer light and graphite-dark card backing with restrained strokes, tiles, tracks, and hover fills.

- [ ] **Step 1: Run the Task 1 test and confirm its card-material assertion is red**

Run: `Tests/run.sh`

Expected: only the new card-material static assertion fails before the palette changes.

- [ ] **Step 2: Implement matching palette and backing changes**

Use the existing visual-effect background. Increase the light backing's translucency without pure white and tune dark backing to deep graphite; update `CardPalette` tile, track, and hover fills to preserve numeric contrast.

- [ ] **Step 3: Run visual safety checks**

Run: `Tests/run.sh && ./build.sh && codesign --verify --deep --strict build/下班啦.app && git diff --check`

Expected: all commands exit 0.
