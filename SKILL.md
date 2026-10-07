---
name: tiktok-bedah
description: "Unduh + bedah konten TikTok tanpa watermark dalam satu perintah (0 token LLM untuk ekstraksi). Menangani video bersuara (transkrip lokal faster-whisper), video senyap/teks overlay, dan carousel foto. Termasuk ekstraksi visual via montage 1x vision call. SSOT: ~/Documents/codeX/tiktok-bedah (di-symlink ke semua agent: Hermes, Claude Code, Cursor, Codex, .agents)."
version: 1.0.0
author: Khoirul Yahya
license: MIT
platforms: [macos]
metadata:
  hermes:
    tags: [tiktok, media, download, transcript, vision, zero-token, carousel]
    related_skills: [media-content, browser-automation]
---

# tiktok-bedah — TikTok download + content extraction

**Trigger:** user kirim link TikTok (`vt.tiktok.com/...` atau `tiktok.com/@user/video/ID`) dan minta
**unduh**, **"cek isinya apa"**, **"bedah"**, **extract**, ringkas, atau transkrip.

**SSOT:** `~/Documents/codeX/tiktok-bedah/` — di-symlink ke `~/.hermes/skills/`, `~/.claude/skills/`,
`~/.cursor/skills/`, `~/.codex/skills/`, `~/.agents/skills/`. Edit di SSOT, semua agent langsung dapat.

**Tool downloader:** `~/Documents/codeX/tiktok-media-downloader/tiktok_downloader.py` (repo terpisah).

---

## Alur baku — SATU perintah, lalu SATU baca

```bash
bash ~/Documents/codeX/tiktok-bedah/scripts/extract.sh "https://vt.tiktok.com/XXXX/"
```

Yang dikerjakan script (semua lokal, **0 token LLM**):

| # | Aksi | Output |
|---|------|--------|
| 1 | unduh tanpa watermark (downloader lokal, `--no-transcribe`) | `downloads/@user/<tanggal>_<slug>_<id>/video.mp4` atau `slide_01.jpg…` |
| 2 | carousel → gabung semua slide | `slides_montage.jpg` |
| 2 | video → montage 8 frame | `frames_montage.jpg` |
| 2 | video → transkrip lokal faster-whisper `small` | `transcript.txt` |
| 3 | ringkas jadi satu file | **`content.md`** |

Script mencetak `MEDIA_DIR=`, `MONTAGE_SLIDES=`, `MONTAGE_FRAMES=`, `VIDEO=`.

### Peta script & knob

| File | Guna |
|---|---|
| `scripts/extract.sh` | entry point (semua langkah di atas) |
| `scripts/montage.sh` | grid gambar deterministik (hstack/vstack) — **pengganti filter `tile` yang rusak di ffmpeg 8.1** |
| `scripts/video_frames_montage.sh` | ambil N frame merata → 1 grid (memanggil `montage.sh`) |
| `scripts/fw_transcribe.py` | transkrip lokal; baca WAV sebagai numpy array (hindari bug PyAV) |
| `references/pitfalls.md` | semua jebakan + cara memverifikasi tanpa token |

Knob (env): `WHISPER_MODEL=small|medium|base`, `SLIDE_COLS=<n>` (paksa jumlah kolom),
`FW_PY=<path python venv>`, `TIKTOK_DL_DIR=<path repo downloader>`.

Kalau hasil vision bilang teks **tidak terbaca**, montage ulang lebih besar tanpa unduh lagi —
`montage.sh` bisa dipanggil langsung ke `slide_*.jpg` yang sudah ada (atau set `SLIDE_COLS=2`), lalu
baca grid baru. Verifikasi lokal sebelum buang token: lihat `references/pitfalls.md`.

**Langkah agen setelahnya (murah):**
1. `read_file <MEDIA_DIR>/content.md` — sudah berisi kreator, statistik, caption, transkrip, daftar file.
2. Panggil `vision_analyze` **hanya kalau perlu piksel** — **satu kali per montage**, bukan per frame/slide.
3. Kalau user minta filenya: `send_message` + `MEDIA:<path>` (satu pesan per video), baru bedah tulisannya.

---

## Kapan pakai vision, kapan cukup transkrip

