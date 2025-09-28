#!/usr/bin/env bash
set -Eeuo pipefail

# =========================
#  record_headless_mac.sh
#  macOS (Option 2) – sans Xvfb
#  Dépendances : ffmpeg, yt-dlp, python3, Chrome/Chromium
#  (brew install ffmpeg yt-dlp; Chrome est recommandé)
# =========================

# ----------- Valeurs par défaut -----------
TRACK_URL="https://soundcloud.com/calage/exalk-hurt-feelings"
WIDGET_DURATION="30"
AUDIO_TC_IN="00:00:15"
BACKGROUND_URL="https://www.youtube.com/watch?v=ywa7QQTjSkE"
BACKGROUND_TC_IN="00:15:15"
FILE_OUT="out.mp4"

# Résolution cible de la fenêtre Chrome qu’on placera en (0,0)
DISPLAY_WIDTH="1080"
DISPLAY_HEIGHT="1920"

# Indice d’écran pour avfoundation (0 = écran principal en général ; sur certains Macs c’est 1)
DISPLAY_INDEX="${DISPLAY_INDEX:-0}"

# Zone à rogner (pixels) pour extraire le widget depuis la capture d’écran complète
# Adapte ces valeurs si le cadre n’est pas correct sur TON écran.
CROP_W="${CROP_W:-350}"
CROP_H="${CROP_H:-344}"
CROP_X="${CROP_X:-365}"
CROP_Y="${CROP_Y:-850}"

HTML_FILE="sc_player.html"
WEBSERVER_PORT="8000"

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

Avancé (facultatif) :
  --display-index N          Écran utilisé pour la capture avfoundation (défaut: $DISPLAY_INDEX)
  --crop WxH+X+Y             Zone de crop du widget (ex: 350x344+365+850)
  --size WxH                 Taille de fenêtre Chrome (ex: 1080x1920)

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
    --display-index)       DISPLAY_INDEX="$2"; shift 2 ;;
    --crop)
      IFS='x+ ' read -r CROP_W CROP_H CROP_X CROP_Y <<<"$(echo "$2" | sed -E 's/x/ /; s/\+/ /; s/\+/ /')"
      shift 2
      ;;
    --size)
      IFS='x' read -r DISPLAY_WIDTH DISPLAY_HEIGHT <<<"$2"
      shift 2
      ;;
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

# ----------- Vérifs & prérequis -----------
need() { command -v "$1" >/dev/null 2>&1 || { echo "❌ '$1' manquant. Installe-le (brew install $1)."; exit 1; }; }
need python3
need ffmpeg
need yt-dlp

# Détecter binaire Chrome/Chromium et le lancer avec PID traçable
BROWSER_BIN=""
for p in \
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  "/Applications/Chromium.app/Contents/MacOS/Chromium" \
  "$(command -v google-chrome || true)" \
  "$(command -v chromium || true)"; do
  [[ -x "$p" ]] && BROWSER_BIN="$p" && break
done
if [[ -z "$BROWSER_BIN" ]]; then
  echo "❌ Chrome/Chromium introuvable. Installe Google Chrome (recommandé)."
  exit 1
fi

# Avertissement permissions macOS
echo "⚠️  macOS demandera l'autorisation de 'Screen Recording' pour ffmpeg (Terminal/iTerm)."
echo "    Va dans: Préférences Système → Sécurité et confidentialité → Enregistrement de l'écran."

# ----------- Affichage paramètres -----------
echo "🎵 Track URL        : $TRACK_URL"
echo "⏱️  Widget durée    : $WIDGET_DURATION s"
echo "🎧 Audio start      : $AUDIO_TC_IN"
echo "📺 Background URL   : $BACKGROUND_URL"
echo "⏱️  Background start: $BACKGROUND_TC_IN"
echo "💾 Fichier sortie   : $FILE_OUT"
echo "🖥️  Capture écran   : avfoundation display index=$DISPLAY_INDEX"
echo "🪟 Fenêtre Chrome   : ${DISPLAY_WIDTH}x${DISPLAY_HEIGHT} @ (0,0)"
echo "✂️  Crop widget      : ${CROP_W}x${CROP_H}+${CROP_X}+${CROP_Y}"

AUDIO_DURATION="$WIDGET_DURATION"
BACKGROUND_DURATION="$WIDGET_DURATION"

# ----------- Utilitaires -----------

# Calcul BACKGROUND_TC_OUT en Python (portable)
py_tc_out() {
  local tc_in="$1" dur="$2"
  python3 - <<'PY'
import sys, datetime as dt
tc_in = sys.argv[1]
dur   = int(sys.argv[2])
h,m,s = map(int, tc_in.split(':'))
t0 = dt.datetime(1970,1,1, h, m, s)
t1 = t0 + dt.timedelta(seconds=dur)
print(t1.strftime("%H:%M:%S"))
PY
  # pass args
} > /tmp/.tc_out.txt 2>/dev/null <<EOF
$BACKGROUND_TC_IN
$BACKGROUND_DURATION
EOF
BACKGROUND_TC_OUT="$(cat /tmp/.tc_out.txt)"

