# Vendored patch provenance

## `ffmpeg-transpose-cuda.patch`

- **Author:** Faeez Kadiri <f1k2faeez@gmail.com>
- **Original subject:** `[FFmpeg-devel] avfilter: add CUDA-accelerated transpose filter`
- **Submitted:** 2025-06-05
- **FFmpeg Patchwork:** https://patchwork.ffmpeg.org/project/ffmpeg/patch/20250605110938.686643-1-f1k2faeez@gmail.com/
- **Patchwork ID:** 55559
- **Message-ID:** `20250605110938.686643-1-f1k2faeez@gmail.com`
- **Vendored SHA-256:** `f59327a7468e9c5680d23fbb28305559d03dc6f4a1f1a7ca2996437c1bc74472`

This repository does not claim authorship of the patch. It is vendored so the
custom FFmpeg build uses reviewable, reproducible input instead of downloading
an unverified patch during every cold build.

The patch was submitted before the pinned FFmpeg n8.0 commit. Its cosmetic
`Changelog` hunk no longer applies, so the build excludes that hunk while
applying all functional source and documentation hunks. The vendored patch
itself is retained unchanged.
