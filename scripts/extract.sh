#!/usr/bin/env bash
# ==============================================================================
# tiktok-bedah — one-shot TikTok downloader + content extractor (0 LLM tokens)
#
#   extract.sh <tiktok-url>
#
# All local work in one shot:
#   1. download (no watermark) via $TIKTOK_DL_DIR (default: local tiktok-media-downloader)
#   2. write content.md  <- the ONLY file the agent has to read
#   3. carousel -> slides_montage.jpg     (every slide, one image)
#      video    -> transcript.txt         (faster-whisper, local)
#                  frames_montage.jpg     (on-screen text, one image)
#
# Montages cost nothing (ffmpeg, local). Spend ONE vision call per montage,
# only when the pixels are actually needed — never one call per frame/slide.
#
# Env knobs: WHISPER_MODEL=small|medium|base   (default small)
#            FW_PY=~/.venvs/fwhisper/bin/python
# ==============================================================================
set -uo pipefail

DL="${TIKTOK_DL_DIR:-$HOME/Documents/codeX/tiktok-media-downloader}"
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FW_PY="${FW_PY:-$HOME/.venvs/fwhisper/bin/python}"
MODEL="${WHISPER_MODEL:-small}"

URL="${1:-}"
[ -z "$URL" ] && { echo "usage: extract.sh <tiktok-url>" >&2; exit 2; }

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

# ---------------------------------------------------------------- 1. download
echo "[1/3] download..." >&2
( cd "$DL" && python3 tiktok_downloader.py "$URL" --no-transcribe ) >"$TMPD/dl.log" 2>&1
rc=$?
[ $rc -ne 0 ] && { echo "ERROR: downloader exit $rc" >&2; tail -5 "$TMPD/dl.log" >&2; exit 1; }

# the downloader prints "📁 Target Folder: <abs path>" -- trust that, not mtime
DIR="$(grep -o 'Target Folder: .*' "$TMPD/dl.log" | head -1 | sed 's/^Target Folder: *//' | tr -d '\r')"
[ -z "$DIR" ] && DIR="$(grep -o '/[^ ]*/downloads/@[^ ]*/' "$TMPD/dl.log" | head -1)"
[ -z "$DIR" ] && DIR="$(ls -dt "$DL/downloads"/*/*/ 2>/dev/null | head -1)"
DIR="${DIR%/}"
[ -d "$DIR" ] || { echo "ERROR: output folder not found" >&2; tail -20 "$TMPD/dl.log" >&2; exit 1; }
echo "[1/3] -> $DIR" >&2