# Check si serveur 8000 écoute; sinon le démarrer
if ! lsof -iTCP:"$WEBSERVER_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "🌐 Démarrage du serveur web local sur :$WEBSERVER_PORT…"
  ( python3 -m http.server "$WEBSERVER_PORT" >/dev/null 2>&1 & echo $! > /tmp/.pyhttpserver.pid )
  trap '[[ -f /tmp/.pyhttpserver.pid ]] && kill "$(cat /tmp/.pyhttpserver.pid)" 2>/dev/null || true' EXIT
else
  echo "✅ Serveur web déjà actif sur $WEBSERVER_PORT"
fi

# ----------- Récup ID SoundCloud ----------- #
echo "Récupération de l'ID de la track sur SoundCloud…"
TRACK_ID="$(yt-dlp --print "%(id)s" "$TRACK_URL")"
echo "✅ ID track: $TRACK_ID"

WEBSERVER_URL="http://127.0.0.1:${WEBSERVER_PORT}/${HTML_FILE}?id=${TRACK_ID}&t=${AUDIO_TC_IN}"

# ----------- Lancer Chrome normal (pas headless) ----------- #
# On fixe la taille & position pour avoir un cadrage reproductible pour le crop.
echo "Démarrage du navigateur…"
"$BROWSER_BIN" \
  --new-window \
  --disable-features=TranslateUI \
  --disable-infobars \
  --autoplay-policy=no-user-gesture-required \
  --window-position=0,0 \
  --window-size="${DISPLAY_WIDTH},${DISPLAY_HEIGHT}" \
  "$WEBSERVER_URL" >/dev/null 2>&1 &
CHROME_PID=$!

# Donne 3s pour charger la page et stabiliser la fenêtre
sleep 3

# Si la fenêtre n'est pas correctement dimensionnée, on force via AppleScript (best effort)
# Nécessite d'autoriser "Terminal" dans "Accessibilité" si macOS le demande.
osascript >/dev/null 2>&1 <<OSA || true
tell application "System Events"
  set frontApp to name of first process whose frontmost is true
end tell
if frontApp is "Google Chrome" or frontApp is "Chromium" then
  tell application frontApp
    activate
    set bounds of front window to {0, 0, $DISPLAY_WIDTH, $DISPLAY_HEIGHT}
  end tell
end if
OSA

# ----------- Enregistrement ffmpeg (Widget) -----------
echo "🎬 Capture du widget (écran=$DISPLAY_INDEX) pendant ${WIDGET_DURATION}s…"
ffmpeg -y \
  -loglevel error \
  -f avfoundation -framerate 30 -video_size "${DISPLAY_WIDTH}x${DISPLAY_HEIGHT}" \
  -i "${DISPLAY_INDEX}:none" \
  -t "$WIDGET_DURATION" \
  -vf "crop=${CROP_W}:${CROP_H}:${CROP_X}:${CROP_Y}" \
  -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p \
  -c:a aac -b:a 192k "widget.mp4"
echo "✅ Widget enregistré"

# ----------- Audio SoundCloud -----------
echo "Téléchargement audio SoundCloud + découpage…"
yt-dlp -x --audio-format mp3 "$TRACK_URL" -o "audio.mp3"
ffmpeg -y -ss "$AUDIO_TC_IN" -t "$AUDIO_DURATION" -i "audio.mp3" -acodec copy "audio_extract.mp3"
echo "✅ Audio OK"

# ----------- Vidéo YouTube (background) -----------
BACKGROUND_URL="${BACKGROUND_URL%%&*}"
echo "Téléchargement extrait vidéo background YouTube…"
yt-dlp -f "bv*[ext=mp4]/bv*" \
  --download-sections "*$BACKGROUND_TC_IN-$BACKGROUND_TC_OUT" \
  -o "background.mp4" \
  "$BACKGROUND_URL"
echo "✅ Vidéo background OK"

# ----------- Composition finale -----------
echo "🎛️  Composition finale…"
ffmpeg -y -i background.mp4 -i widget.mp4 -i audio_extract.mp3 \
  -loglevel error \
  -filter_complex "\
[0:v]scale=${DISPLAY_WIDTH}:${DISPLAY_HEIGHT}:force_original_aspect_ratio=increase, \
 crop=${DISPLAY_WIDTH}:${DISPLAY_HEIGHT},setsar=1,boxblur=20:1[bg]; \
[1:v]scale=720:-2:force_original_aspect_ratio=decrease,setsar=1[fg]; \
[bg][fg]overlay=(W-w)/2:(H-h)/2:shortest=1[v]" \
  -map "[v]" -map 2:a -c:v libx264 -preset medium -crf 20 -c:a aac -shortest "$FILE_OUT"

echo "✅ Terminé : $FILE_OUT"

# ----------- Nettoyage & sortie propre ----------- #
# Fermer la fenêtre Chrome ouverte par le script (best effort)
if ps -p "${CHROME_PID}" >/dev/null 2>&1; then
  kill "${CHROME_PID}" 2>/dev/null || true
fi

rm -f audio.mp3 audio_extract.mp3 background.mp4 widget.mp4 /tmp/.tc_out.txt
echo "🧹 Nettoyage OK – prêt pour un nouvel export."

