#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build
# A stable signing certificate lets TCC recognize subsequent app builds.
# Keep an explicit SIGNING_IDENTITY authoritative; otherwise use the sole local
# Apple Development identity. Never silently choose between multiple identities.
if [[ -z "${SIGNING_IDENTITY:-}" ]]; then
    identities=(${(f)"$(security find-identity -v -p codesigning | awk '/"Apple Development:/ { print $2 }')"})
    if (( ${#identities} == 1 )); then
        SIGNING_IDENTITY="$identities[1]"
    else
        SIGNING_IDENTITY="-"
        print -u2 -- "Warning: using ad-hoc signing; rebuilt apps may require fresh Accessibility authorization. Set SIGNING_IDENTITY to a stable certificate."
    fi
fi
xcodebuild -project MiniToggle.xcodeproj -scheme MiniToggle \
    -configuration Release -destination 'platform=macOS' \
    -derivedDataPath build/xcode CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" build
APP="$PWD/build/MiniToggle.app"
ditto build/xcode/Build/Products/Release/MiniToggle.app "$APP"
codesign --verify --strict "$APP"
print -r -- "$APP"
