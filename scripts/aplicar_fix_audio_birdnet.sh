#!/bin/bash

# Corrige el ancho de banda del audio guardado por BirdNET-Pi: por defecto,
# el mp3 de cada deteccion queda recortado a ~16kHz por el filtro pasa-bajos
# de LAME (aunque el archivo declare 48000 Hz), y el espectrograma se genera
# remuestreado a 24kHz (eje visible hasta 12kHz). Ninguno de los dos afecta
# la deteccion en si -- el modelo analiza el .wav crudo a 48kHz antes de este
# paso -- solo la fidelidad de lo que queda guardado despues.
#
# Idempotente: si ya se aplico, los sed no encuentran el patron original y no
# hacen nada. Se corre solo, en cada ventana, desde inicio_amanecer.sh /
# inicio_atardecer.sh, despues de actualizar_repo.sh.

export HOME=/home/lsd

REPORTING_PY="/home/lsd/BirdNET-Pi/scripts/utils/reporting.py"

if [ ! -f "$REPORTING_PY" ]; then
	exit 0
fi

if grep -q "'-C', '320'" "$REPORTING_PY" 2>/dev/null; then
	exit 0
fi

sudo sed -i "s/\['sox', '-V1', f'{in_file}', f'{out_file}', 'trim', f'={start}', f'={stop}'\]/['sox', '-V1', f'{in_file}', '-C', '320', f'{out_file}', 'trim', f'={start}', f'={stop}']/" "$REPORTING_PY"
sudo sed -i "s/'remix', '1', 'rate', '24k', 'spectrogram'/'remix', '1', 'spectrogram'/" "$REPORTING_PY"

sudo systemctl restart birdnet_analysis.service

echo "[$(date '+%Y-%m-%d %H:%M')] Fix de ancho de banda de audio aplicado a BirdNET-Pi" >> /home/lsd/log_sistema.txt
