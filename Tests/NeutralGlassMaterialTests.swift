import Foundation

var failures = 0

func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    let passed = condition()
    print((passed ? "✅" : "❌") + " " + name)
    if !passed { failures += 1 }
}

func source(_ path: String) -> String {
    (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
}

let settings = source("Sources/下班啦/SettingsView.swift")
let widget = source("Sources/下班啦/WidgetContainer.swift")
let card = source("Sources/下班啦/CountdownCardView.swift")
let toolbar = source("Sources/下班啦/ScreenTimeToolbarInteractionOverlay.swift")
let screenTime = source("Sources/下班啦/ScreenTimeView.swift")
let happiness = source("Sources/下班啦/HappinessIndexView.swift")
let screenTimeView = source("Sources/下班啦/ScreenTimeView.swift")

check("设置交互跟随用户主题色", settings.contains(".environment(\\.themeAccent, model.accentColor)"))
check("设置继续使用窗口后背景模糊", settings.contains("SettingsBlurBackground") &&
      settings.contains("view.blendingMode = .behindWindow"))
check("设置采用可见的分层玻璃透明度", settings.contains("windowTintOpacity: 0.58") &&
      settings.contains("sidebarTintOpacity: 0.24") &&
      settings.contains("windowTintOpacity: 0.54") &&
      settings.contains("sidebarTintOpacity: 0.20"))
check("设置卡片不使用外轮廓描边", !settings.contains(".strokeBorder(palette.cardStroke, lineWidth: 0.8)"))
check("外观页提供主题色选择器", settings.contains("SettingsRow(\"主题色\")") &&
      settings.contains("AccentColorPicker(model: model)"))
check("倒计时继续使用视觉效果背景", widget.contains("VisualEffectBackground") &&
      widget.contains("view.blendingMode = .behindWindow"))
check("倒计时使用可见的中性玻璃底色", widget.contains("Color(red: 0.96, green: 0.955, blue: 0.94).opacity(0.42)") &&
      widget.contains("Color(red: 0.075, green: 0.082, blue: 0.095).opacity(0.44)"))
check("倒计时数字牌保留可见的半透明材质", card.contains("tile: Color.white.opacity(0.12)") &&
      card.contains("tile: Color.white.opacity(0.60)"))
check("提醒 Tab 使用双层玻璃胶囊", toolbar.contains("tabOuterStroke") &&
      toolbar.contains("tabInnerStroke") &&
      toolbar.contains("selectedStroke"))
check("提醒 Tab 的选中片有独立高光与投影", toolbar.contains("selectedStroke") &&
      toolbar.contains("selectedShadow"))
check("设置页统一使用卡片组间距 token", settings.contains("static let sectionSpacing: CGFloat = 16") &&
      settings.contains("VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing)") &&
      settings.contains("VStack(spacing: SettingsMetrics.sectionSpacing) {"))
check("在岗和幸福页面沿用统一组间距", screenTime.contains("spacing: SettingsMetrics.sectionSpacing") &&
      happiness.contains("spacing: SettingsMetrics.sectionSpacing"))
check("饮水卡按天周周期切换", screenTimeView.contains("period: period") &&
      screenTimeView.contains("weeklyWaterIntakeSummary") &&
      screenTimeView.contains("if period == .day"))
check("周饮水卡不提供快捷补记", screenTimeView.contains("showQuickAdd: period == .day"))
check("悬停反馈使用可见的前置材质层", settings.contains("var hoverSurface: Color") &&
      settings.contains("var hoverStroke: Color") &&
      settings.contains(".fill(isEnabled && hovering ? palette.hoverSurface : .clear)") &&
      settings.contains("hovering = isEnabled && $0") &&
      settings.contains("palette.hoverSurface"))
check("菜单容器回传悬停状态", settings.contains("private func setHovered(_ isHovered: Bool) {\n        hovered = isHovered\n        onHover?(isHovered)") &&
      !settings.contains("applyHoverAppearance"))
check("悬停覆盖层不拦截按钮点击", settings.contains("palette.hoverSurface : .clear)\n                    .allowsHitTesting(false)") &&
      settings.contains("palette.hoverStroke : .clear, lineWidth: 1)\n                    .allowsHitTesting(false)"))
check("下拉保留 SwiftUI 按下态", settings.contains(".fill(active ? palette.hoverSurface.opacity(pressed ? 1.28 : 1) : .clear)") &&
      settings.contains(".strokeBorder(hovering ? palette.hoverStroke : .clear, lineWidth: 1)") &&
      !settings.contains("applyHoverAppearance"))
check("时间控件把悬停状态回传给 SwiftUI", settings.contains("onHover: { hovering = $0 }") &&
      settings.contains("final class HoverDatePicker: NSDatePicker") &&
      !settings.contains("layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor"))
check("透明原生菜单在同层容器中绘制悬停", settings.contains("final class HoverPopUpControl: NSView") &&
      settings.contains("override func draw(_ dirtyRect: NSRect)") &&
      settings.contains("button.isTransparent = true") &&
      settings.contains("hovered ? hoverFill : .clear"))
check("菜单容器独立追踪鼠标并重绘", settings.contains("private func setHovered(_ isHovered: Bool)") &&
      settings.contains("HoverPopUpControl: NSView") &&
      settings.contains("needsDisplay = true"))

print(failures == 0 ? "全部通过" : "失败 \(failures) 项")
exit(failures == 0 ? 0 : 1)
