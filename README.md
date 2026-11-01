# tiktok-bedah

Local-first TikTok **download + content extraction** lab. One command turns a TikTok URL into a folder with media, a frame/slide montage, an optional local transcript, and a single `content.md` summary.

**0 LLM tokens for extraction.** Download, FFmpeg montage, and faster-whisper all run on your machine. Vision/LLM is optional afterward (one call per montage if you need on-screen text).

This is a personal toolkit / agent skill, not a commercial studio product.

## Quick start

```bash
# Requires: ffmpeg, a TikTok downloader that writes metadata.json + media,
# and (optional) a faster-whisper venv for transcripts.
export TIKTOK_DL_DIR=/path/to/your-tiktok-downloader
export FW_PY=$HOME/.venvs/fwhisper/bin/python   # optional

bash scripts/extract.sh "https://vt.tiktok.com/XXXX/"
```

Happy path output (printed by the script):

```text
MEDIA_DIR=.../downloads/@user/<date>_<slug>_<id>
MONTAGE_FRAMES=.../frames_montage.jpg   # or MONTAGE_SLIDES for carousels
VIDEO=.../video.mp4                     # when present
```

Then read `$MEDIA_DIR/content.md`.

## What it does

| Step | Local tool | Result |
|------|------------|--------|
| 1 | TikTok downloader (`TIKTOK_DL_DIR`) | `video.mp4` or `slide_*.jpg` + `metadata.json` |
| 2a | `scripts/montage.sh` / `video_frames_montage.sh` | deterministic image grid (avoids broken ffmpeg `tile` on 8.1) |
| 2b | `scripts/fw_transcribe.py` + faster-whisper | `transcript.txt` when speech exists |
| 3 | inline Python in `extract.sh` | **`content.md`** (creator, stats, caption, transcript pointers) |

## Layout

- `scripts/extract.sh` — entry point
- `scripts/montage.sh`, `scripts/video_frames_montage.sh` — deterministic grids
- `scripts/fw_transcribe.py` — local transcription helper
- `references/pitfalls.md` — failure modes and zero-token verification tips
- `SKILL.md` — agent skill contract (Hermes / Claude / Cursor / Codex)

## Requirements

- macOS-oriented today (`sips` used for slide sizing). Linux port welcome.
- `ffmpeg` / `ffprobe`
- Python 3
- Separate TikTok downloader repo that exposes `tiktok_downloader.py <url> --no-transcribe` and writes a `Target Folder:` line plus `metadata.json`. Set `TIKTOK_DL_DIR`.
- Optional: faster-whisper venv (`FW_PY`), models `small` / `base` / `medium` via `WHISPER_MODEL`

## What is NOT in this repo

- No API keys, cookies, or session stores
- No client / brand footage
- No downloaded TikTok media (gitignored: `*.mp4`, montages, logs)
- No cloud video generators (Veo/Sora/etc.)
- Downloader implementation lives in a separate local tool (not bundled here)

## Env knobs

- `TIKTOK_DL_DIR` — path to downloader repo (required for step 1)
- `FW_PY` — Python with faster-whisper (optional)
- `WHISPER_MODEL` — `small` (default) / `base` / `medium`
- `SLIDE_COLS` — force carousel grid columns

## License

MIT — see [LICENSE](LICENSE).

## Author

Muhammad Khoirul Yahya · [GitHub](https://github.com/khoirulyahya) · [Portfolio](https://khoirulyahya.github.io/)
