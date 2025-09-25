#!/usr/bin/env bash
set -Eeuo pipefail

# ----------- Paramètres -----------
TRACK_URL="${1:-https://soundcloud.com/calage/exalk-hurt-feelings}"
VIDEO_DURATION="${2:-30}"
AUDIO_TC_IN="${3:-00:03:30}"
AUDIO_DURATION="${4:-30}"
FILE_OUT="${5:-out.mp4}"
BACKGROUND_URL="${6:-https://www.youtube.com/watch?v=ywa7QQTjSkE}"
BACKGROUND_DURATION=30
BACKGROUND_TC_IN="${7:-00:38:35}"

start_epoch=$(date -u -d "1970-01-01 ${BACKGROUND_TC_IN} UTC" +%s) || {
  echo "timecode invalide: ${BACKGROUND_TC_IN}" >&2; exit 1;
}
end_epoch=$(( start_epoch + BACKGROUND_DURATION ))
BACKGROUND_TC_OUT=$(date -u -d "@${end_epoch}" +%T)

TRACK_ID=$(bin/yt-dlp --print "%(id)s" "$TRACK_URL")

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

# ----------- Enregistrement ffmpeg (Widget) -----------
ffmpeg -y \
  -video_size "$DISPLAY_WIDTH"x"$DISPLAY_HEIGHT" -framerate 30 \
  -f x11grab -draw_mouse 0 -i :99.0+0,0 \
  -t "$VIDEO_DURATION" \
  -vf "crop=350:344:365:866" \
  -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p \
  -c:a aac -b:a 192k "widget.mp4"


# ----------- Téléchargement extrait audio -----------

bin/yt-dlp -x --audio-format mp3 "$TRACK_URL" -o "audio.mp3"
ffmpeg -ss "$AUDIO_TC_IN" -t "$AUDIO_DURATION" -i "audio.mp3" -acodec copy "audio_extract.mp3"

# ----------- Téléchargement extrait vidéo background -----------

bin/yt-dlp -f "bv*[ext=mp4]/bv*" \
  --download-sections "*$BACKGROUND_TC_IN-$BACKGROUND_TC_OUT" \
  -o "background.mp4" \
  "$BACKGROUND_URL"

# ----------- Création du fichier final -----------

ffmpeg -i background.mp4 -i widget.mp4 -i audio_extract.mp3 \
-filter_complex "\
[0:v]scale=1080:1920:force_original_aspect_ratio=increase, \
 crop=1080:1920,setsar=1,boxblur=20:1[bg]; \
[1:v]scale=900:-2:force_original_aspect_ratio=decrease,setsar=1[fg]; \
[bg][fg]overlay=(W-w)/2:(H-h)/2:shortest=1[v]" \
-map "[v]" -map 2:a -c:v libx264 -preset medium -crf 20 -c:a aac -shortest "$FILE_OUT"

echo "✅ Terminé : $FILE_OUT"

rm -rf ~/.cache/chromium
rm audio.mp3
echo "✅ Supprime le cache pour les prochains exports"
