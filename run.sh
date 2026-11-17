#!/bin/sh
# Builds ASCII TV and launches it in the tvOS simulator.
#   ./run.sh                                                  Apple TV 4K
#   DEVICE="Apple TV 4K (4th generation) (at 1080p)" ./run.sh  1080p output
set -e
cd "$(dirname "$0")"
DEVICE="${DEVICE:-Apple TV 4K (4th generation)}"

xcodebuild -project AsciiTV.xcodeproj -scheme AsciiTV -configuration Debug \
  -destination "platform=tvOS Simulator,name=$DEVICE" -derivedDataPath .build/xcode -quiet build

xcrun simctl boot "$DEVICE" 2>/dev/null || true
open "$(xcode-select -p)/Applications/Simulator.app" 2>/dev/null || true
xcrun simctl install "$DEVICE" .build/xcode/Build/Products/Debug-appletvsimulator/AsciiTV.app
xcrun simctl launch --terminate-running-process "$DEVICE" com.example.AsciiTV
