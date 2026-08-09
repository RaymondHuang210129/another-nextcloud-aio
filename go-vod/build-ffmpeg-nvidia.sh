#!/usr/bin/env bash
set -euo pipefail

# --- Versions/flags you can tweak ---
FFMPEG_REF="140fd653aed8cad774f991ba083e2d01e86420c7" # n8.0 peeled commit
NV_CODEC_HEADERS_REF="88fee5c37318c991a8762d423530f91681e32e3a" # n13.0.19.1
NV_CODEC_HEADERS_TAG="n13.0.19.1"
CUDA_BUILD_PACKAGES=(cuda-nvcc-13-0 cuda-cudart-dev-13-0)
CUDA_KEYRING_URL="https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/cuda-keyring_1.1-1_all.deb"
CUDA_KEYRING_SHA256="e7f219eab6fe4819cdb5c15b98233dc3420302d9c00883219cd3d896857cf48d"
NVCC_SM_FLAGS="-gencode=arch=compute_90,code=sm_90"  # use 'sm_89' if your nvcc rejects 90
PREFIX="/usr/local"
# ------------------------------------

run_go_vod() {
  local hls_codec="${GO_VOD_HLS_CODEC:-h264}"
  local codec_override="$PREFIX/bin/go-vod-hls-codec"
  if [[ -r "$codec_override" ]]; then
    read -r hls_codec < "$codec_override"
  fi

  if [[ "$hls_codec" == "hevc" ]]; then
    local custom_go_vod="/app/go-vod-custom"
    if [[ ! -x "$custom_go_vod" ]]; then
      echo "ERROR: GO_VOD_HLS_CODEC=hevc but $custom_go_vod is missing or not executable"
      exit 1
    fi
    echo "[*] Starting experimental HEVC/fMP4 go-vod"
    exec "$custom_go_vod" -version-monitor "$@"
  fi

  if [[ "$hls_codec" != "h264" ]]; then
    echo "ERROR: unsupported HLS codec '$hls_codec' (expected h264 or hevc)"
    exit 1
  fi

  echo "[*] Starting stock go-vod"
  exec /app/entrypoint.sh "$@"
}

# if ffmpeg.real exists, the ffmpeg has been built already; skip
if [[ -f "$PREFIX/bin/ffmpeg.real" ]]; then
  echo "[*] FFmpeg with NVIDIA support already installed, skipping build."
  cp -- /app/ffmpeg-wrapper "$PREFIX/bin/ffmpeg"
  run_go_vod "$@"
fi

export DEBIAN_FRONTEND=noninteractive

echo "[*] Installing build prerequisites"
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl git pkg-config build-essential yasm nasm \
  autoconf automake libtool cmake \
  libx264-dev

echo "[*] Installing minimal CUDA 13.0 build toolchain"
tmpdeb="$(mktemp)"
curl -fsSL \
  "$CUDA_KEYRING_URL" \
  -o "$tmpdeb"
echo "$CUDA_KEYRING_SHA256  $tmpdeb" | sha256sum -c -
dpkg -i "$tmpdeb"
rm -f "$tmpdeb"
apt-get update
apt-get install -y --no-install-recommends "${CUDA_BUILD_PACKAGES[@]}"

export CUDA_HOME=/usr/local/cuda
export PATH="$CUDA_HOME/bin:${PATH}"
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}"
hash -r

# Sanity: show nvcc and bail if missing
echo "[*] nvcc version:"
nvcc --version || { echo "ERROR: nvcc not found on PATH"; exit 1; }

build_root="$(mktemp -d /tmp/go-vod-build.XXXXXX)"
trap 'rm -rf -- "$build_root"' EXIT
headers_dir="$build_root/nv-codec-headers"
ffmpeg_dir="$build_root/ffmpeg"

echo "[*] Installing pinned NVENC/NVDEC headers"
git init "$headers_dir"
git -C "$headers_dir" remote add origin https://github.com/FFmpeg/nv-codec-headers.git
git -C "$headers_dir" fetch --depth=1 origin "refs/tags/$NV_CODEC_HEADERS_TAG"
git -C "$headers_dir" checkout --detach FETCH_HEAD
test "$(git -C "$headers_dir" rev-parse HEAD)" = "$NV_CODEC_HEADERS_REF"
make -C "$headers_dir" install

echo "[*] Fetching pinned FFmpeg ${FFMPEG_REF}"
git init "$ffmpeg_dir"
git -C "$ffmpeg_dir" remote add origin https://github.com/FFmpeg/FFmpeg.git
git -C "$ffmpeg_dir" fetch --depth=1 origin "$FFMPEG_REF"
git -C "$ffmpeg_dir" checkout --detach FETCH_HEAD
test "$(git -C "$ffmpeg_dir" rev-parse HEAD)" = "$FFMPEG_REF"
cd "$ffmpeg_dir"

# Apply Faeez Kadiri's transpose_cuda patch. Provenance and the original
# FFmpeg Patchwork submission are recorded in /app/patches/README.md. Its
# cosmetic Changelog hunk predates n8.0; all functional hunks apply unchanged.
echo "[*] Applying vendored transpose_cuda patch"
git apply --exclude=Changelog --check /app/patches/ffmpeg-transpose-cuda.patch
git apply --exclude=Changelog /app/patches/ffmpeg-transpose-cuda.patch

# trap 'cat /tmp/ffmpeg/ffbuild/config.log' ERR

echo "[*] Configuring FFmpeg (CUDA filters + NVENC/NVDEC + x264)"
./configure \
  --prefix="$PREFIX" \
  --enable-gpl --enable-nonfree \
  --enable-libx264 \
  --enable-nvenc --enable-nvdec \
  --enable-cuda-nvcc \
  --extra-cflags="-I/usr/local/cuda/include" \
  --extra-ldflags="-L/usr/local/cuda/lib64" \
  --nvccflags="$NVCC_SM_FLAGS -lineinfo" \
  --disable-ffplay --disable-sdl2 \
  --disable-xlib --disable-libxcb \
  --disable-vaapi --disable-vdpau \
  --disable-doc

echo "[*] Building FFmpeg"
make -j"$(nproc)"

echo "[*] Installing FFmpeg to $PREFIX (overrides /usr/bin on PATH)"
make install
ldconfig || true

echo "[*] FFmpeg installed:"
command -v ffmpeg
ffmpeg -version | head -n 3
echo "[*] CUDA filters present?"
ffmpeg -filters | grep -E 'scale_cuda|transpose_cuda'

# Move the binary to .real so we have a wrapper script to fix the arguments
mv "$PREFIX/bin/ffmpeg" "$PREFIX/bin/ffmpeg.real"

cp -- /app/ffmpeg-wrapper "$PREFIX/bin/ffmpeg"

# The successful cold build no longer needs its cloned source trees.
cd /app
rm -rf -- "$build_root"
trap - EXIT

# Hand over to your app
run_go_vod "$@"
