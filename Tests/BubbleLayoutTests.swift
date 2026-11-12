import AppKit

var failures = 0
func check(_ name: String, _ actual: CGFloat, _ expected: CGFloat) {
    let passed = abs(actual - expected) < 0.001
    print((passed ? "✅" : "❌") + " " + name)
    if !passed { failures += 1 }
}

let tipY: CGFloat = 900
let originalPanelHeight = BubbleMetrics.trailHeight + BubbleMetrics.cloudHeight + BubbleMetrics.bottomMargin
check("加回应按钮不改变原浮层高度", BubbleMetrics.panelSize.height, originalPanelHeight)
print(failures == 0 ? "全部通过" : "失败 \(failures) 项")
exit(failures == 0 ? 0 : 1)
