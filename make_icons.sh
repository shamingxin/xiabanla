#!/bin/zsh
# 更换 Assets/icon-source.jpg 后运行，重新生成图标
set -e
cd "$(dirname "$0")"
mkdir -p build/overlay
: > build/overlay/empty.modulemap
cat > build/overlay/vfs.yaml << YAML
{ "version": 0, "case-sensitive": "false", "roots": [
  { "type": "file",
    "name": "/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap",
    "external-contents": "$PWD/build/overlay/empty.modulemap" } ] }
YAML
swiftc -O -vfsoverlay build/overlay/vfs.yaml -Xcc -ivfsoverlay -Xcc build/overlay/vfs.yaml \
  Tools/make_icons.swift -o build/make_icons
./build/make_icons "$PWD"
rm -rf build/make_icons build/overlay
