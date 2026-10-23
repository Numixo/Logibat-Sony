#!/bin/zsh
set -eu
cd "${0:A:h}"
./build.sh
mkdir -p dist
APP_ARCH="$(uname -m)"
case "$APP_ARCH" in
    arm64) LABEL=AppleSilicon ;;
    x86_64) LABEL=Intel ;;
    *) echo "Unsupported architecture: $APP_ARCH" >&2; exit 1 ;;
esac
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
ARCHIVE="Logibat-Sony-$VERSION-macOS-$LABEL.zip"
codesign --verify --strict Logibat.app
plutil -lint Logibat.app/Contents/Info.plist
ditto -c -k --sequesterRsrc --keepParent Logibat.app "dist/$ARCHIVE"
(cd dist && shasum -a 256 "$ARCHIVE" > SHA256SUMS.txt)
unzip -t "dist/$ARCHIVE"
echo "Release package: $PWD/dist/$ARCHIVE"
