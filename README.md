# calage_sc_widget

# 🎶 Calage SC Widget

Ce projet permet de générer une vidéo **Picture-in-Picture** avec un widget SoundCloud incrusté sur un fond vidéo (YouTube) et synchronisé avec un timecode précis.  
L’ensemble s’appuie sur `chromium` en mode headless et `ffmpeg`.

---

## 📥 Installation

Cloner le dépôt :

```bash
git clone git@github.com:gglacroix/calage_sc_widget.git
cd calage_sc_widget.git

Installer les dépendances nécessaires :

```bash
sudo apt update
sudo apt install -y python3 chromium ffmpeg xvfb

Depuis le répertoire du dépôt, lancer un enregistrement avec :

```bash
./record_headless.sh \
  --track-url "https://soundcloud.com/calage/exalk-hurt-feelings" \
  --audio-tc-in 00:02:50 \
  --background-url "https://www.youtube.com/watch?v=L7he8tHtPXM" \
  --background-tc-in 00:35:40

