# tiktok-bedah

Unduh + bedah konten TikTok tanpa watermark — **0 token LLM** untuk ekstraksi.

- `scripts/extract.sh` — entry point: unduh → montage (slide/frame) → transkrip lokal faster-whisper → `content.md`
- `scripts/montage.sh`, `scripts/video_frames_montage.sh` — grid gambar deterministik (pengganti filter `tile` ffmpeg 8.1 yang rusak)
- `scripts/fw_transcribe.py` — transkrip lokal
- `references/pitfalls.md` — jebakan + cara verifikasi tanpa token

Pemakaian: `bash scripts/extract.sh "https://vt.tiktok.com/XXXX/"`

## Status

SSOT skill — di-symlink ke `~/.hermes/skills/`, `~/.claude/skills/`, `~/.cursor/skills/`,
`~/.codex/skills/`, `~/.agents/skills/`. Repo **lokal saja** (tanpa remote).
