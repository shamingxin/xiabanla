# 下班啦 · Agent 规则

macOS 菜单栏下班倒计时 App（SwiftUI + AppKit），功能说明见 README.md。

## 运行

- 构建：`./build.sh` → `build/下班啦.app`；改完代码必须重新构建，并 `pkill -x 下班啦 && open build/下班啦.app` 重启，否则用户看到的是旧进程
- 没有 Xcode，只有 Command Line Tools：不能用 `#Preview`；build.sh 用 vfsoverlay 屏蔽 CLT 里重复的 module.modulemap
- 没有屏幕录制权限：界面效果靠用户截图；需要自查时写临时 main.swift，用 `NSHostingView.cacheDisplay` 离屏渲染取像素，用完删除
- `osascript` 被禁用；本机 Python 的 PIL 架构不匹配，读 PNG 像素用纯 Python zlib 解码

## 目录

- `Sources/下班啦/`：WorkTimerModel（工时规则、倒欠计时、深浅模式、主题色 AccentPreset、倒计时样式 CountdownStyle）、ReminderModel（提醒调度）、BubbleController（思考泡）、CountdownCardView（卡片 + CardPalette + 翻页/灵动岛两种数字样式）、WidgetContainer（背景渲染，图片背景已下线、注释保留）、SettingsView（侧边栏两栏设置面板 + SettingsPalette + themeAccent 环境值 + 自绘强调色开关）、TodayPanel（「今日工作」点阵屏面板 + TodayPalette + 逐位时间输入）、AppDelegate
- `Assets/Videos/{喝水,彩蛋,下班}/`：内置视频，必须 640×640
- `docs/project-context/`：跨对话任务接力（CURRENT.md / BACKLOG.md），新对话先读 CURRENT.md 再核对 git

## 约定

- 设置窗口固定两栏布局 678×560（侧边栏浮起面板内缩 8 + 宽 190，右内容区 480 宽，尺寸常量在 `SettingsMetrics`），不要改成随内容自适应（会布局循环闪退）；窗口 fullSizeContentView + 空 unified 工具栏，红黄绿按钮落在侧边栏面板内，右侧顶部 15pt 半粗标题和按钮同一行
- 设置面板分五个侧边栏分区：「工作时长」（今日工作+上班规则，默认选中）、「提醒动画」（喝水/彩蛋/下班提醒）、「通用」（登录项）、「外观」（深浅模式 + 主题色一张卡片；下方「倒计时样式」独立成组，墙纸式 3 列预览网格 `CountdownStylePreview`，新增样式加枚举项 + 补预览画法即可）、「关于」（直接在内容区显示，不弹窗）；侧边栏每项是彩色圆角方块图标（分类色固定），选中态主题色实底，文字黑/白按底色亮度自动取（`Color.contrastingText`）
- 配色走环境值：卡片用 `\.cardPalette`，设置面板用 `\.settingsPalette`，强调色用 `\.themeAccent`（在 SettingsView 根部由 `model.accentColor` 注入），不要写死 `Color.white` 或写死十六进制强调色
- UserDefaults key 改名要兼容老用户（如 `defaultStartTime` 沿用）
- **产品文案（2026-11 改版后）**：原「主题色」（黑/白/图片背景）现在叫「深浅模式」，只剩「浅色」「深色」两态，样式是系统设置「外观」同款窗口缩略图（`AppearanceThumbnail`）+ 下方文字，选中态主题色描边，上传图片功能已下线（代码保留注释，未删除，见 `WidgetContainer.customImage`）；新增「主题色」控制开关/数字等强调色（5 预设：荧光绿 #39FF14、莱茵蓝 #0057FF、黄 #FED501、粉 #FF6B9D、红 #FF3B30 + 自定义 hex 输入）；新增「倒计时样式」控制主卡片数字呈现（翻页 `flip` 现状 / 灵动岛 `dynamicIsland` 粗体数字+spring 果冻动画），只影响 CountdownCardView，不影响「今日工作」点阵面板
- 设置窗口是透明窗口 + SwiftUI 自绘 28pt 圆角和背景模糊（15.x SDK 在 macOS 26 只给小圆角）；`.ignoresSafeArea()` 必须在 SettingsView 修饰链最外层，放里层会裁掉顶部、红黄绿按钮露到窗外
- 设置配色三层半透明：侧边栏最透（`sidebarTintOpacity`）、内容区较实（`windowTintOpacity`）、卡片只叠极淡白/黑，不要改回不透明色块
- 倒计时样式切换时卡片整体宽度必须保持一致（灵动岛的数字宽度、分隔符宽度要对齐翻页样式的 `Metrics.tileSize`/`tileGap`），不要让切换样式时卡片跳动
- 只在用户明确同意后提交；只暂存 Sources/、Assets/、build.sh、.gitignore 和文档，推送 main；.project-handoff.json、release/ 已被忽略不提交
- 发版前改 build.sh 里的 CFBundleShortVersionString / CFBundleVersion；安装包打到 `release/下班啦-vX.Y.zip`，只保留最新版

## 当前状态

v1.4 已发布（2026-11-06，commit 8cda64c，tag v1.4，GitHub Release 已上传）。后续待办见 docs/project-context/BACKLOG.md。
