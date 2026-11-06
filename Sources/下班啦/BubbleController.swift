import AppKit
import AVFoundation
import SwiftUI

/// 思考泡尺寸：菜单栏图标下方依次吐出 3 个小圈，最后是放动画的云朵大圈
enum BubbleMetrics {
    /// 正方形：和 640×640 的视频比例一致，不会左右被裁
    static let cloudWidth: CGFloat = 195
    static let cloudHeight: CGFloat = 195
    /// 左右留白：放关闭按钮和阴影
    static let sideMargin: CGFloat = 14
    static let bottomMargin: CGFloat = 10
    /// 菜单栏图标到大圈顶部的距离，小圈排在这一段里
    static let trailHeight: CGFloat = 30
    static let lineWidth: CGFloat = 2
    static let closeSize: CGFloat = 26
    /// 播完后停留多久再消失
    static let lingerAfterEnd: TimeInterval = 1
    /// 小圈：直径 + 在轨迹上的位置（0 = 图标处，1 = 大圈顶部），越靠近大圈越大
    static let dots: [(diameter: CGFloat, t: CGFloat)] = [(12, 0.5)]

    static var panelSize: CGSize {
        CGSize(width: cloudWidth + sideMargin * 2, height: trailHeight + cloudHeight + bottomMargin)
    }

    static var cloudRect: CGRect {
        CGRect(x: sideMargin, y: trailHeight, width: cloudWidth, height: cloudHeight)
    }
}

/// 配色参考用户给的漫画思考泡：白底 + 深石板蓝细线
enum BubbleInk {
    static let paper = Color.white
    static let ink = Color(red: 0.20, green: 0.25, blue: 0.32)
    static let shadow = Color.black.opacity(0.18)
}

/// 出现进度：0 隐藏；1…dots.count 小圈依次出现；再 +1 大圈出现
final class BubbleStage: ObservableObject {
    @Published var step = 0
}

/// 管理提醒气泡：同一时间只显示一个，播放完毕 1 秒后收回；常驻模式下循环播放，点 × 才收回
final class BubbleController {
    /// 返回菜单栏图标在屏幕上的位置；图标不可见时返回 nil，气泡退到屏幕右上角
    var anchorProvider: () -> NSRect? = { nil }

    private var panel: NSPanel?
    private var stage: BubbleStage?
    private var player: AVPlayer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var pending: [DispatchWorkItem] = []
    /// 当前气泡收回时（点 ×、播完、被替换）调用一次
    private var onDismiss: (() -> Void)?

    var isShowing: Bool { panel != nil }

    /// 弹出气泡并播放视频。已有气泡时：force 为 true 则替换，否则返回 false 让调度器稍后重试
    /// - loop：常驻模式，同一个视频循环播放，不自动收回
    /// - onDismiss：这个气泡收回时回调一次
    @discardableResult
    func show(videoURL: URL, loop: Bool = false, force: Bool = false, onDismiss: (() -> Void)? = nil) -> Bool {
        if isShowing {
            guard force else { return false }
            dismiss(animated: false)
        }
        present(videoURL, loop: loop)
        self.onDismiss = onDismiss
        return true
    }

    func dismiss(animated: Bool = true) {
        pending.forEach { $0.cancel() }
        pending.removeAll()
        observers.forEach { center, token in center.removeObserver(token) }
        observers.removeAll()
        player?.pause()
        player = nil
        let callback = onDismiss
        onDismiss = nil
        callback?()
        guard let panel else { return }
        let stage = self.stage
        self.panel = nil
        self.stage = nil
        guard animated, let stage else {
            panel.orderOut(nil)
            return
        }
        // 反向收回：大圈先缩回，小圈再依次消失
        let steps = Array((0...BubbleMetrics.dots.count).reversed())
        for (i, step) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + (i == 0 ? 0 : 0.12 + 0.07 * Double(i))) {
                stage.step = step
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { panel.orderOut(nil) }
    }

    // MARK: - 布局与展示