| Bentuk konten | Sinyal | Yang dibaca |
|---|---|---|
| Video talking-head (bersuara) | `transcript.txt` ada isinya | transkrip → cukup. Vision **tidak** perlu. |
| Video bersuara **+ info di layar** (slide, screenshot, teks, demo aplikasi) | transkrip jalan tapi isi visual penting | transkrip **DAN** `frames_montage.jpg` (1x vision) |
| Video senyap / musik saja | transkrip kosong, `digest.md` bilang "musik latar saja" | `frames_montage.jpg` (1x vision). **Jangan** ulang whisper. |
| Carousel foto | `is_photo_carousel: true`, ada `slide_*.jpg` | `slides_montage.jpg` (1x vision). Caption biasanya cuma hashtag. |

Prompt vision yang dipakai:
> "Bacakan SEMUA teks overlay verbatim per frame (Bahasa asli). Jangan mengarang; kalau tidak ada teks tulis 'tanpa teks'."

---

## Bentuk jawaban yang diterima user

- Bahasa **Indonesia**, padat, langsung ke **isi** — bukan deskripsi tool.
- Header per video: kreator, hook/judul, durasi, 👁/❤/💬/🔁, musik.
- Video senyap: kutip overlay **verbatim** sebagai blok, lalu deskripsi visual singkat + isi caption utuh.
- Video bersuara: poin bernomor dengan **angka & contoh asli** yang disebut kreator (jangan diparafrase jadi kabur).
- Tutup dengan punchline/mindset kreator **verbatim**.
- Jangan pernah mengganti isi dengan "video ini tentang …".

---

## Kalau ada yang gagal

| Gejala | Sebab | Tindakan |
|---|---|---|
| `WARN: media tidak terunduh ulang -> pakai salinan lokal` | downloader exit 0 tapi tak mengunduh apa pun (carousel sering) | normal, script memakai folder lama dengan id sama. Cek `WARN` sebelum melapor. |
| `ERROR: downloader tidak menghasilkan media` | link mati / rate limit / carousel gagal dan tak ada salinan | ulang sekali; kalau tetap gagal lapor **apa adanya**, jangan mengarang isi |
| `ERROR: downloader exit N` | link mati / region / rate limit | cek link, ulang sekali, kalau tetap gagal lapor apa adanya |
| `WARN: ~/.venvs/fwhisper/bin/python missing` | venv belum ada | `uv venv ~/.venvs/fwhisper && uv pip install --python ~/.venvs/fwhisper/bin/python faster-whisper 'av>=14'` |
| `content.md` menyebut `(whisper gagal: …)` | error asli dari whisper | baca pesannya; kalau `0 segments` itu bukan gagal, itu video tanpa narasi |
| transkrip ngawur (`Leifel 2` = `Level 2`) | model `small` terlalu lemah | ulang `WHISPER_MODEL=medium extract.sh "<url>"` |
| `av.open() got an unexpected keyword argument 'metadata_errors'` | PyAV drift | sudah di-handle: `fw_transcribe.py` baca WAV sebagai numpy array, bukan PyAV |
| grid montage kelihatan kosong/hitam | filter `tile` ffmpeg 8.1 | jangan pakai `tile`; pakai `montage.sh`. Verifikasi: `ffmpeg -i grid.jpg -vf scale=4x3 -f rawvideo -pix_fmt gray - \| od -An -tu1` (0 = sel kosong) |
| 2 URL sekaligus | downloader cuma terima 1 positional | loop shell, atau `-b links.txt` |

---

## Hemat token — aturan mati

1. **`--no-transcribe` selalu.** Whisper `tiny` bawaan downloader mengacaukan bahasa Indonesia; pipeline ini pakai `small` via venv.
2. **Baca `content.md` dulu**, jangan `digest.md` + `metadata.json` + `caption.txt` terpisah.
3. **1 vision call per montage.** Jangan pernah 8 frame → 8 call.
4. **Jangan re-run whisper** kalau transkrip kosong — itu artinya kontennya visual.
5. **Jangan** pakai `video_analyze` (tak bisa baca file lokal) dan **jangan** `yt-dlp` untuk TikTok (sering "Unexpected response from webpage request").

Detail pitfall & riwayat: `references/pitfalls.md`.
