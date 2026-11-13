import Foundation

var failures = 0

func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    let passed = condition()
    print((passed ? "✅" : "❌") + " " + name)
    if !passed { failures += 1 }
}

let viewPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/下班啦/HappinessIndexView.swift")
let source = (try? String(contentsOf: viewPath, encoding: .utf8)) ?? ""

check("结果卡保留中文指数标题", source.contains("Text(\"本周幸福指数\")"))
check("结果卡移除英文周报标题", !source.contains("XIABANLA") && !source.contains("WEEKLY REPORT") && !source.contains("THIS WEEK"))
check("结果操作使用 48pt 高度", source.contains("minHeight: 48"))
check("结果操作使用胶囊圆角", source.contains("Capsule()"))
check("再测一次重新进入测量流程", source.contains("runMeasurement(summary: summary, persona: nextPersona)"))
check("结果卡按半星展示评分", source.contains("starRating(for score: Int)") && source.contains("rounded() / 2"))
check("结果卡包含视频封面与星级评分", source.contains("HappinessVideoView()") && source.contains("SketchStar(") && source.contains("starRating(for: score)"))
check("星级采用手绘描边而非系统图标", source.contains("private struct SketchStar: Shape") && !source.contains("Image(systemName: starSymbol"))

print(failures == 0 ? "全部通过" : "失败 \(failures) 项")
exit(failures == 0 ? 0 : 1)
