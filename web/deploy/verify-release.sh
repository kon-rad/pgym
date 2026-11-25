#!/bin/sh
set -eu

expected_revision=${1:?usage: verify-release.sh REVISION [URL]}
health_url=${2:-http://127.0.0.1:3000/api/health}
body=$(curl --fail --silent --show-error "$health_url")
actual_revision=$(printf '%s' "$body" | sed -n 's/.*"revision":"\([^"]*\)".*/\1/p')

if [ "$actual_revision" != "$expected_revision" ]; then
  echo "revision mismatch: expected $expected_revision, received ${actual_revision:-missing}" >&2
  exit 1
fi

echo "healthy revision $actual_revision"
