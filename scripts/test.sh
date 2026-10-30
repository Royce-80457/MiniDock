#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build
xcodebuild -project MiniToggle.xcodeproj -scheme MiniToggle \
    -configuration Debug -destination 'platform=macOS' \
    -derivedDataPath build/xcode CODE_SIGNING_ALLOWED=NO test
