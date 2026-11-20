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

let offWorkSelected = VideoSelectionState.selectedNames(saved: ["b.mp4"], available: available)
check("下班动画可恢复已保存选择", offWorkSelected == ["b.mp4"])
check("下班动画最后一项不可取消",
      VideoSelectionState.toggling(["b.mp4"], name: "b.mp4", available: available) == ["b.mp4"])
check("下班随机池只保留已选动画",
      VideoSelectionState.filtered(available, selected: offWorkSelected).map(\.lastPathComponent) == ["b.mp4"])

check("饮水量只在喝水提醒和强制提醒都开启时启用",
      WaterTrackingState.isEnabled(waterEnabled: true, sticky: true))
check("关闭喝水提醒时不显示饮水量",
      !WaterTrackingState.isEnabled(waterEnabled: false, sticky: true))
check("关闭强制提醒时不显示饮水量",
      !WaterTrackingState.isEnabled(waterEnabled: true, sticky: false))

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

let settingsSource = try! String(contentsOfFile: "Sources/下班啦/SettingsView.swift", encoding: .utf8)
check("喝水提醒使用卡片上方标题", settingsSource.contains("SettingsHeader(\"喝水提醒\")"))
check("喝水提醒下有常规设置卡", settingsSource.contains("SettingsCard { waterRegularRows }"))
check("喝水提醒下有强制提醒卡", settingsSource.contains("SettingsCard { waterStickyRows }"))
check("强制提醒不再作为额外标题", !settingsSource.contains("SettingsSection(\"强制提醒\")"))
check("常规设置不再作为额外标题", !settingsSource.contains("SettingsSection(\"常规设置\")"))
check("强制提醒是第二张卡的首行", settingsSource.contains("SettingsRow(\"强制提醒\""))
check("提醒大模块使用更大间距", settingsSource.contains("VStack(alignment: .leading, spacing: 28)"))
check("喝水标题与两张卡使用紧凑间距", settingsSource.contains("VStack(spacing: 10) {"))
check("放松提醒使用卡片上方标题", settingsSource.contains("SettingsSection(\"放松提醒\")"))
check("下班提醒使用卡片上方标题", settingsSource.contains("SettingsSection(\"下班提醒\")"))
check("三张卡片内的开关行统一叫动画提醒",
      settingsSource.components(separatedBy: "SettingsRow(\"动画提醒\")").count == 4)
check("动画选择行仍叫播放动画", settingsSource.contains("Text(\"播放动画\")"))
check("动画已选数量读取当前主题色", settingsSource.contains("let accent = model.accentColor"))
check("下班提醒接入动画库", settingsSource.contains("animationLibrary(.offWork)"))
check("深色模块底色使用更浅的叠层", settingsSource.contains("card: Color.white.opacity(0.04)"))

let screenTimeSource = try! String(contentsOfFile: "Sources/下班啦/ScreenTimeView.swift", encoding: .utf8)
let appDelegateSource = try! String(contentsOfFile: "Sources/下班啦/AppDelegate.swift", encoding: .utf8)
check("在岗卡片不再叠加旧的深黑遮罩", !screenTimeSource.contains(".black.opacity(0.42)"))
check("在岗周图使用当前工作日标签", screenTimeSource.contains("labels: weekChartLabels"))
check("在岗页不再在内容区放日期工具栏", !screenTimeSource.contains("HStack {\n                Spacer()\n                ScreenTimeToolbar"))
check("在岗日期工具栏位于原生标题栏", appDelegateSource.contains("NSTitlebarAccessoryViewController"))

let expectedWaterVideos = ["喝咖啡.mp4", "喝水.mp4"]
let expectedRestVideos = ["伸懒腰.mp4", "偷瞄.mp4", "发呆.mp4", "吃吃吃吃.mp4", "吃我一肥皂.mp4", "休息-听歌.mp4", "呜呜呜.mp4", "哭哭.mp4", "啊？.mp4", "嘻嘻.mp4", "嘻嘻嘻.mp4", "困.mp4", "好累.mp4", "妈咪妈咪哄.mp4", "幻境.mp4", "开车.mp4", "彭扔.mp4", "想睡觉.mp4", "抠鼻子.mp4", "抽烟1.mp4", "抽烟2.mp4", "猫猫车.mp4", "玩电脑.mp4", "被子在控制我.mp4", "钱包没钱了.mp4"]
let fileManager = FileManager.default
check("喝水素材已导入", expectedWaterVideos.allSatisfy {
    fileManager.fileExists(atPath: "Assets/Videos/喝水/\($0)")
})
check("放松素材已导入", expectedRestVideos.allSatisfy {
    fileManager.fileExists(atPath: "Assets/Videos/彩蛋/\($0)")
})

print(fails == 0 ? "全部通过" : "失败 \(fails) 项")
exit(fails == 0 ? 0 : 1)
