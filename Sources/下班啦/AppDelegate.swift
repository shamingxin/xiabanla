import AppKit
import SwiftUI
import Combine

@main
enum XiabanlaMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

/// 管理菜单栏图标、菜单栏浮层、桌面小窗和设置窗口
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = WorkTimerModel()
    private lazy var reminders = ReminderModel(work: model)
    private let bubble = BubbleController()
    private var statusItem: NSStatusItem!
    private var popover: WidgetPanel?
    private var desktop: WidgetWindow?
    private var settingsWindow: NSWindow?
    /// 设置窗口代理：拖动时限制高度（NSWindow.delegate 是弱引用，这里强持有）
    private let settingsResizeDelegate = SettingsResizeDelegate()
    private var cancellables = Set<AnyCancellable>()
    private var monitors: [Any] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        buildMainMenu()
        setupStatusItem()
        showDesktopWindow()
        model.objectWillChange
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateStatusItem() } }
            .store(in: &cancellables)
        updateStatusItem()
        setupReminders()
    }

    // MARK: - 提醒气泡

    private func setupReminders() {
        bubble.anchorProvider = { [weak self] in self?.statusItemScreenFrame() }
        reminders.present = { [weak self] url, force, loop, onDismiss in
            self?.bubble.show(videoURL: url, loop: loop, force: force, onDismiss: onDismiss) ?? false
        }
        reminders.start()
    }

    /// 菜单栏图标在屏幕上的位置；图标被系统隐藏时返回 nil
    private func statusItemScreenFrame() -> NSRect? {
        guard let button = statusItem.button, let window = button.window,
              window.isVisible, window.occlusionState.contains(.visible) else { return nil }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        return frame.width > 0 ? frame : nil
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDesktopWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - 卡片

    private func actions(forDesktop: Bool) -> CardActions {
        CardActions(
            openSettings: { [weak self] in self?.openSettings() },
            showWindow: { [weak self] in self?.showDesktopWindow() },
            closeWindow: forDesktop ? { [weak self] in self?.desktop?.orderOut(nil) } : nil,
            minimizeWindow: forDesktop ? { [weak self] in self?.desktop?.miniaturize(nil) } : nil,
            quit: { NSApp.terminate(nil) }
        )
    }

    private func makeController(forDesktop: Bool) -> NSHostingController<WidgetContainer<CountdownCardView>> {
        let model = self.model
        let actions = self.actions(forDesktop: forDesktop)
        let controller = NSHostingController(rootView: WidgetContainer(model: model) {
            CountdownCardView(model: model, actions: actions)
        })
        controller.sizingOptions = [.preferredContentSize]
        return controller
    }

    private func install(_ controller: NSViewController, in window: NSWindow) {
        let size = controller.view.fittingSize
        window.contentViewController = controller
        window.setContentSize(size)
    }

    private func makePopover() -> WidgetPanel {
        let panel = WidgetPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        install(makeController(forDesktop: false), in: panel)
        return panel
    }

    // MARK: - 桌面小窗

    @objc private func showDesktopWindow() {
        if desktop == nil {
            let window = WidgetWindow(contentRect: .zero, styleMask: [.borderless, .miniaturizable],
                                      backing: .buffered, defer: false)
            install(makeController(forDesktop: true), in: window)
            window.title = "下班啦"
            window.isMovableByWindowBackground = true
            let size = window.frame.size
            if window.setFrameUsingName("DesktopWidget") {
                window.setContentSize(size)
            } else {
                window.center()
            }
            window.setFrameAutosaveName("DesktopWidget")
            desktop = window
        }
        NSApp.activate(ignoringOtherApps: true)
        if desktop?.isMiniaturized == true { desktop?.deminiaturize(nil) }
        desktop?.makeKeyAndOrderFront(nil)
        desktop?.invalidateShadow()
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            button.image = image
        } else {
            button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "下班啦")
        }
        button.imagePosition = .imageLeft
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func updateStatusItem() {
        statusItem.button?.title = " " + model.statusText
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            closePopover()
            let menu = NSMenu()
            menu.addItem(menuItem("设置…", #selector(openSettings)))
            menu.addItem(menuItem("显示桌面小窗", #selector(showDesktopWindow)))
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "退出下班啦", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
            return
        }
        if let panel = popover, panel.isVisible { closePopover() } else { openPopover() }
    }

    private func openPopover() {
        let panel = popover ?? makePopover()
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        popover = panel
        positionPopover(panel)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        addMonitors()
    }

    /// 浮层放在菜单栏图标正下方，不超出屏幕
    private func positionPopover(_ panel: NSWindow) {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size
        let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        var x = buttonFrame.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: buttonFrame.minY - 6 - size.height))
    }

    /// 点击浮层以外的地方时收起浮层
    private func addMonitors() {
        removeMonitors()
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.closePopover()
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            guard let self else { return event }
            if event.window !== self.popover && event.window !== self.statusItem.button?.window {
                self.closePopover()
            }
            return event
        }) { monitors.append(local) }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func closePopover() {
        popover?.orderOut(nil)
        removeMonitors()
    }

    // MARK: - 设置窗口

    /// 用户拖动后的设置窗口高度
    private static let settingsHeightKey = "settingsWindowHeight"

    @objc func openSettings() {
        closePopover()
        if settingsWindow == nil {
            // 窗口尺寸只由窗口决定：hosting view 不向窗口回报内容尺寸，避免窗口跟随 SwiftUI 内容变化造成布局循环崩溃
            let hosting = NSHostingView(rootView: SettingsView(model: model, reminders: reminders))
            hosting.sizingOptions = []
            let savedHeight = UserDefaults.standard.double(forKey: Self.settingsHeightKey)
            let height = savedHeight > 0
                ? min(max(CGFloat(savedHeight), SettingsMetrics.minWindowHeight), SettingsMetrics.maxWindowHeight)
                : SettingsMetrics.windowHeight
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0,
                                                      width: SettingsMetrics.windowWidth,
                                                      height: height),
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.contentView = hosting
            window.delegate = settingsResizeDelegate
            // 只允许上下拉高度：宽度锁死（「今日工作」面板按 480 内容宽设计）
            window.contentMinSize = NSSize(width: SettingsMetrics.windowWidth, height: SettingsMetrics.minWindowHeight)
            window.contentMaxSize = NSSize(width: SettingsMetrics.windowWidth, height: SettingsMetrics.maxWindowHeight)
            // 自绘圆角窗口的阴影要按新高度重算；松手后记住高度，下次打开沿用
            let center = NotificationCenter.default
            center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak window] _ in
                window?.invalidateShadow()
            }
            center.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main) { [weak window] _ in
                guard let window else { return }
                // fullSizeContentView：内容视图和窗口等高，直接存内容高度
                let height = window.contentView?.frame.height ?? window.frame.height
                UserDefaults.standard.set(Double(height), forKey: Self.settingsHeightKey)
            }
            window.title = "下班啦设置"
            // 参考系统设置：内容铺到标题栏下面，系统标题隐藏，标题由右侧内容区自己画
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            // 空的 unified 工具栏让标题栏变成 52pt 高，红黄绿按钮下移，落在侧边栏面板里
            let toolbar = NSToolbar(identifier: "SettingsToolbar")
            toolbar.showsBaselineSeparator = false
            window.toolbar = toolbar
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            applySettingsAppearance(window)
            // 切换背景时，标题栏和系统控件（开关、菜单）跟着变深/浅
            model.$background
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak window] _ in
                    guard let window else { return }
                    DispatchQueue.main.async { self?.applySettingsAppearance(window) }
                }
                .store(in: &cancellables)
            window.center()
            settingsWindow = window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { window.invalidateShadow() }
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// 标题栏与面板背景同色，避免标题栏和内容区出现色差
    private func applySettingsAppearance(_ window: NSWindow) {
        let palette = SettingsPalette.of(model.background)
        window.appearance = NSAppearance(named: model.background == .light ? .aqua : .darkAqua)
        // 窗口透明，外形由 SwiftUI 的大圆角背景决定；palette.nsWindow 不再用于窗口底色
        _ = palette
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        // 阴影按内容的透明区域重算，才能贴合自绘圆角
        DispatchQueue.main.async { window.invalidateShadow() }
    }

    // MARK: - 主菜单（⌘, 设置、⌘W 关闭、编辑快捷键）

    private func menuItem(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func buildMainMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(menuItem("设置…", #selector(openSettings), ","))
        appMenu.addItem(menuItem("显示桌面小窗", #selector(showDesktopWindow), "0"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "隐藏下班啦", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "退出下班啦", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let edit = NSMenu(title: "编辑")
        edit.addItem(NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let editItem = NSMenuItem()
        editItem.submenu = edit
        main.addItem(editItem)

        let window = NSMenu(title: "窗口")
        window.addItem(NSMenuItem(title: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        let windowItem = NSMenuItem()
        windowItem.submenu = window
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }
}

/// 设置窗口拖动高度限制
/// 不能只靠 contentMinSize/contentMaxSize：窗口显示后 SwiftUI 的 NSHostingView 会把它们重置成 0/无限，
/// 所以在系统询问新尺寸时直接夹住：宽度固定，高度 500–1000
final class SettingsResizeDelegate: NSObject, NSWindowDelegate {
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(width: SettingsMetrics.windowWidth,
               height: min(max(frameSize.height, SettingsMetrics.minWindowHeight), SettingsMetrics.maxWindowHeight))
    }
}
