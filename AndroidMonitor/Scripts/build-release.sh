#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
./Scripts/bootstrap.sh
rm -rf dist
mkdir -p dist
xcodebuild build \
  -project AndroidMonitor.xcodeproj \
  -scheme AndroidMonitor \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath DerivedDataRelease \
  CODE_SIGNING_ALLOWED=NO
cp -R "DerivedDataRelease/Build/Products/Release/Android Monitor.app" dist/
chmod 755 "dist/Android Monitor.app/Contents/Resources/adb"
codesign --force --deep --sign - "dist/Android Monitor.app"

