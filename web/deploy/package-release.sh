#!/bin/sh
set -eu

revision=${1:?usage: package-release.sh REVISION OUTPUT_ARCHIVE}
output=${2:?usage: package-release.sh REVISION OUTPUT_ARCHIVE}
printf '%s' "$revision" | grep -Eq '^[0-9a-f]{7,40}$' || { echo "revision must be a git SHA" >&2; exit 2; }
test -f .next/standalone/server.js || { echo "run npm run build first" >&2; exit 2; }

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT INT TERM
mkdir -p "$stage/web/.next"
cp -R .next/standalone/. "$stage/web/"
cp -R .next/static "$stage/web/.next/static"
if test -d public; then cp -R public "$stage/web/public"; fi
cp -R deploy "$stage/web/deploy"
printf '%s\n' "$revision" > "$stage/REVISION"
tar -czf "$output" -C "$stage" .
echo "created $output for $revision"
