#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
command -v xcodegen >/dev/null
./Scripts/fetch-adb.sh
xcodegen generate
