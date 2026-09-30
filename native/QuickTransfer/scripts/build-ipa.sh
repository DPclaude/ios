#!/bin/bash
set -euo pipefail
mkdir -p build
xcodegen generate
xcodebuild build -project QuickTransfer.xcodeproj -scheme QuickTransfer -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build/Release CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" 2>&1 | tee build/xcode-release.log
mkdir -p build/package/Payload
ditto build/Release/Build/Products/Release-iphoneos/QuickTransfer.app build/package/Payload/QuickTransfer.app
codesign --force --sign - build/package/Payload/QuickTransfer.app
codesign --verify build/package/Payload/QuickTransfer.app
lipo -info build/package/Payload/QuickTransfer.app/QuickTransfer | grep -q arm64
(cd build/package && ditto -c -k --keepParent Payload ../QuickTransfer-unsigned.ipa)
unzip -t build/QuickTransfer-unsigned.ipa
shasum -a 256 build/QuickTransfer-unsigned.ipa > build/QuickTransfer-unsigned.ipa.sha256
