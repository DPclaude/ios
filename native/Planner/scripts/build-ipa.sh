#!/bin/bash
set -euo pipefail
xcodebuild build -project Planner.xcodeproj -scheme Planner -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/Release \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" 2>&1 | tee build/xcode-release.log
mkdir -p build/package/Payload
ditto build/Release/Build/Products/Release-iphoneos/Planner.app build/package/Payload/Planner.app
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' build/package/Payload/Planner.app/Info.plist | grep -qx 'com.dpclaude.planner'
lipo -info build/package/Payload/Planner.app/Planner | grep -q arm64
(cd build/package && ditto -c -k --keepParent Payload ../Planner-unsigned.ipa)
unzip -t build/Planner-unsigned.ipa
shasum -a 256 build/Planner-unsigned.ipa > build/Planner-unsigned.ipa.sha256