    private func present(_ url: URL, loop: Bool) {
        let size = BubbleMetrics.panelSize

        // 大圈尽量居中在图标正下方；靠近屏幕边缘时整体平移，小圈仍从图标处吐出
        let anchor = anchorProvider()
        let screen = NSScreen.screens.first { anchor.map($0.frame.intersects) ?? false } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let tipX = anchor?.midX ?? (visible.maxX - 60)
        let tipY = anchor.map { $0.minY - 2 } ?? visible.maxY
        var originX = tipX - size.width / 2
        originX = min(max(originX, visible.minX + 4), visible.maxX - size.width - 4)
        let tipInPanel = min(max(tipX - originX, 8), size.width - 8)
        let origin = NSPoint(x: originX, y: tipY - size.height)

        let player = AVPlayer(url: url)
        player.isMuted = true
        player.actionAtItemEnd = .pause
        player.preventsDisplaySleepDuringVideoPlayback = false
        self.player = player

        let stage = BubbleStage()
        self.stage = stage
        let view = BubbleView(stage: stage, tipX: tipInPanel, onClose: { [weak self] in self?.dismiss() }) {
            PlayerLayerView(player: player)
        }
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = BubblePanel(contentRect: NSRect(origin: origin, size: size))
        panel.contentView = hosting
        panel.orderFrontRegardless()
        self.panel = panel

        // 小圈一个接一个吐出来，最后弹出大圈，大圈稳住后开始播放
        let dotCount = BubbleMetrics.dots.count
        var timeline: [(TimeInterval, () -> Void)] = (0..<dotCount).map { i in
            (0.09 * Double(i), { stage.step = i + 1 })
        }
        let cloudAt = 0.09 * Double(dotCount) + 0.05
        timeline.append((cloudAt, { stage.step = dotCount + 1 }))
        timeline.append((cloudAt + 0.2, { player.play() }))
        for (delay, action) in timeline { schedule(after: delay, action) }

        let center = NotificationCenter.default
        observe(center, .AVPlayerItemDidPlayToEndTime, object: player.currentItem) { [weak self, weak player] _ in
            if loop {
                // 常驻：同一个视频从头再播，等用户点 ×
                player?.seek(to: .zero)
                player?.play()
            } else {
                self?.schedule(after: BubbleMetrics.lingerAfterEnd) { self?.dismiss() }
            }
        }
        // 文件损坏或无法播放时不要一直挂着
        observe(center, .AVPlayerItemFailedToPlayToEndTime, object: player.currentItem) { [weak self] _ in
            self?.dismiss()
        }

        // 熄屏 / 锁屏时暂停，回来后接着播，气泡留在原处
        let pause: (Notification) -> Void = { [weak player] _ in player?.pause() }
        let resume: (Notification) -> Void = { [weak self, weak player] _ in
            guard let self, self.panel != nil, (self.stage?.step ?? 0) > BubbleMetrics.dots.count else { return }
            player?.play()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification, using: pause)
        observe(workspace, NSWorkspace.screensDidWakeNotification, using: resume)
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked"), using: pause)
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked"), using: resume)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, object: Any? = nil,
                         using block: @escaping (Notification) -> Void) {
        let token = center.addObserver(forName: name, object: object, queue: .main, using: block)
        observers.append((center, token))
    }

