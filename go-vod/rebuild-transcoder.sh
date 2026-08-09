#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
compose_file="$script_dir/../compose/podman-compose.yml"
service="memories-go-vod"
container="nextcloud-memories-transcoder"
compose=(podman-compose --no-ansi -f "$compose_file")

if ! command -v "${compose[0]}" >/dev/null; then
  echo "ERROR: podman-compose is required so CDI GPU devices are preserved" >&2
  exit 1
fi

echo "[*] Building pinned go-vod image"
"${compose[@]}" build "$service"

echo "[*] Recreating transcoder container"
"${compose[@]}" up -d --no-deps --force-recreate "$service"

echo "[*] Waiting for transcoder readiness"
ready=false
for ((attempt = 1; attempt <= 720; attempt++)); do
  if podman exec nextcloud curl -fsS -o /dev/null \
    "http://nextcloud-memories-transcoder:47788/test/path/test" 2>/dev/null; then
    ready=true
    break
  fi
  if (( attempt % 12 == 0 )); then
    echo "[*] Still waiting; a cold FFmpeg build can take a while"
  fi
  sleep 5
done
if [[ "$ready" != true ]]; then
  podman logs --tail 100 "$container" || true
  echo "ERROR: transcoder did not become ready" >&2
  exit 1
fi


echo "[*] Verifying deployed go-vod"
podman exec "$container" /app/go-vod-custom -version
echo
podman exec "$container" sha256sum /app/go-vod-custom

