#!/bin/bash

export HOME=/home/lsd

REPO_DIR="/home/lsd/LSD-Tector1.1"

cd "$REPO_DIR" || exit 0

ANTES=$(git rev-parse HEAD)
git pull --quiet origin main
DESPUES=$(git rev-parse HEAD)

if [ "$ANTES" = "$DESPUES" ]; then
	exit 0
fi

# Nunca se toca config/: config_general.txt y config_horarios.txt guardan
# estado en vivo del dispositivo (VENTANA_ACTIVA, CIERRE_FORZADO, coordenadas
# reales, horarios recalculados), no solo valores de plantilla.
cp "$REPO_DIR"/scripts/*.sh /home/lsd/
cp "$REPO_DIR"/python/*.py /home/lsd/
chmod +x /home/lsd/*.sh

sudo cp "$REPO_DIR"/systemd/*.service /etc/systemd/system/
sudo chmod 644 /etc/systemd/system/hotspot.service /etc/systemd/system/sync-rtc.service
sudo systemctl daemon-reload

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Repo actualizado: $ANTES -> $DESPUES" >> /home/lsd/log_sistema.txt
