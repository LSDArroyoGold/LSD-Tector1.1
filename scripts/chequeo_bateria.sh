#!/bin/bash

export HOME=/home/lsd

VENTANA_ACTIVA=$(awk -F'=' '/VENTANA_ACTIVA/{print $2}' /home/lsd/config_general.txt | tr -d ' \r')

if [ "$VENTANA_ACTIVA" = "NONE" ]; then
	exit 0
fi

UMBRAL=$(awk -F'=' '/UMBRAL_BATERIA/{print $2}' /home/lsd/config_general.txt | tr -d ' \r')

NIVEL=$(python3 -c "
import sys
sys.path.append('/home/lsd/BirdNET-Pi/PiJuice/Software/Source')
from pijuice import PiJuice
pj = PiJuice(1, 0x14)
print(pj.status.GetChargeLevel()['data'])
")

if [ "$NIVEL" -lt "$UMBRAL" ]; then
	sed -i 's/CIERRE_FORZADO = .*/CIERRE_FORZADO = TRUE/' /home/lsd/config_general.txt
fi
