#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/bin"
BUILDER_IMAGE="localhost/nextcloud-memories-transcoder-builder:go-vod-0.2.6"

mkdir -p "$OUTPUT_DIR"

podman build \
  --target go-vod-builder \
  --tag "$BUILDER_IMAGE" \
  "$SCRIPT_DIR"

builder_container="$(podman create "$BUILDER_IMAGE")"
temporary="$(mktemp "$OUTPUT_DIR/.go-vod-custom.XXXXXX")"
cleanup() {
  podman rm "$builder_container" >/dev/null 2>&1 || true
  rm -f -- "$temporary"
}
trap cleanup EXIT

podman cp "$builder_container:/out/go-vod-custom" "$temporary"
chmod 0755 "$temporary"
mv -f -- "$temporary" "$OUTPUT_DIR/go-vod-custom"
trap - EXIT
podman rm "$builder_container" >/dev/null

echo "Built $OUTPUT_DIR/go-vod-custom"
