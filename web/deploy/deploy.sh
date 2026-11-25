#!/bin/sh
set -eu

host=
revision=
dry_run=false
artifact=

usage() {
  echo "usage: deploy.sh --host HOST --revision GIT_SHA --artifact ARCHIVE [--dry-run]" >&2
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --host) host=${2:-}; shift 2 ;;
    --revision) revision=${2:-}; shift 2 ;;
    --artifact) artifact=${2:-}; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    *) usage ;;
  esac
done

[ -n "$host" ] && [ -n "$revision" ] && [ -n "$artifact" ] || usage
printf '%s' "$revision" | grep -Eq '^[0-9a-f]{7,40}$' || { echo "revision must be a git SHA" >&2; exit 2; }
[ -f "$artifact" ] || { echo "artifact not found: $artifact" >&2; exit 2; }

release="/opt/pgym/releases/$revision"
remote_archive="/tmp/pgym-$revision.tar.gz"

echo "host=$host"
echo "revision=$revision"
echo "release=$release"
echo "artifact=$artifact"

if [ "$dry_run" = true ]; then
  echo "validation complete; no remote changes made"
  exit 0
fi

scp "$artifact" "$host:$remote_archive"
ssh "$host" "set -eu; test ! -e '$release'; mkdir -p '$release'; tar -xzf '$remote_archive' -C '$release'; test -f '$release/web/server.js'; ln -sfn '$release' /opt/pgym/current.next; mv -Tf /opt/pgym/current.next /opt/pgym/current; systemctl restart pgym; rm '$remote_archive'"
ssh "$host" "/opt/pgym/current/web/deploy/verify-release.sh '$revision'"
