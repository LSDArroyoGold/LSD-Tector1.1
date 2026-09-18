#!/bin/bash

export RCLONE_CONFIG=/home/lsd/.config/rclone/rclone.conf
export HOME=/home/lsd

SYNC_REMOTE=$(awk -F'=' '/^SYNC_REMOTE/{print $2}' /home/lsd/config_general.txt | tr -d ' \r')
SYNC_PATH=$(awk -F'=' '/^SYNC_PATH/{print $2}' /home/lsd/config_general.txt | tr -d ' \r')
SYNC_REMOTE=${SYNC_REMOTE:-servidor}
SYNC_PATH=${SYNC_PATH:-data}

VENTANA_ACTIVA=$(awk -F'=' '/VENTANA_ACTIVA/{print $2}' /home/lsd/config_general.txt | tr -d ' \r')

if [ "$VENTANA_ACTIVA" = "NONE" ]; then
	exit 0
fi

timeout 90 rclone copy /home/lsd/BirdSongs/Extracted/By_Date/ "$SYNC_REMOTE:$SYNC_PATH/Detecciones" --include "*.mp3"
