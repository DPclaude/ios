#!/bin/bash
set -euo pipefail
xcodebuild build -project Planner.xcodeproj -scheme Planner -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/Release \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" 2>&1 | tee build/xcode-release.log
mkdir -p build/package/Payload
ditto build/Release/Build/Products/Release-iphoneos/Planner.app build/package/Payload/Planner.app
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' build/package/Payload/Planner.app/Info.plist | grep -qx 'com.dpclaude.planner'
# SideStore submits the unlocalized name to Apple's appIdName endpoint.
# Keep signing metadata ASCII, and the Chinese Home Screen name localized.
for key in CFBundleDisplayName CFBundleName; do
  /usr/libexec/PlistBuddy -c "Print :$key" build/package/Payload/Planner.app/Info.plist | grep -qx 'Planner'
  plutil -extract "$key" raw -o - build/package/Payload/Planner.app/zh-Hans.lproj/InfoPlist.strings | grep -qx '计划本'
done
echo 'Validated signing name Planner and localized Chinese app name.'
WIDGET=build/package/Payload/Planner.app/PlugIns/PlannerWidget.appex
test -d "$WIDGET"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$WIDGET/Info.plist" | grep -qx 'com.dpclaude.planner.widget'
/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$WIDGET/Info.plist" | grep -qx 'Planner Widget'
/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$WIDGET/Info.plist" | grep -qx 'com.apple.widgetkit-extension'
plutil -extract CFBundleDisplayName raw -o - "$WIDGET/zh-Hans.lproj/InfoPlist.strings" | grep -qx '计划本组件'
lipo -info "$WIDGET/PlannerWidget" | grep -q arm64
# Ad-hoc signatures carry requested group metadata; SideStore replaces them with the user's signature.
codesign --force --sign - --entitlements Planner.entitlements "$WIDGET"
codesign --force --sign - --entitlements Planner.entitlements build/package/Payload/Planner.app
for BUNDLE in "$WIDGET" build/package/Payload/Planner.app; do
  codesign --verify "$BUNDLE"
  codesign -d --entitlements :- "$BUNDLE" 2>/dev/null > build/checked-entitlements.plist
  /usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' build/checked-entitlements.plist | grep -qx 'group.com.dpclaude.planner'
done
echo 'Validated embedded widget and shared group signing metadata.'
lipo -info build/package/Payload/Planner.app/Planner | grep -q arm64
(cd build/package && ditto -c -k --keepParent Payload ../Planner-unsigned.ipa)
unzip -t build/Planner-unsigned.ipa
shasum -a 256 build/Planner-unsigned.ipa > build/Planner-unsigned.ipa.sha256
