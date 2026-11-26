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
# 不能在运行中删除 .app：Launch Services 会把旧进程当作损坏包而直接终止。
# 先正常退出，构建完成后再由系统启动器拉起新版。
WAS_RUNNING=0
if pgrep -x "下班啦" >/dev/null 2>&1; then
  WAS_RUNNING=1
  pkill -x "下班啦"
  for _ in {1..20}; do
    pgrep -x "下班啦" >/dev/null 2>&1 || break
    sleep 0.1
  done
fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mv build/下班啦-bin "$APP/Contents/MacOS/下班啦"
mkdir -p "$APP/Contents/Resources"
cp Assets/AppIcon.icns Assets/MenuBarIcon.png Assets/Kirby.gif "$APP/Contents/Resources/"
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
  <key>CFBundleShortVersionString</key><string>2.0</string>
  <key>CFBundleVersion</key><string>22</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
rm -rf build/overlay build/compile.log
echo "构建完成: $PWD/$APP"
if [[ "$WAS_RUNNING" == "1" ]]; then
  if ! open "$APP"; then
    echo "新版未能自动显示；请从 build/下班啦.app 手动打开。" >&2
  fi
fi