# The downloader ALWAYS exits 0, even when it silently downloads nothing
# (seen on photo carousels: "Mengunduh via yt-dlp fallback..." then no media at all).
# Verify real media, and reuse an earlier folder of the SAME video id if present.
shopt -s nullglob
has_media() { [ -f "$1/video.mp4" ] || { local s=( "$1"/slide_*.jpg ); [ ${#s[@]} -gt 0 ]; }; }
if ! has_media "$DIR"; then
  ID="${DIR##*_}"
  ALT=""
  for d in "$DL"/downloads/*/*_"$ID"; do
    [ -d "$d" ] && has_media "$d" && { ALT="$d"; break; }
  done
  if [ -n "$ALT" ]; then
    echo "[1/3] WARN: media tidak terunduh ulang -> pakai salinan lokal: $ALT" >&2
    DIR="$ALT"
  else
    echo "ERROR: downloader tidak menghasilkan media (carousel/video gagal)." >&2
    tail -6 "$TMPD/dl.log" >&2
    exit 1
  fi
fi

# ------------------------------------------------------------ 2a. slides
MON_SLIDES=""
shopt -s nullglob
SLIDES=( "$DIR"/slide_*.jpg )
if [ ${#SLIDES[@]} -gt 0 ]; then
  n=${#SLIDES[@]}
  cols="${SLIDE_COLS:-0}"
  [ "$cols" -eq 0 ] 2>/dev/null || cols=0
  if [ "$cols" -eq 0 ]; then
    cols=4; [ "$n" -le 9 ] && cols=3; [ "$n" -le 4 ] && cols=2; [ "$n" -le 1 ] && cols=1
  fi
  echo "[2/3] slides montage ($n slides, ${cols} kolom)..." >&2
  read -r SW SH < <(sips -g pixelWidth -g pixelHeight "${SLIDES[0]}" \
    | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w, h}')
  [ -z "${SW:-}" ] && { SW=1080; SH=736; }
  if [ "$SW" -ge "$SH" ]; then CW=480; CH=$(( 480 * SH / SW )); else CH=480; CW=$(( 480 * SW / SH )); fi
  [ "$CW" -lt 2 ] && CW=2; [ "$CH" -lt 2 ] && CH=2
  CW=$(( CW / 2 * 2 )); CH=$(( CH / 2 * 2 ))
  if bash "$SKILL_DIR/scripts/montage.sh" "$DIR/slides_montage.jpg" "$cols" "$CW" "$CH" "${SLIDES[@]}" >/dev/null 2>&1; then
    MON_SLIDES="$DIR/slides_montage.jpg"
  else
    echo "[2/3] WARN: montage slide gagal" >&2
  fi
fi

# -------------------------------------------------------------- 2b. video
VIDEO=""; MON_FRAMES=""; TRANSCRIPT=""
TR_NOTE="(tidak ada media video — carousel foto)"
[ -f "$DIR/video.mp4" ] && VIDEO="$DIR/video.mp4"

if [ -n "$VIDEO" ]; then
  TR_NOTE="(tidak ada narasi — video musik/senyap, isinya teks di frame)"
  echo "[2/3] frames montage..." >&2
  if bash "$SKILL_DIR/scripts/video_frames_montage.sh" "$VIDEO" "$TMPD/frames.jpg" 8 4 >/dev/null 2>&1; then
    cp "$TMPD/frames.jpg" "$DIR/frames_montage.jpg" && MON_FRAMES="$DIR/frames_montage.jpg"
  fi

  if [ -x "$FW_PY" ]; then
    echo "[2/3] transcribe (faster-whisper $MODEL, local)..." >&2
    if ffmpeg -v error -i "$VIDEO" -vn -ar 16000 -ac 1 -c:a pcm_s16le "$TMPD/a.wav" -y 2>/dev/null; then
      "$FW_PY" "$SKILL_DIR/scripts/fw_transcribe.py" "$TMPD/a.wav" "$MODEL" id \
        --prompt "Konten video pendek bahasa Indonesia." > "$TMPD/t.txt" 2>"$TMPD/t.err"
      if grep -qE '^\[ *[0-9]' "$TMPD/t.txt" 2>/dev/null; then
        cp "$TMPD/t.txt" "$DIR/transcript.txt"; TRANSCRIPT="$DIR/transcript.txt"
      elif grep -q "0 segments" "$TMPD/t.err" 2>/dev/null; then
        TR_NOTE="(tidak ada narasi — video musik/senyap, isinya teks di frame)"
      elif grep -qiE "traceback|error" "$TMPD/t.err" 2>/dev/null; then
        TR_NOTE="(whisper gagal: $(grep -iE 'error|Error' "$TMPD/t.err" | tail -1 | cut -c1-120))"
      fi
    fi
  else
    TR_NOTE="(venv whisper belum siap)"
    echo "[2/3] WARN: $FW_PY missing -> skip transcription." >&2
    echo "      setup: uv venv ~/.venvs/fwhisper && uv pip install --python ~/.venvs/fwhisper/bin/python faster-whisper 'av>=14'" >&2
  fi
fi

# ------------------------------------------------------------- 3. content.md
echo "[3/3] content.md..." >&2
python3 - "$DIR" "$MON_SLIDES" "$MON_FRAMES" "$TRANSCRIPT" "$TR_NOTE" <<'PY'
import json, os, sys
d, mon_slides, mon_frames, tr, tr_note = sys.argv[1:6]
m = json.load(open(os.path.join(d, "metadata.json")))
cap = (m.get("description") or "").strip()
if not cap:
    p = os.path.join(d, "caption.txt")
    if os.path.exists(p):
        cap = open(p, encoding="utf-8", errors="replace").read().strip()
L = [f"# @{m.get('author_username')} — {m.get('date_formatted')}",
     f"author: {m.get('author_name')} | id: {m.get('id')} | dur: {m.get('duration')}s | carousel: {m.get('is_photo_carousel')}",
     f"stats: views={m.get('view_count')} likes={m.get('like_count')} comments={m.get('comment_count')} shares={m.get('repost_count')}",
     f"music: {m.get('music_title')} ({m.get('music_author')})",
     f"url: {m.get('url')}",
     f"folder: {d}", "",
     "## caption", cap or "(kosong)", ""]
imgs = sorted(f for f in os.listdir(d) if f.startswith("slide_") and f.endswith(".jpg"))
if imgs:
    L += [f"## slides ({len(imgs)})", ", ".join(imgs), ""]
if mon_slides:
    L += ["## montage slides -> 1x vision_analyze", os.path.basename(mon_slides), ""]
if mon_frames:
    L += ["## frames montage (teks overlay) -> 1x vision_analyze", os.path.basename(mon_frames), ""]
if tr and os.path.exists(tr):
    txt = open(tr, encoding="utf-8", errors="replace").read().strip()
    segs = [l for l in txt.splitlines() if l.strip()]
    L += [f"## transcript ({len(segs)} segmen, faster-whisper lokal)", txt]
else:
    L += ["## transcript", tr_note]
L.append("")
open(os.path.join(d, "content.md"), "w", encoding="utf-8").write("\n".join(L))
print(os.path.join(d, "content.md"))
PY

echo "MEDIA_DIR=$DIR"
[ -n "$MON_SLIDES" ] && echo "MONTAGE_SLIDES=$MON_SLIDES"
[ -n "$MON_FRAMES" ] && echo "MONTAGE_FRAMES=$MON_FRAMES"
[ -n "$VIDEO" ]      && echo "VIDEO=$VIDEO"
exit 0
