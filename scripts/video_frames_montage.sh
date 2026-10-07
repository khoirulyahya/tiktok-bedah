#!/usr/bin/env bash
# ==============================================================================
# video_frames_montage.sh — ambil N frame merata dari video -> ONE grid image.
#
#   video_frames_montage.sh <video> <out.jpg> [n_frames] [cols]
#
# Video senyap / musik-only menaruh SELURUH isinya sebagai teks di frame.
# Satu grid = satu vision call; jangan pernah N frame -> N vision call.
#
# Grid dibangun oleh montage.sh (hstack/vstack). JANGAN pakai filter `tile`:
# di ffmpeg 8.1 `tile` hanya mengisi sel pertama (sisanya hitam) dan hasilnya
# kelihatan "berhasil" padahal isinya cuma 1 frame.
# ==============================================================================
set -uo pipefail

V="${1:?usage: video_frames_montage.sh <video> <out.jpg> [n_frames] [cols]}"
OUT="${2:?}"
N="${3:-8}"
COLS="${4:-4}"
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

DUR="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$V")"
FPS="$(awk -v n="$N" -v d="$DUR" 'BEGIN{ if (d <= 0) d = 1; printf "%.6f", n / d }')"
ffmpeg -v error -i "$V" -vf "fps=${FPS}" -frames:v "$N" -q:v 4 "$TMPD/f_%02d.jpg" -y
[ -e "$TMPD/f_01.jpg" ] || { echo "gagal ekstrak frame dari $V" >&2; exit 1; }

# ukuran sel mengikuti aspect frame (video vertikal -> sel tinggi, bukan kotak)
read -r FW FH < <(sips -g pixelWidth -g pixelHeight "$TMPD/f_01.jpg" \
  | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w, h}')
if [ "${FW:-1}" -ge "${FH:-1}" ]; then CW=480; CH=$(( 480 * FH / FW )); else CH=480; CW=$(( 480 * FW / FH )); fi
[ "$CW" -lt 2 ] && CW=2; [ "$CH" -lt 2 ] && CH=2
CW=$(( CW / 2 * 2 )); CH=$(( CH / 2 * 2 ))

bash "$SKILL_DIR/scripts/montage.sh" "$OUT" "$COLS" "$CW" "$CH" "$TMPD"/f_*.jpg
