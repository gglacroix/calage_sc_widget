#!/usr/bin/env bash
set -Eeuo pipefail

# ----------- Valeurs par défaut -----------
TRACK_URL="https://soundcloud.com/calage/exalk-hurt-feelings"
WIDGET_DURATION="30"
AUDIO_TC_IN="00:00:15"
BACKGROUND_URL="https://www.youtube.com/watch?v=ywa7QQTjSkE"
BACKGROUND_TC_IN="00:15:15"
FILE_OUT="out.mp4"

show_help() {
  cat <<EOF
Usage: $0 [options]

Options:
  -t, --track-url URL        URL de la track SoundCloud (par défaut: $TRACK_URL)
  -d, --duration SEC         Durée de la capture widget en secondes (par défaut: $WIDGET_DURATION)
  -a, --audio-tc-in TC       Timecode début audio track soundcloud (HH:MM:SS) (par défaut: $AUDIO_TC_IN)
  -b, --background-url URL   URL de la vidéo YouTube pour le background (par défaut: $BACKGROUND_URL)
  -s, --background-tc-in TC  Timecode début du background (HH:MM:SS) (par défaut: $BACKGROUND_TC_IN)
  -o, --output FILE          Nom du fichier de sortie (par défaut: $FILE_OUT)
  -h, --help                 Affiche cette aide

Exemple :
  $0 --track-url "https://soundcloud.com/user/track" \\
     --duration 30 --audio-tc-in 00:01:23 \\
     --background-url "https://youtube.com/watch?v=xxxx" \\
     --background-tc-in 00:40:10 --output out.mp4
EOF
}

# ----------- Parsing arguments -----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--track-url)        TRACK_URL="$2"; shift 2 ;;
    -d|--duration)         WIDGET_DURATION="$2"; shift 2 ;;
    -a|--audio-tc-in)      AUDIO_TC_IN="$2"; shift 2 ;;
    -b|--background-url)   BACKGROUND_URL="$2"; shift 2 ;;
    -s|--background-tc-in) BACKGROUND_TC_IN="$2"; shift 2 ;;
    -o|--output)           FILE_OUT="$2"; shift 2 ;;
    -h|--help)             show_help; exit 0 ;;
    --) shift; break ;;
    -*)
      echo "❌ Option inconnue: $1" >&2
      show_help
      exit 1
      ;;
    *) break ;;
  esac
done

# ----------- Vérification -----------
echo "🎵 Track URL        : $TRACK_URL"
echo "⏱️  Widget durée    : $WIDGET_DURATION s"
echo "🎧 Audio start      : $AUDIO_TC_IN"
echo "📺 Background URL   : $BACKGROUND_URL"
echo "⏱️  Background start: $BACKGROUND_TC_IN"
echo "💾 Fichier sortie   : $FILE_OUT"

AUDIO_DURATION="$WIDGET_DURATION"
BACKGROUND_DURATION="$WIDGET_DURATION"

# Convertir TC_OUT à partir de TC_IN + $BACKGROUND_DURATION
start_epoch=$(date -u -d "1970-01-01 ${BACKGROUND_TC_IN} UTC" +%s) || {
  echo "timecode invalide: ${BACKGROUND_TC_IN}" >&2; exit 1;
}
end_epoch=$(( start_epoch + BACKGROUND_DURATION ))
BACKGROUND_TC_OUT=$(date -u -d "@${end_epoch}" +%T)

echo "Récupération de l'ID de la track sur Soundcloud"
TRACK_ID=$(bin/yt-dlp --print "%(id)s" "$TRACK_URL")
echo "✅ l'ID de la track est '$TRACK_ID'"

# Informations serveurs web
HTML_FILE="sc_player.html"
WEBSERVER_URL="http://127.0.0.1:8000/$HTML_FILE?id=${TRACK_ID}&t=${AUDIO_TC_IN}"

# ----------- Vérifie si serveur web sur 8000 est actif, sinon lance ----------- #
if ! ss -ltn "( sport = :8000 )" | grep -q LISTEN; then
  echo "Serveur web absent → démarrage..."
  python3 -m http.server 8000 >/dev/null 2>&1 &
  WEBSERVER_PID=$!
  # stoppe proprement à la fin
  trap '[[ -n "$WEBSERVER_PID" ]] && kill "$WEBSERVER_PID" 2>/dev/null || true' EXIT
else
  echo "✅ Serveur web déjà actif sur 8000"
fi

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
echo "Démarrage du navigateur en mode headless"
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
  "$WEBSERVER_URL" & 2>/dev/null
CHROM_PID=$!
echo "✅ Navigateur démarré"

# Laisse charger la page
sleep 3

# ----------- Enregistrement ffmpeg (Widget) -----------
echo "Enregistrement du widget"
ffmpeg -y \
  -loglevel error \
  -video_size "$DISPLAY_WIDTH"x"$DISPLAY_HEIGHT" -framerate 30 \
  -f x11grab -draw_mouse 0 -i :99.0+0,0 \
  -t "$WIDGET_DURATION" \
  -vf "crop=350:344:365:850" \
  -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p \
  -c:a aac -b:a 192k "widget.mp4"
echo "✅ Widget enregistré"

# ----------- Téléchargement extrait audio -----------
echo "Téléchargement de la track depuis soundcloud"
bin/yt-dlp -x --audio-format mp3 "$TRACK_URL" -o "audio.mp3"
ffmpeg -ss "$AUDIO_TC_IN" -t "$AUDIO_DURATION" -i "audio.mp3" -acodec copy "audio_extract.mp3"
echo "✅ Téléchargé terminé"
# ----------- Téléchargement extrait vidéo background -----------
BACKGROUND_URL="${BACKGROUND_URL%%&*}"
echo "Téléchargement de l'extrait de la vidéo youtube"
bin/yt-dlp -f "bv*[ext=mp4]/bv*" \
  --download-sections "*$BACKGROUND_TC_IN-$BACKGROUND_TC_OUT" \
  -o "background.mp4" \
  "$BACKGROUND_URL"
echo "✅ Vidéo téléchargée"

# ----------- Création du fichier final -----------

echo "Enregistrement du rendu final"
ffmpeg -i background.mp4 -i widget.mp4 -i audio_extract.mp3 \
-loglevel error \
-filter_complex "\
[0:v]scale=1080:1920:force_original_aspect_ratio=increase, \
 crop=1080:1920,setsar=1,boxblur=20:1[bg]; \
[1:v]scale=720:-2:force_original_aspect_ratio=decrease,setsar=1[fg]; \
[bg][fg]overlay=(W-w)/2:(H-h)/2:shortest=1[v]" \
-map "[v]" -map 2:a -c:v libx264 -preset medium -crf 20 -c:a aac -shortest "$FILE_OUT"

echo "✅ Terminé : $FILE_OUT"

rm -rf ~/.cache/chromium
rm audio.mp3 audio_extract.mp3  background.mp4 widget.mp4
echo "✅ Supprime le cache pour les prochains exports"
