#!/usr/bin/env bash
set -e

echo "=========================================="
echo "🚲 MOUNTAIN BIKE VERIFICATION SUITE"
echo "=========================================="

echo -e "\n[1/2] Running Physics & Math Invariant Tests..."
swift MountainBike/Tests/PhysicsVerificationTests.swift

echo -e "\n[2/2] Running Simulator Build Validation..."
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project MountainBike.xcodeproj -scheme MountainBike \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/trailrush-derived \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO ARCHS=arm64 build | tail -n 20

echo -e "\n🎉 ALL VERIFICATION CHECKS PASSED!"
