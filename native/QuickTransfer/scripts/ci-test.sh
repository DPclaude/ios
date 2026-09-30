#!/bin/bash
set -euo pipefail
mkdir -p build
xcodegen generate
DEVICE=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for k,v in d["devices"].items() if "iOS" in k for x in v if "iPhone" in x["name"]))')
xcodebuild test -project QuickTransfer.xcodeproj -scheme QuickTransfer -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath build/Tests CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual 2>&1 | tee build/xcode-tests.log
APP=build/Tests/Build/Products/Debug-iphonesimulator/QuickTransfer.app
codesign --verify "$APP"
codesign -d --entitlements :- "$APP" > build/simulator-entitlements.plist 2>/dev/null
/usr/libexec/PlistBuddy -c 'Print :application-identifier' build/simulator-entitlements.plist | grep -qx 'QTLOCAL001.com.pandong.quicktransfer'
/usr/libexec/PlistBuddy -c 'Print :keychain-access-groups:0' build/simulator-entitlements.plist | grep -qx 'QTLOCAL001.com.pandong.quicktransfer'
