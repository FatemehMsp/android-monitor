#!/bin/zsh
# Decides whether a release is due from Conventional Commit messages since the last v* tag.
#   feat:            -> minor      fix: / perf:  -> patch      type!: or "BREAKING CHANGE" -> major
#   docs / chore / ci / test / build / style / refactor alone -> no release
# A commit containing "[skip release]" never triggers one. Prints key=value lines (for $GITHUB_OUTPUT).
# FORCE_BUMP=patch|minor|major overrides the commit analysis (used by the manual workflow run).
set -euo pipefail
last="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
range="${last:+$last..}HEAD"
base="${last#v}"; base="${base:-0.0.0}"
IFS=. read -r major minor patch <<< "$base"

bump=none
while IFS= read -r -d $'\x1e' entry; do
  entry="${entry#$'\n'}"   # git log puts a newline between records
  [[ "$entry" == *"[skip release]"* ]] && continue
  subject="${entry%%$'\n'*}"
  if [[ "$subject" =~ '^[a-z]+(\([^)]*\))?!:' ]] || [[ "$entry" == *"BREAKING CHANGE"* ]]; then bump=major
  elif [[ "$subject" =~ '^feat(\(|:)' ]]; then [[ $bump != major ]] && bump=minor
  elif [[ "$subject" =~ '^(fix|perf)(\(|:)' ]]; then [[ $bump == none ]] && bump=patch
  fi
done < <(git log "$range" --format='%B%x1e')

[[ -n "${FORCE_BUMP:-}" && "${FORCE_BUMP}" != auto ]] && bump="$FORCE_BUMP"

case $bump in
  major) major=$((major+1)); minor=0; patch=0 ;;
  minor) minor=$((minor+1)); patch=0 ;;
  patch) patch=$((patch+1)) ;;
  none) echo "release=false"; echo "previous=${last:-none}"; exit 0 ;;
esac
echo "release=true"
echo "version=$major.$minor.$patch"
echo "previous=${last:-none}"
