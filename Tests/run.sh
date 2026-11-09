#!/bin/zsh
# 运行自动计时判定测试（只需 Command Line Tools）
set -e
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
: > "$TMP/empty.modulemap"
cat > "$TMP/vfs.yaml" << YAML
{ "version": 0, "case-sensitive": "false", "roots": [
  { "type": "file", "name": "/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap",
    "external-contents": "$TMP/empty.modulemap" } ] }
YAML
cp Tests/AutoStartTests.swift "$TMP/main.swift"
swiftc -target arm64-apple-macos13.0 -vfsoverlay "$TMP/vfs.yaml" -Xcc -ivfsoverlay -Xcc "$TMP/vfs.yaml" \
  "$TMP/main.swift" Sources/下班啦/WorkTimerModel.swift Sources/下班啦/LoginItemManager.swift -o "$TMP/t"
"$TMP/t"
