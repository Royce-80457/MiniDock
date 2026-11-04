#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
MT_APP="${1:-$PWD/build/xcode/Build/Products/Release/MiniToggle.app}"
MT_VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$MT_APP/Contents/Info.plist")
MT_OUTPUT="$PWD/build/release"
MT_STAGE="$PWD/build/dmg-stage-$MT_VERSION"
MT_DMG="$MT_OUTPUT/MiniToggle-$MT_VERSION-universal.dmg"
[[ ! -e "$MT_STAGE" && ! -e "$MT_DMG" ]] || { print -u2 'Staging or DMG already exists; refusing to overwrite.'; exit 1; }
codesign --verify --strict "$MT_APP"
MT_ARCHS=$(lipo -archs "$MT_APP/Contents/MacOS/MiniToggle")
[[ " $MT_ARCHS " == *" arm64 "* && " $MT_ARCHS " == *" x86_64 "* ]] || { print -u2 'App must contain arm64 and x86_64.'; exit 1; }
mkdir -p "$MT_OUTPUT" "$MT_STAGE"
ditto "$MT_APP" "$MT_STAGE/MiniToggle.app"
ln -s /Applications "$MT_STAGE/Applications"
cp docs/INSTALL.zh-CN.md "$MT_STAGE/安装说明.txt"
hdiutil create -volname "MiniToggle $MT_VERSION" -srcfolder "$MT_STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$MT_DMG"
(cd "$MT_OUTPUT" && shasum -a 256 "${MT_DMG:t}" > SHA256SUMS.txt)
print -r -- "$MT_DMG"
