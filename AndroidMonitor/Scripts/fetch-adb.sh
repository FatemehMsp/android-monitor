#!/bin/zsh
# Puts a copy of Google's adb into Resources/adb (bundled into the app). adb is not stored in this repository.
set -euo pipefail
cd "${0:A:h}/.."
[ -x Resources/adb ] && exit 0
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
if [ -x "$SDK/platform-tools/adb" ]; then
  cp "$SDK/platform-tools/adb" Resources/adb
else
  TMP="$(mktemp -d)"
  curl -fsSL -o "$TMP/pt.zip" https://dl.google.com/android/repository/platform-tools-latest-darwin.zip
  unzip -q -j "$TMP/pt.zip" platform-tools/adb -d Resources
fi
chmod 755 Resources/adb
echo "adb ready: $(Resources/adb version | head -1)"
