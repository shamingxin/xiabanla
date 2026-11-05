import SwiftUI
import AppKit

/// macOS 小组件风格容器：半透明深色毛玻璃 + 大圆角 + 1px 细描边
enum WidgetStyle {
    static let cornerRadius: CGFloat = 24
    /// 图片主题的不透明度：图片清晰可见，同时透出后方的模糊
    static let imageOpacity: Double = 0.8
    /// 图片上方纯黑遮罩的不透明度
    static let imageDim: Double = 0.3
}

struct WidgetContainer<Content: View>: View {
    @ObservedObject var model: WorkTimerModel
    @ViewBuilder var content: () -> Content

    /// 图片模式下实际能读到的图片；读不到（被删了）时退回黑色
    private var customImage: NSImage? {
        guard model.background == .image, let path = model.backgroundImagePath else { return nil }
        return NSImage(contentsOfFile: path)
    }

    private var isLight: Bool { model.background == .light }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WidgetStyle.cornerRadius, style: .continuous)
        content()
            .background(background)
            .clipShape(shape)
            .overlay(shape.strokeBorder(isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.12), lineWidth: 1))
            .environment(\.colorScheme, isLight ? .light : .dark)
            .environment(\.cardPalette, isLight ? .light : .dark)
    }

    @ViewBuilder
    private var background: some View {
        if let image = customImage {
            // 图片模式：最底层是毛玻璃（模糊卡片后面的桌面/窗口），上面叠半透明图片
            // 图片本身不模糊，透明度让后面的模糊层隐约透出来
            ZStack {
                VisualEffectBackground(cornerRadius: WidgetStyle.cornerRadius)
                // 图片按比例放大铺满卡片、居中裁切，四边都不会露底
                FillImageView(image: image)
                    .opacity(WidgetStyle.imageOpacity)
                // 纯黑遮罩压暗图片，避免抢眼，也保证浅色数字看得清
                Color.black.opacity(WidgetStyle.imageDim)
            }
        } else if isLight {
            ZStack {
                VisualEffectBackground(cornerRadius: WidgetStyle.cornerRadius, light: true)
                Color.white.opacity(0.6)
            }
        } else {
            ZStack {
                VisualEffectBackground(cornerRadius: WidgetStyle.cornerRadius)
                Color.black.opacity(0.5)
            }
        }
    }
}

/// 图片铺满容器：用 CALayer 的 resizeAspectFill，尺寸始终跟随视图边界，居中裁切
struct FillImageView: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.contentsGravity = .resizeAspectFill
        view.layer?.masksToBounds = true
        view.layer?.contents = image
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        view.layer?.contents = image
    }
}

/// 透出窗口后方内容的毛玻璃（和系统通知中心小组件同类材质）
struct VisualEffectBackground: NSViewRepresentable {
    var cornerRadius: CGFloat
    var light = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = light ? .popover : .hudWindow
        view.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = Self.maskImage(cornerRadius: cornerRadius)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}

    /// 可拉伸的圆角遮罩，让毛玻璃本身也是圆角
    private static func maskImage(cornerRadius r: CGFloat) -> NSImage {
        let edge = r * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        image.resizingMode = .stretch
        return image
    }
}

/// 无边框透明面板：桌面小窗和菜单栏浮层共用
final class WidgetPanel: NSPanel {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                  backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backing, defer: flag)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { !styleMask.contains(.nonactivatingPanel) }

    /// 无边框窗口没有关闭按钮，⌘W / Esc 直接隐藏
    override func performClose(_ sender: Any?) { orderOut(nil) }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }

    /// 内容高度变化（如点了「开始上班」）时保持顶边不动
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var rect = frameRect
        if isVisible, frame.height > 0, rect.height != frame.height {
            rect.origin.y = frame.maxY - rect.height
        }
        super.setFrame(rect, display: flag)
        invalidateShadow()
    }
}

/// 桌面小窗：无边框、可最小化到程序坞
final class WidgetWindow: NSWindow {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                  backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backing, defer: flag)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performClose(_ sender: Any?) { orderOut(nil) }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }

    /// 内容高度变化时保持顶边不动
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var rect = frameRect
        if isVisible, frame.height > 0, rect.height != frame.height {
            rect.origin.y = frame.maxY - rect.height
        }
        super.setFrame(rect, display: flag)
        invalidateShadow()
    }
}
