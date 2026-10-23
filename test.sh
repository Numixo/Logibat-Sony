#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p .build/module-cache
xcrun swiftc -module-cache-path "$PWD/.build/module-cache" Sources/SonyFrame.swift Sources/SonyState.swift Tests/main.swift -o .build/protocol-tests
.build/protocol-tests
