#!/bin/zsh
# 一键编译并打包 下班啦.app（只需要 Command Line Tools，无需 Xcode）
set -e
cd "$(dirname "$0")"
mkdir -p build/overlay
: > build/overlay/empty.modulemap
# 屏蔽 CLT 中重复定义的旧 module.modulemap（不修改系统文件）
cat > build/overlay/vfs.yaml << YAML
{ "version": 0, "case-sensitive": "false", "roots": [
  { "type": "file",
    "name": "/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap",
    "external-contents": "$PWD/build/overlay/empty.modulemap" } ] }
YAML
swiftc -parse-as-library -O -target arm64-apple-macos13.0 \
  -vfsoverlay build/overlay/vfs.yaml -Xcc -ivfsoverlay -Xcc build/overlay/vfs.yaml \
  Sources/下班啦/*.swift -o build/下班啦-bin

APP="build/下班啦.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mv build/下班啦-bin "$APP/Contents/MacOS/下班啦"
mkdir -p "$APP/Contents/Resources"
cp Assets/AppIcon.icns Assets/MenuBarIcon.png "$APP/Contents/Resources/"
# 内置提醒视频（可选）：Assets/Videos/喝水、Assets/Videos/彩蛋
if [ -d Assets/Videos ]; then cp -R Assets/Videos "$APP/Contents/Resources/"; fi
cat > "$APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>下班啦</string>
  <key>CFBundleDisplayName</key><string>下班啦</string>
  <key>CFBundleIdentifier</key><string>com.shasha.xiabanla</string>
  <key>CFBundleExecutable</key><string>下班啦</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.6</string>
  <key>CFBundleVersion</key><string>7</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
rm -rf build/overlay build/compile.log
echo "构建完成: $PWD/$APP"
