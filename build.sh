#!/bin/zsh
set -eu
cd "${0:A:h}"
APP="$PWD/Logibat.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build/module-cache
xcrun swiftc -O -module-cache-path "$PWD/.build/module-cache" -target "$(uname -m)-apple-macosx13.0" Sources/Battery.swift Sources/Icons.swift Sources/SonyFrame.swift Sources/SonyState.swift Sources/SonyHeadphones.swift Sources/main.swift -o "$APP/Contents/MacOS/Logibat" -framework AppKit -framework IOKit -framework ServiceManagement -framework IOBluetooth
cp Info.plist "$APP/Contents/Info.plist"
cp THIRD_PARTY_NOTICES "$APP/Contents/Resources/THIRD_PARTY_NOTICES"
codesign --force --sign - "$APP"
echo "Built: $APP"
