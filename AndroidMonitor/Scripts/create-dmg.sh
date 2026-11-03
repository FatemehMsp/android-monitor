#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
./Scripts/build-release.sh
rm -rf dist/dmg-root dist/AndroidMonitor.dmg
mkdir -p dist/dmg-root
cp -R "dist/Android Monitor.app" dist/dmg-root/
ln -s /Applications dist/dmg-root/Applications
hdiutil create -volname "Android Monitor" -srcfolder dist/dmg-root -ov -format UDZO dist/AndroidMonitor.dmg
shasum -a 256 dist/AndroidMonitor.dmg > dist/AndroidMonitor.dmg.sha256

