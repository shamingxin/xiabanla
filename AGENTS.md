# 下班啦 · Agent 规则

macOS 菜单栏下班倒计时 App（SwiftUI + AppKit），功能说明见 README.md。

## 运行

- 构建：`./build.sh` → `build/下班啦.app`；改完代码必须重新构建，并 `pkill -x 下班啦 && open build/下班啦.app` 重启，否则用户看到的是旧进程
- 没有 Xcode，只有 Command Line Tools：不能用 `#Preview`；build.sh 用 vfsoverlay 屏蔽 CLT 里重复的 module.modulemap
- 没有屏幕录制权限：界面效果靠用户截图；需要自查时写临时 main.swift，用 `NSHostingView.cacheDisplay` 离屏渲染取像素，用完删除
- `osascript` 被禁用；本机 Python 的 PIL 架构不匹配，读 PNG 像素用纯 Python zlib 解码

## 目录

- `Sources/下班啦/`：WorkTimerModel（工时规则、倒欠计时、主题色）、ReminderModel（提醒调度）、BubbleController（思考泡）、CountdownCardView（卡片 + CardPalette）、WidgetContainer（背景渲染）、SettingsView（设置面板 + SettingsPalette + 自绘橙色开关）、TodayPanel（「今日工作」点阵屏面板 + TodayPalette + 逐位时间输入）、AppDelegate
- `Assets/Videos/{喝水,彩蛋,下班}/`：内置视频，必须 640×640
- `docs/project-context/`：跨对话任务接力（CURRENT.md / BACKLOG.md），新对话先读 CURRENT.md 再核对 git

## 约定

- 设置窗口固定 460×560，不要改成随内容自适应（会布局循环闪退）
- 配色走环境值：卡片用 `\.cardPalette`，设置面板用 `\.settingsPalette`，不要写死 `Color.white`
- UserDefaults key 改名要兼容老用户（如 `defaultStartTime` 沿用）
- 产品文案以用户定稿为准：设置里叫「主题色」，不叫「背景」
- 只在用户明确同意后提交；只暂存 Sources/、Assets/、build.sh、.gitignore 和文档，推送 main；.project-handoff.json、release/ 已被忽略不提交
- 发版前改 build.sh 里的 CFBundleShortVersionString / CFBundleVersion；安装包打到 `release/下班啦-vX.Y.zip`，只保留最新版

## 当前状态

v1.2 已发布（tag v1.2）；v1.3 已提交推送（tag v1.3），GitHub Release 待发布；Release 状态与后续事项见 docs/project-context/CURRENT.md、BACKLOG.md。
