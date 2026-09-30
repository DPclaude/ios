#!/bin/bash
set -euo pipefail
mkdir -p build
xcodegen generate
DEVICE=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for k,v in d["devices"].items() if "iOS" in k for x in v if "iPhone" in x["name"]))')
xcodebuild test -project QuickTransfer.xcodeproj -scheme QuickTransfer -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath build/Tests CODE_SIGNING_ALLOWED=NO 2>&1 | tee build/xcode-tests.log
