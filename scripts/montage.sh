#!/usr/bin/env bash
# ==============================================================================
# montage.sh — grid gambar deterministik (hstack/vstack), TANPA filter `tile`.
#
#   montage.sh <out.jpg> <cols> <cellW> <cellH> <img1> [img2 ...]
#
# KENAPA bukan `tile`: di ffmpeg 8.1 filter `tile` hanya mengisi sel pertama,
# sisanya hitam — hasilnya montage "1 gambar + 11 kotak kosong" yang menipu
# (ukurannya benar, isinya kosong). Sudah diverifikasi:
#   ffmpeg -i out.jpg -vf scale=4:2 -f rawvideo -pix_fmt gray -  ->  18 0 0 0 0 0 0 0
# hstack/vstack membangun grid baris-per-baris, jadi tidak bisa setengah jadi.
#
# Sel di-pad ke ukuran seragam (aspect asli dipertahankan). Baris terakhir yang
# tidak penuh diisi kotak putih, bukan hitam.
# ==============================================================================
set -uo pipefail

OUT="${1:?usage: montage.sh <out.jpg> <cols> <cellW> <cellH> <img...>}"
COLS="${2:-}"; CW="${3:-}"; CH="${4:-}"
shift 4
IMGS=( "$@" )
N=${#IMGS[@]}
[ "$N" -eq 0 ] && { echo "montage.sh: no input images" >&2; exit 1; }
# guard: kalau argumen salah urut (mis. lupa <cols>), errornya jadi jelas
for v in COLS CW CH; do
  case "${!v}" in ''|*[!0-9]*) echo "montage.sh: $v harus angka, dapat '${!v}' — usage: montage.sh <out.jpg> <cols> <cellW> <cellH> <img...>" >&2; exit 2;; esac
done

ROWS=$(( (N + COLS - 1) / COLS ))
TOTAL=$(( ROWS * COLS ))

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

# kotak putih untuk sel sisa
ffmpeg -v error -f lavfi -i "color=white:s=${CW}x${CH}" -frames:v 1 "$TMPD/blank.jpg" -y 2>/dev/null

ARGS=(); FILTER=""
# scale ke kotak 2px lebih kecil lalu pad ke CWxCH: kalau kotaknya sama, pembulatan
# aspect bisa membuat hasil scale 1px lebih besar dari target dan `pad` menolak
# ("Padded dimensions cannot be smaller than input dimensions").
SW=$(( CW - 2 )); SH=$(( CH - 2 ))
i=0
for f in "${IMGS[@]}"; do
  ARGS+=( -i "$f" )
  FILTER+="[$i]scale=${SW}:${SH}:force_original_aspect_ratio=decrease,pad=${CW}:${CH}:(ow-iw)/2:(oh-ih)/2:white,setsar=1[s$i];"
  i=$((i+1))
done
while [ "$i" -lt "$TOTAL" ]; do
  ARGS+=( -i "$TMPD/blank.jpg" )
  FILTER+="[$i]scale=${CW}:${CH},setsar=1[s$i];"
  i=$((i+1))
done

# baris demi baris
ROW_REFS=()
for ((r=0; r<ROWS; r++)); do
  refs=""
  for ((c=0; c<COLS; c++)); do refs+="[s$((r*COLS+c))]"; done
  if [ "$COLS" -eq 1 ]; then
    FILTER+="${refs}null[row$r];"
  else
    FILTER+="${refs}hstack=inputs=${COLS}[row$r];"
  fi
  ROW_REFS+=( "[row$r]" )
done

if [ "$ROWS" -eq 1 ]; then
  LAST="[row0]"
else
  FILTER+="${ROW_REFS[*]}vstack=inputs=${ROWS}[out]"
  LAST="[out]"
fi

ffmpeg -v error "${ARGS[@]}" -filter_complex "$FILTER" -map "$LAST" -frames:v 1 -q:v 3 "$OUT" -y
[ -s "$OUT" ] || { echo "montage.sh: gagal membuat $OUT" >&2; exit 1; }
echo "$OUT"
