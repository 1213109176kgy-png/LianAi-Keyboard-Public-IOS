#!/bin/bash
set -euo pipefail
readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SIMULATOR_ID="${1:?Usage: bash scripts/test_ios.sh BOOTED_IPHONE_SIMULATOR_ID}"
cd "$PROJECT_ROOT"
# Seed a synthetic screenshot for the real Photos picker UI test. Use an isolated simulator.
xcrun simctl addmedia "$SIMULATOR_ID" "$PROJECT_ROOT/docs/fixtures/keyboard-voice-source.png"
xcodebuild -project LianAiKeyboard.xcodeproj -scheme LianAiKeyboard \
  -configuration Debug -destination "platform=iOS Simulator,id=${SIMULATOR_ID}" \
  -derivedDataPath .build-artifacts/DerivedData -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO test
