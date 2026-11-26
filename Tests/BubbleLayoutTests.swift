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
for (width, height) in [(1920.0, 1080.0), (1080, 1920), (640, 640), (4000, 100), (100, 4000)] {
    let layout = BubbleLayout(mediaSize: CGSize(width: width, height: height), hasActions: true)
    check("云朵固定为正方形 \(width)×\(height)", layout.cloudSize.width / layout.cloudSize.height, 1)
    check("云朵宽度固定", layout.cloudSize.width, BubbleMetrics.cloudWidth)
    check("云朵高度固定", layout.cloudSize.height, BubbleMetrics.cloudHeight)
    check("回应按钮保留可读宽度", layout.panelSize.width >= 223 ? 1 : 0, 1)
    check("按钮位于云朵下方", layout.panelSize.height - layout.cloudRect.maxY,
          BubbleMetrics.actionAreaHeight + BubbleMetrics.bottomMargin)
}
let invalid = BubbleLayout(mediaSize: .zero, hasActions: false)
check("无尺寸信息回退默认大小", invalid.cloudSize.width, 195)
print(failures == 0 ? "全部通过" : "失败 \(failures) 项")
exit(failures == 0 ? 0 : 1)
