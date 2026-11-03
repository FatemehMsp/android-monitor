#!/bin/zsh
# Compiles Scripts/cliphelper/*.java into Resources/amclip.jar (dex), run on the phone via app_process.
set -euo pipefail
cd "${0:A:h}/.."
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
JAR="$SDK/platforms/android-33/android.jar"
D8="$(ls -d "$SDK"/build-tools/*/d8 | sort -V | tail -1)"
TMP="$(mktemp -d)"
javac --release 8 -cp "$JAR" -d "$TMP/classes" Scripts/cliphelper/*.java 2>&1 | grep -v "warning" || true
"$D8" --lib "$JAR" --output "$TMP/out.jar" "$TMP"/classes/*.class
cp "$TMP/out.jar" Resources/amclip.jar
echo "built Resources/amclip.jar"
