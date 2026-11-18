import Foundation

var fails = 0

func check(_ name: String, _ got: Bool) {
    print((got ? "✅" : "❌") + " " + name)
    if !got { fails += 1 }
}

func video(_ name: String) -> URL {
    URL(fileURLWithPath: "/tmp/\(name)")
}

let available = [video("a.mp4"), video("b.mp4"), video("c.mp4")]

let defaultSelection = VideoSelectionState.selectedNames(saved: nil, available: available)
check("未存选择时默认全选", defaultSelection == ["a.mp4", "b.mp4", "c.mp4"])

let cleanedSelection = VideoSelectionState.selectedNames(saved: ["a.mp4", "removed.mp4"], available: available)
check("已删除视频会自动忽略", cleanedSelection == ["a.mp4"])

let lastSelection = VideoSelectionState.toggling(["a.mp4"], name: "a.mp4", available: available)
check("最后一个已选动画不可取消", lastSelection == ["a.mp4"])

let expandedSelection = VideoSelectionState.toggling(["a.mp4"], name: "b.mp4", available: available)
check("可选中新的动画", expandedSelection == ["a.mp4", "b.mp4"])

let filtered = VideoSelectionState.filtered(available, selected: ["b.mp4"])
check("随机池只保留已选动画", filtered.map(\.lastPathComponent) == ["b.mp4"])

var libraryExpansion = ReminderLibraryExpansionState()
check("喝水动画库默认收起", !libraryExpansion.isExpanded(.water))
check("彩蛋动画库默认收起", !libraryExpansion.isExpanded(.egg))
libraryExpansion.toggle(.water)
check("喝水动画库可以展开", libraryExpansion.isExpanded(.water))
check("展开喝水不影响彩蛋", !libraryExpansion.isExpanded(.egg))
libraryExpansion.toggle(.egg)
check("彩蛋动画库独立展开", libraryExpansion.isExpanded(.egg))
libraryExpansion.collapseAll()
check("离开页面后两个动画库均收起", !libraryExpansion.isExpanded(.water) && !libraryExpansion.isExpanded(.egg))

print(fails == 0 ? "全部通过" : "失败 \(fails) 项")
exit(fails == 0 ? 0 : 1)
