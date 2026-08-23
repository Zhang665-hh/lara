#!/bin/bash
set -uo pipefail

rm -rf build/
mkdir -p build

echo "Build Started!"
echo

# Disable -e around the pipeline so we can capture PIPESTATUS and dump logs.
set +e
xcodebuild \
  -project lara.xcodeproj \
  -scheme lara \
  -configuration Debug \
  -sdk iphoneos \
  -arch arm64e \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  EXPANDED_CODE_SIGN_IDENTITY="" \
  AD_HOC_CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_ENTITLEMENTS="Config/lara.entitlements" \
  SWIFT_STRICT_CONCURRENCY=minimal \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=NO \
  GCC_TREAT_WARNINGS_AS_ERRORS=NO \
  archive \
  -archivePath "$PWD/build/lara.xcarchive" 2>&1 | tee "$PWD/build/xcodebuild.log" | xcpretty
EXIT_CODE=${PIPESTATUS[0]}
set -e

APP_PATH="$PWD/build/lara.xcarchive/Products/Applications/lara.app"

if [ "$EXIT_CODE" -ne 0 ] || [ ! -d "$APP_PATH" ]; then
  echo ""
  echo "=== BUILD FAILED (exit $EXIT_CODE) ==="
  echo "=== LAST 200 LINES ==="
  tail -200 "$PWD/build/xcodebuild.log" || true
  echo ""
  echo "=== ERROR LINES ONLY ==="
  grep -i "error:" "$PWD/build/xcodebuild.log" || echo "(no error: lines found)"
  exit 1
fi

echo ""
echo "[*] Packaging IPA..."

rm -rf "$PWD/build/Payload"
mkdir -p "$PWD/build/Payload"
cp -R "$APP_PATH" "$PWD/build/Payload/"

plutil -replace UIFileSharingEnabled -bool YES "$PWD/build/Payload/lara.app/Info.plist"

if ! command -v ldid >/dev/null 2>&1; then
  echo "ERROR: ldid not installed. Install with: brew install ldid" >&2
  exit 1
fi
ldid -SConfig/lara.entitlements "$PWD/build/Payload/lara.app/lara"
(cd "$PWD/build" && /usr/bin/zip -qry lara.ipa Payload)

echo ""
echo "build successful!"
echo "ipa at: build/lara.ipa"
exit 0
