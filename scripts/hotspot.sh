#!/bin/bash

export RCLONE_CONFIG=/home/lsd/.config/rclone/rclone.conf
export HOME=/home/lsd

LOG_PATH="/home/lsd/log_sistema.txt"
CONFIG_PATH="/home/lsd/config_general.txt"
CONFIG_HORARIOS="/home/lsd/config_horarios.txt"

log() {
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M')
    echo "[$TIMESTAMP] $1" | tee -a "$LOG_PATH"
}

FIRST_START=$(awk -F' = ' '/FIRST_START/{print $2}' "$CONFIG_PATH" | tr -d '\r')

sleep 15

# Chequear si fue activado por botón
BUTTON_FLAG=$(python3 -c "
import RPi.GPIO as GPIO
GPIO.setmode(GPIO.BCM)
GPIO.setwarnings(False)
GPIO.setup(24, GPIO.IN, pull_up_down=GPIO.PUD_DOWN)
val = GPIO.input(24)
GPIO.cleanup()
print(val)
")

if [ "$FIRST_START" != "TRUE" ] && [ "$BUTTON_FLAG" != "1" ]; then
    exit 0
fi

if [ "$BUTTON_FLAG" = "1" ]; then
python3 -c "
import RPi.GPIO as GPIO
GPIO.setmode(GPIO.BCM)
GPIO.setwarnings(False)
GPIO.setup(25, GPIO.OUT)
GPIO.output(25, GPIO.LOW)
import time; time.sleep(0.1)
GPIO.output(25, GPIO.HIGH)
GPIO.cleanup()
"
    sed -i 's/FIRST_START = .*/FIRST_START = TRUE/' "$CONFIG_PATH"
    FIRST_START="TRUE"
fi

if [ "$FIRST_START" != "TRUE" ]; then
    exit 0
fi

sudo rfkill unblock wifi
sleep 2
sudo nmcli radio wifi on
sleep 2

levantar_hotspot() {
    sudo ip addr flush dev wlan0
    sleep 1
    sudo pkill dnsmasq 2>/dev/null
    sleep 2
    sudo nmcli device wifi hotspot ifname wlan0 ssid LSD-Tector password birdnet123 con-name Hotspot
    sleep 3
    sudo nmcli connection modify Hotspot ipv4.addresses 192.168.4.1/24 ipv4.method shared
    sudo nmcli connection up Hotspot
}

levantar_hotspot
if [ $? -ne 0 ]; then
    log "Primer intento fallido. Reintentando hotspot..."
    sleep 5
    levantar_hotspot
    if [ $? -ne 0 ]; then
        log "Error: no se pudo levantar el hotspot después de dos intentos."
        exit 1
    fi
fi


sleep 5

IP_HOTSPOT=$(ip addr show wlan0 | grep -oP 'inet \K[\d.]+')
log "Hotspot activo (IP: $IP_HOTSPOT)"

# Lanzar portal y capturar exit code
sudo python3 /home/lsd/portal_configuracion.py
EXIT_CODE=$?

if [ $EXIT_CODE -eq 2 ]; then
    log "Sin respuesta en el portal tras 15 minutos. Apagando para conservar batería."
    python3 -c "
import sys
sys.path.append('/home/lsd/BirdNET-Pi/PiJuice/Software/Source')
from pijuice import PiJuice
pj = PiJuice(1, 0x14)
pj.power.SetPowerOff(30)
"
    sudo poweroff
    exit 0
fi

if [ $EXIT_CODE -ne 0 ]; then
    log "Conexión fallida. Hotspot reactivado, esperando nuevas credenciales."
    exit 1
fi

# --- CONEXION EXITOSA ---

# Sincronizar hora
sudo systemctl restart systemd-timesyncd
sleep 5
python3 /home/lsd/sync_pijuice_rtc.py

SSID_CONECTADA=$(nmcli -t -f active,ssid dev wifi | awk -F: '$1=="yes"{print $2; exit}')

UBICACION=$(curl -s ipinfo.io/json)
LAT=$(echo $UBICACION | python3 -c "import sys,json; coords=json.load(sys.stdin)['loc'].split(','); print(coords[0])")
LON=$(echo $UBICACION | python3 -c "import sys,json; coords=json.load(sys.stdin)['loc'].split(','); print(coords[1])")
sed -i "s/LAT=.*/LAT=$LAT/" /home/lsd/config_general.txt
sed -i "s/LON=.*/LON=$LON/" /home/lsd/config_general.txt

# Marcar FIRST_START = FALSE
sed -i 's/FIRST_START = TRUE/FIRST_START = FALSE/' "$CONFIG_PATH"

bash /home/lsd/auto_sync_horarios.sh
timeout 90 rclone copy /home/lsd/config_horarios.txt gdrive:Laboratorio\ 6/

# Calcular próxima ventana (la más cercana a futuro)
HORA_ACTUAL_MIN=$(date +%H%M | sed 's/^0*//')
INICIO_AMANECER=$(awk -F'=' '/inicio_amanecer/{print $2}' "$CONFIG_HORARIOS" | tr -d ' \r:')
INICIO_ATARDECER=$(awk -F'=' '/inicio_atardecer/{print $2}' "$CONFIG_HORARIOS" | tr -d ' \r:')

INICIO_AMANECER_MIN=$(echo "$INICIO_AMANECER" | sed 's/^0*//')
INICIO_ATARDECER_MIN=$(echo "$INICIO_ATARDECER" | sed 's/^0*//')

if [ "$INICIO_AMANECER_MIN" -gt "$HORA_ACTUAL_MIN" ]; then
    HORA_WAKE=$(awk -F'=' '/inicio_amanecer/{print $2}' "$CONFIG_HORARIOS" | tr -d ' \r')
elif [ "$INICIO_ATARDECER_MIN" -gt "$HORA_ACTUAL_MIN" ]; then
    HORA_WAKE=$(awk -F'=' '/inicio_atardecer/{print $2}' "$CONFIG_HORARIOS" | tr -d ' \r')
else
    HORA_WAKE=$(awk -F'=' '/inicio_amanecer/{print $2}' "$CONFIG_HORARIOS" | tr -d ' \r')
fi

PROXIMA_VENTANA=$(echo "$HORA_WAKE" | awk -F: '{m=$2+2; h=$1; if(m>=60){m=m-60} printf "%02d:%02d\n", h, m}')

# Programar alarma y apagar
python3 /home/lsd/set_wake_pijuice.py $HORA_WAKE
log "Conectado a $SSID_CONECTADA. Próxima ventana: $PROXIMA_VENTANA. Apagando."

# Subir log a Drive
timeout 90 rclone copy "$LOG_PATH" gdrive:Laboratorio\ 6/
bash /home/lsd/generar_log_reciente.sh

sudo chown lsd:lsd /home/lsd/.config/rclone/rclone.conf

python3 -c "
import sys
sys.path.append('/home/lsd/BirdNET-Pi/PiJuice/Software/Source')
from pijuice import PiJuice
pj = PiJuice(1, 0x14)
pj.power.SetPowerOff(30)
"
sudo poweroff
