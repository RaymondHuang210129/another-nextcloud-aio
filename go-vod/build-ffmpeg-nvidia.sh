#!/usr/bin/env bash
set -euo pipefail

# --- Versions/flags you can tweak ---
FFMPEG_TAG="n8.0"                 # FFmpeg release tag
CUDA_TOOLKIT_PKG="cuda-toolkit-13-0"   # CUDA 13.0 toolkit meta-package
NVCC_SM_FLAGS="-gencode=arch=compute_90,code=sm_90"  # use 'sm_89' if your nvcc rejects 90
PREFIX="/usr/local"
# ------------------------------------

# if ffmpeg.real exists, the ffmpeg has been built already; skip
if [[ -f "$PREFIX/bin/ffmpeg.real" ]]; then
  echo "[*] FFmpeg with NVIDIA support already installed, skipping build."
  cp /app/ffmpeg-wrapper $PREFIX/bin/ffmpeg
  exec /app/entrypoint.sh "$@"
fi

export DEBIAN_FRONTEND=noninteractive

echo "[*] Installing build prerequisites"
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl git pkg-config build-essential yasm nasm \
  autoconf automake libtool cmake \
  libx264-dev

echo "[*] Installing CUDA 13.0 toolkit (nvcc)"
tmpdeb="$(mktemp)"
curl -fsSL \
  https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb \
  -o "$tmpdeb"
dpkg -i "$tmpdeb"
rm -f "$tmpdeb"
apt-get update
apt-get install -y --no-install-recommends "$CUDA_TOOLKIT_PKG"

export CUDA_HOME=/usr/local/cuda
export PATH="$CUDA_HOME/bin:${PATH}"
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}"
hash -r

# Sanity: show nvcc and bail if missing
echo "[*] nvcc version:"
nvcc --version || { echo "ERROR: nvcc not found on PATH"; exit 1; }

echo "[*] Installing NVENC/NVDEC headers (nv-codec-headers)"
rm -rf /tmp/nv-codec-headers
git clone --depth=1 https://github.com/FFmpeg/nv-codec-headers /tmp/nv-codec-headers
make -C /tmp/nv-codec-headers install

echo "[*] Fetching FFmpeg ${FFMPEG_TAG}"
rm -rf /tmp/ffmpeg
git clone https://github.com/FFmpeg/FFmpeg /tmp/ffmpeg
cd /tmp/ffmpeg

# Add a patch made by Faeez Kadiri to enable transpose_cuda
echo "[*] Applying transpose_cuda patch"
git checkout "$FFMPEG_TAG"
curl https://patchwork.ffmpeg.org/project/ffmpeg/patch/20250605110938.686643-1-f1k2faeez@gmail.com/raw/ > /tmp/patch
git apply --3way /tmp/patch

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
ffmpeg -filters | grep -E '^ T.*scale_cuda' || true

# Move the binary to .real so we have a wrapper script to fix the arguments
mv $PREFIX/bin/ffmpeg $PREFIX/bin/ffmpeg.real

cp /app/ffmpeg-wrapper $PREFIX/bin/ffmpeg

# Hand over to your app
exec /app/entrypoint.sh "$@"
