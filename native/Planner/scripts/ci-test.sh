#!/bin/bash
set -euo pipefail
mkdir -p build
if [[ ! -x build/XcodeGen/.build/release/xcodegen ]]; then
  git clone --depth 1 --branch 2.46.0 https://github.com/yonaskolb/XcodeGen.git build/XcodeGen
  test "$(git -C build/XcodeGen rev-parse HEAD)" = "8445e778451c7e44237b90281bde622d764b0084"
  swift build --package-path build/XcodeGen --configuration release --product xcodegen
fi
swift scripts/make-icon.swift
build/XcodeGen/.build/release/xcodegen generate
xcodebuild test -project Planner.xcodeproj -scheme Planner \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -resultBundlePath build/Tests.xcresult \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee build/xcode-test.log
