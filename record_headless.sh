#!/usr/bin/env bash
set -Eeuo pipefail

# ----------- Paramètres -----------
TRACK_ID="${1:-2113654521}"
DUR="${2:-30}"
OUT="${3:-out.mp4}"

# Informations serveurs web
HTML_FILE="sc_player.html"
WEBSERVER_URL="http://127.0.0.1:8000/$HTML_FILE"

# Mise à jour de la track ID dans le fichier HTML

sed -i -E "s|(%253A)[0-9]+(&color)|\1${TRACK_ID}\2|g" "$HTML_FILE"

# Affichage navigateur
DISPLAY_WIDTH="1080"
DISPLAY_HEIGHT="1920"
DISPLAY_NUM="${DISPLAY_NUM:-99}"

XVFB_PID=""; CHROM_PID=""; OPENBOX_PID=""

cleanup() {
  [[ -n "$CHROM_PID"   ]] && kill "$CHROM_PID"   2>/dev/null || true
  [[ -n "$OPENBOX_PID" ]] && kill "$OPENBOX_PID" 2>/dev/null || true
  [[ -n "$XVFB_PID"    ]] && kill "$XVFB_PID"    2>/dev/null || true
}
trap cleanup EXIT

# ----------- Xvfb -----------
export DISPLAY=":${DISPLAY_NUM}"
Xvfb "$DISPLAY" -screen 0 "${DISPLAY_WIDTH}x${DISPLAY_HEIGHT}x24" -nolisten tcp -dpi 96 &
XVFB_PID=$!
sleep 0.7

# ----------- Lancer Chromium (forcer X11 + rendu software) -----------
chromium \
  --no-sandbox \
  --ozone-platform=x11 \
  --disable-gpu \
  --use-gl=swiftshader \
  --in-process-gpu \
  --disable-gpu-compositing \
  --disable-features=VizDisplayCompositor \
  --start-maximized \
  --window-position=0,0 \
  --window-size="${DISPLAY_WIDTH},${DISPLAY_HEIGHT}" \
  --autoplay-policy=no-user-gesture-required \
  --noerrdialogs \
  --disable-infobars \
  "$WEBSERVER_URL" &
CHROM_PID=$!

# Laisse charger la page
sleep 3

# ----------- Enregistrement ffmpeg (X11 + Pulse monitor) -----------
ffmpeg -y \
  -video_size "$DISPLAY_WIDTH"x"$DISPLAY_HEIGHT" -framerate 30 \
  -f x11grab -draw_mouse 0 -i :99.0+0,0 \
  -f pulse -thread_queue_size 1024 -i virt_sink.monitor \
  -t "$DUR" \
  -vf "crop=350:344:365:866" \
  -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p \
  -c:a aac -b:a 192k "$OUT"


echo "✅ Terminé : $OUT"

rm -rf ~/.cache/chromium
echo "✅ Supprime le cache pour les prochains exports"
