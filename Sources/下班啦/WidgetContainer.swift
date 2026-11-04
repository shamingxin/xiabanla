import SwiftUI
import AppKit

/// macOS 小组件风格容器：半透明深色毛玻璃 + 大圆角 + 1px 细描边
enum WidgetStyle {
    static let cornerRadius: CGFloat = 24
}

struct WidgetContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WidgetStyle.cornerRadius, style: .continuous)
        content()
            .background(
                ZStack {
                    VisualEffectBackground(cornerRadius: WidgetStyle.cornerRadius)
                    Color.black.opacity(0.5)
                }
            )
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .environment(\.colorScheme, .dark)
    }
}

/// 透出窗口后方内容的毛玻璃（和系统通知中心小组件同类材质）
struct VisualEffectBackground: NSViewRepresentable {
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
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
