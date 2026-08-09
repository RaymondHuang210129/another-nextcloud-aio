#!/usr/bin/env bash
set -euo pipefail

codec="${1:-}"
if [[ "$codec" != "h264" && "$codec" != "hevc" ]]; then
  echo "Usage: $0 h264|hevc" >&2
  exit 2
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
override="$SCRIPT_DIR/bin/go-vod-hls-codec"
temporary="$(mktemp "$SCRIPT_DIR/bin/.go-vod-hls-codec.XXXXXX")"
trap 'rm -f -- "$temporary"' EXIT
printf '%s\n' "$codec" > "$temporary"
chmod 0644 "$temporary"
mv -f -- "$temporary" "$override"
trap - EXIT

podman restart nextcloud-memories-transcoder
echo "go-vod HLS codec switched to $codec"
