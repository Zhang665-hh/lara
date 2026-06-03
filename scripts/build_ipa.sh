#!/bin/bash
set -euo pipefail

rm -rf build/
mkdir -p build

echo "Build Started!"
echo

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
  "OTHER_LDFLAGS=\$(inherited) -framework Security -framework Photos" \
  archive \
  -archivePath "$PWD/build/lara.xcarchive" 2>&1 | tee "$PWD/build/xcodebuild.log" | xcpretty

APP_PATH="$PWD/build/lara.xcarchive/Products/Applications/lara.app"
if [ ! -d "$APP_PATH" ]; then
  echo ""
  echo "=== BUILD FAILED ==="
  echo "Full log at build/xcodebuild.log"
  echo "=== LAST 150 LINES ==="
  tail -150 "$PWD/build/xcodebuild.log"
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