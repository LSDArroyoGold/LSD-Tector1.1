#!/bin/bash

export RCLONE_CONFIG=/home/lsd/.config/rclone/rclone.conf
export HOME=/home/lsd

VENTANA_ACTIVA=$(awk -F'=' '/VENTANA_ACTIVA/{print $2}' /home/lsd/config_general.txt | tr -d ' \r')

if [ "$VENTANA_ACTIVA" = "NONE" ]; then
	exit 0
fi

timeout 90 rclone copy /home/lsd/BirdSongs/Extracted/By_Date/ gdrive:Laboratorio\ 6/BirdNET_Detecciones --include "*.mp3"
