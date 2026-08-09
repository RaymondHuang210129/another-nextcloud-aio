# Reproducible HEVC HLS transcoder

The transcoder image is built from the official Memories source at the pinned
`go-vod/0.2.6` commit `321d93cbafed298c6c3c662e41b8c622c6f8e955`.
`Containerfile` clones that commit, applies
`patches/go-vod-0.2.6-custom.patch`, runs the Go tests, and compiles a static
`/app/go-vod-custom` binary. The image also contains the local FFmpeg wrapper,
startup script, and vendored `transpose_cuda` patch.

The `custom-src/` tree and `bin/go-vod-custom` are retained only as a working
reference and convenience output. Container builds do not read either one.

When `GO_VOD_HLS_CODEC=hevc` is present, HLS output uses:

- `hevc_nvenc` with Main-profile, 8-bit NV12 video
- fMP4/CMAF-style `.m4s` segments and one init segment per rendition
- `hvc1` sample-entry and RFC 6381 codec signaling
- the wrapper's 12 Mbps target, 16 Mbps peak, and 32 Mbps VBV buffer
- forced IDR boundaries for reliable adaptive-quality switching
- a corrected static VOD playlist for short tails and HEVC fragment variance
- H.264 MP4 output for Live Photos; the HEVC switch affects HLS only

## Rebuild and deploy

From the repository root:

```bash
./go-vod/rebuild-transcoder.sh
```

This builds `localhost/nextcloud-memories-transcoder:go-vod-0.2.6-hevc`,
recreates only the `memories-go-vod` service, and verifies the deployed binary.
Podman layer caching makes later rebuilds fast.

To build only the patched Go binary into `go-vod/bin/`:

```bash
./go-vod/build-go-vod-custom.sh
```

To inspect or refresh the patch intentionally:

1. Check out the pinned commit from `https://github.com/pulsejet/memories.git`.
2. Apply `patches/go-vod-0.2.6-custom.patch` at the repository root.
3. Modify and test `go-vod/` in that checkout.
4. Regenerate the patch against the same pinned commit.

Do not silently change the commit in `Containerfile`: a Memories upgrade may
change the go-vod protocol version. Update the commit, patch, image tag, and
this document together.

## FFmpeg cache

`go-vod/bin/` remains mounted at `/usr/local/bin`. It caches the expensive
custom FFmpeg build and stores `go-vod-hls-codec`. If the cache is empty, the
container builds FFmpeg from pinned commits and applies the vendored
`patches/ffmpeg-transpose-cuda.patch`. Deleting `bin/ffmpeg.real`
intentionally forces that rebuild on the next container start.

## Rollback

Switch immediately to the stock go-vod H.264/MPEG-TS path:

```bash
./go-vod/set-hls-codec.sh h264
```

Switch back to the local HEVC/fMP4 server:

```bash
./go-vod/set-hls-codec.sh hevc
```

The helper writes `go-vod/bin/go-vod-hls-codec`, which overrides the compose
environment and restarts only `nextcloud-memories-transcoder`. Delete the
override file to use `GO_VOD_HLS_CODEC` from compose again.
