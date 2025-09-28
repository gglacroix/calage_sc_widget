# calage_sc_widget

Télécharger le dépôt :
git clone git@github.com:gglacroix/calage_sc_widget.git

Les paquets suivants doivent être installés : 
sudo apt install -y python3 chromium ffmpeg xvfb

Pour lancer un enregistrement, se placer dans le répertoire du dépôt et lancer la commande suivante : 
cd calage_sc_widget.git

./record_headless.sh --track-url "https://soundcloud.com/calage/exalk-hurt-feelings" \
     --audio-tc-in 00:02:50 \
     --background-url "https://www.youtube.com/watch?v=L7he8tHtPXM" \
     --background-tc-in 00:35:40