    private func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) {
        let work = DispatchWorkItem(block: action)
        pending.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

/// 无边框、不抢焦点、所有桌面空间都可见的浮层；阴影由 SwiftUI 画，跟随形状
final class BubblePanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - 气泡视图

/// 思考泡：小圈从菜单栏图标往下排，越来越大，连到云朵大圈；动画裁在云朵里
struct BubbleView<Content: View>: View {
    @ObservedObject var stage: BubbleStage
    let tipX: CGFloat
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    private static var pop: Animation { .spring(response: 0.3, dampingFraction: 0.6) }

    var body: some View {
        let size = BubbleMetrics.panelSize
        let cloud = BubbleMetrics.cloudRect
        let trailEnd = CGPoint(x: cloud.midX, y: cloud.minY + 2)
        let cloudShown = stage.step > BubbleMetrics.dots.count

        ZStack(alignment: .topLeading) {
            ForEach(Array(BubbleMetrics.dots.enumerated()), id: \.offset) { index, dot in
                let shown = stage.step > index
                ThoughtDot(diameter: dot.diameter)
                    .scaleEffect(shown ? 1 : 0.01)
                    .opacity(shown ? 1 : 0)
                    .animation(Self.pop, value: stage.step)
                    .position(Self.dotCenter(t: dot.t, tipX: tipX, end: trailEnd))
            }

            ZStack {
                CloudShape().fill(BubbleInk.paper)
                    .shadow(color: BubbleInk.shadow, radius: 5, y: 2)
                content()
                    .frame(width: cloud.width, height: cloud.height)
                    .clipShape(CloudShape())
                    .accessibilityLabel("提醒动画")
                CloudShape()
                    .stroke(BubbleInk.ink, style: StrokeStyle(lineWidth: BubbleMetrics.lineWidth, lineJoin: .round))
            }
            .frame(width: cloud.width, height: cloud.height)
            .overlay(alignment: .topTrailing) {
                HandDrawnCloseButton(action: onClose).offset(x: 6, y: 4)
            }
            // 从小圈连接处长出来
            .scaleEffect(cloudShown ? 1 : 0.3, anchor: UnitPoint(x: (trailEnd.x - cloud.minX) / cloud.width, y: 0))
            .opacity(cloudShown ? 1 : 0)
            .animation(Self.pop, value: stage.step)
            .position(x: cloud.midX, y: cloud.midY)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .environment(\.colorScheme, .light)
    }

    /// 小圈沿一条略带弧度的线，从图标处排到大圈顶部
    static func dotCenter(t: CGFloat, tipX: CGFloat, end: CGPoint) -> CGPoint {
        let x = tipX + (end.x - tipX) * t - 4 * sin(t * .pi)
        let y = end.y * t
        return CGPoint(x: x, y: y)
    }
}

/// 一个小圈：白底细线
struct ThoughtDot: View {
    let diameter: CGFloat

    var body: some View {
        Circle()
            .fill(BubbleInk.paper)
            .overlay(Circle().stroke(BubbleInk.ink, lineWidth: diameter < 6 ? 1.4 : 1.8))
            .frame(width: diameter, height: diameter)
            .shadow(color: BubbleInk.shadow, radius: 2, y: 1)
    }
}

/// 云朵轮廓：一圈大小不一的圆鼓包，鼓包之间是尖的凹口，和漫画思考泡一样
struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        let bumps = 12.0
        let amp = min(rect.width, rect.height) * 0.026
        let maxAmp = amp * 1.25
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let rx = rect.width / 2 - maxAmp
        let ry = rect.height / 2 - maxAmp
        let samples = 360
        var p = Path()
        for i in 0..<samples {
            let th = Double(i) / Double(samples) * 2 * .pi
            // 扭一下角度，让鼓包宽窄不一
            let phi = th + 0.12 * sin(2 * th + 0.6) + 0.05 * sin(3 * th + 2.0)
            // 指数越大鼓包越圆、凹口越浅
            let bump = CGFloat(pow(abs(sin(bumps * phi / 2)), 0.75))
            let a = amp * CGFloat(1 + 0.25 * sin(5 * th + 1))
            // 略方的椭圆底形，云朵更饱满
            let ct = cos(th), st = sin(th)
            let ex = CGFloat(copysign(pow(abs(ct), 0.6), ct))
            let ey = CGFloat(copysign(pow(abs(st), 0.6), st))
            let pt = CGPoint(x: c.x + (rx + a * bump) * ex, y: c.y + (ry + a * bump) * ey)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }
}

/// 关闭按钮：手画的小圆 + ×
struct HandDrawnCloseButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                WobblyCircle().fill(hovering ? Color(white: 0.9) : BubbleInk.paper)
                WobblyCircle().stroke(BubbleInk.ink, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                ScribbleCross().stroke(BubbleInk.ink, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
            .frame(width: BubbleMetrics.closeSize, height: BubbleMetrics.closeSize)
            .shadow(color: BubbleInk.shadow, radius: 2, y: 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("关闭")
        .accessibilityLabel("关闭提醒")
    }
}

/// 手画的小圆：半径有起伏
struct WobblyCircle: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = rect.width / 2 - 1.4
        var p = Path()
        let count = 48
        for i in 0...count {
            let t = Double(i) / Double(count) * 2 * .pi - 2.2
            let rr = r + CGFloat(0.5 * sin(3 * t + 0.4) + 0.3 * sin(5 * t))
            let pt = CGPoint(x: c.x + rr * CGFloat(cos(t)), y: c.y + rr * CGFloat(sin(t)))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }
}

/// 手写的 ×：两笔略带弧度
struct ScribbleCross: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.33, y: h * 0.32))
        p.addQuadCurve(to: CGPoint(x: w * 0.69, y: h * 0.67), control: CGPoint(x: w * 0.53, y: h * 0.47))
        p.move(to: CGPoint(x: w * 0.67, y: h * 0.30))
        p.addQuadCurve(to: CGPoint(x: w * 0.32, y: h * 0.70), control: CGPoint(x: w * 0.47, y: h * 0.52))
        return p
    }
}

/// 只渲染画面、不带任何播放控件的视频层
struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer = layer
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView.layer as? AVPlayerLayer)?.player = player
    }
}
