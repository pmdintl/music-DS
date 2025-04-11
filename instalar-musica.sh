#!/bin/bash

echo "🚀 Instalando reproductor de música..."

# 1. Instalar dependencias
echo "📦 Instalando dependencias..."
sudo apt update
sudo apt install -y python3 python3-pip pulseaudio vlc python3-vlc

# 2. Crear entorno de PulseAudio en consola
# echo "🔧 Configurando PulseAudio para uso en consola..."
# sudo sed -i 's/^; autospawn = yes/autospawn = yes/' /etc/pulse/client.conf || echo "autospawn = yes" | sudo tee -a /etc/pulse/client.conf
# sudo sed -i 's/^; daemon-binary =/daemon-binary =/' /etc/pulse/client.conf

# 3. Copiar aplicación
echo "🗂️ Instalando archivo musica.py..."
cat > /home/pi/musica.py << 'EOF'
# Ejemplo mínimo (reemplazar con tu lógica real)

import vlc
import json
import os
import random
import time
import psutil
import sys

CONFIG_FILE = '/home/pi/media/__Musica.json'
MUSIC_DIR = '/home/pi/media'

def load_audio_assets(config_path):
    with open(config_path, 'r') as f:
        config = json.load(f)

    audio_settings = config['settings']['audio']
    audio_enabled = audio_settings.get('enable', True)
    randomize = audio_settings.get('random', False)
    volume = audio_settings.get('volume', 100)

    if not audio_enabled:
        print("🎧 Audio desactivado en la configuración.")
        return [], volume

    audio_files = [
        asset['filename']
        for asset in config['assets']
        if not asset.get('isVideo', False)
    ]

    if randomize:
        random.shuffle(audio_files)

    return audio_files, volume

def get_interrupting_process_name():
    for proc in psutil.process_iter(['name', 'pid', 'cmdline']):
        try:
            if 'omxplayer' in proc.info['name']:
                cmdline = proc.info['cmdline']
                if '-n' in cmdline:
                    idx = cmdline.index('-n')
                    if idx + 1 < len(cmdline) and cmdline[idx + 1] == '-1':
                        continue  # omxplayer sin audio
                return f"{proc.info['name']} (PID: {proc.info['pid']})"
        except (psutil.NoSuchProcess, psutil.AccessDenied, IndexError):
            continue
    return None

def is_wget_running():
    for proc in psutil.process_iter(['name']):
        try:
            if proc.info['name'] == 'wget':
                return True
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    return False

def play_audio_playlist(audio_files, volume):
    instance = vlc.Instance('--aout=pulse')  # 👈 USANDO PULSEAUDIO
    player = instance.media_player_new()
    player.audio_set_volume(volume)

    for filename in audio_files:
        file_path = os.path.join(MUSIC_DIR, filename)
        if os.path.exists(file_path):
            print(f"\n🎵 Reproduciendo: {filename}")
            media = instance.media_new_path(file_path)
            player.set_media(media)
            player.play()
            time.sleep(1)

            paused = False
            while player.get_state() != vlc.State.Ended:
                proc_name = get_interrupting_process_name()
                if proc_name and not paused:
                    print(f"[⏸] Pausando música por: {proc_name}")
                    player.set_pause(1)
                    paused = True
                elif not proc_name and paused:
                    print("[▶️] Reanudando música")
                    player.set_pause(0)
                    paused = False

                if is_wget_running():
                    print("📥 wget detectado. Esperando que finalice...")
                    while is_wget_running():
                        time.sleep(1)
                    print("✅ wget finalizó. Reiniciando música...")
                    os.execv(sys.executable, ['python3'] + sys.argv)

                time.sleep(1)
        else:
            print(f"[⚠️] Archivo no encontrado: {file_path}")

if __name__ == "__main__":
    try:
        audio_list, volume = load_audio_assets(CONFIG_FILE)
        if audio_list:
            play_audio_playlist(audio_list, volume)
        else:
            print("No hay pistas de audio para reproducir.")
    except KeyboardInterrupt:
        print("\n🛑 Reproducción interrumpida por el usuario.")

chmod +x /home/pi/musica.py

# 4. Crear script de inicio
echo "🛠️ Creando script de inicio..."
cat > /home/pi/iniciar-musica.sh << 'EOF'
#!/bin/bash

export XDG_RUNTIME_DIR="/run/user/$(id -u)"

if ! pgrep -x "pulseaudio" > /dev/null; then
  pulseaudio --start
  sleep 2
fi

/usr/bin/python3 /home/pi/musica.py >> /home/pi/musica.log 2>&1
EOF

chmod +x /home/pi/iniciar-musica.sh

# 5. Crear servicio systemd
echo "⚙️ Creando servicio systemd..."
sudo tee /etc/systemd/system/musica.service > /dev/null << EOF
[Unit]
Description=Reproductor de música con PulseAudio en consola
After=network.target sound.target
Wants=network.target sound.target

[Service]
User=pi
ExecStart=/home/pi/iniciar-musica.sh
Environment=XDG_RUNTIME_DIR=/run/user/1000
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 6. Activar servicio
echo "✅ Activando servicio..."
sudo systemctl daemon-reload
sudo systemctl enable musica.service
sudo systemctl start musica.service

echo "✅ Instalación completada. Verifica con: systemctl status musica.service"
