// 由 Assets/icon-source.jpg 生成 Assets/AppIcon.icns 和 Assets/MenuBarIcon.png
import AppKit

let root = CommandLine.arguments[1]
guard let src = NSImage(contentsOfFile: "\(root)/Assets/icon-source.jpg"),
      let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("读取 icon-source.jpg 失败")
}

/// 裁剪 crop 区域（像素，左上角原点），绘制到 size×size 画布，按圆角方块或圆形裁切
func render(_ size: Int, crop: CGRect, inset: CGFloat, circle: Bool) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    let s = CGFloat(size)
    let r = NSRect(x: s * inset, y: s * inset, width: s * (1 - 2 * inset), height: s * (1 - 2 * inset))
    let path = circle ? NSBezierPath(ovalIn: r)
                      : NSBezierPath(roundedRect: r, xRadius: r.width * 0.225, yRadius: r.width * 0.225)
    path.addClip()
    ctx.cgContext.draw(cg.cropping(to: crop)!, in: r)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = "\(root)/build/AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

// App 图标：整张插画，按 macOS 图标网格四周留白约 10%
let appCrop = CGRect(x: 47, y: 0, width: 960, height: 960)
for size in [16, 32, 128, 256, 512] {
    try! render(size, crop: appCrop, inset: 0.098, circle: false).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(size)x\(size).png"))
    try! render(size * 2, crop: appCrop, inset: 0.098, circle: false).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(size)x\(size)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset, "-o", "\(root)/Assets/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
try? fm.removeItem(atPath: iconset)

// 菜单栏图标：猫头圆形头像，36px（菜单栏按 18pt @2x 显示）
try! render(36, crop: CGRect(x: 140, y: 70, width: 560, height: 560), inset: 0, circle: true)
    .write(to: URL(fileURLWithPath: "\(root)/Assets/MenuBarIcon.png"))
print("图标生成完成")
