#!/bin/bash

export RCLONE_CONFIG=/home/lsd/.config/rclone/rclone.conf
export HOME=/home/lsd

HORARIO=$(awk -F' = ' '/inicio_amanecer/{print $2}' /home/lsd/config_horarios.txt |  tr -d '\r')
HORA_ACTUAL=$(date +%H:%M)

HORARIO_DELAY=$(echo "$HORARIO" | awk -F: '{m=$2+2; h=$1; if(m>=60){m=m-60} printf "%02d:%02d\n", h, m}')

if [ "$HORA_ACTUAL" = "$HORARIO_DELAY" ]; then

	sed -i 's/VENTANA_ACTIVA = .*/VENTANA_ACTIVA = NONE/' /home/lsd/config_general.txt
	sed -i 's/CIERRE_FORZADO = .*/CIERRE_FORZADO = FALSE/' /home/lsd/config_general.txt

	python3 /home/lsd/log_sistema.py INICIO amanecer
	sed -i 's/VENTANA_ACTIVA = .*/VENTANA_ACTIVA = amanecer/' /home/lsd/config_general.txt
	sudo nmcli radio wifi on
	INTENTOS=0
	until ping -c 1 google.com &>/dev/null || [ $INTENTOS -ge 6 ]; do
		sleep 5
		INTENTOS=$((INTENTOS + 1))
	done
	if ! ping -c 1 google.com &>/dev/null; then
		echo "Sin conexión, abortando"
		exit 1
	fi
	rclone copy /home/lsd/log_sistema.txt gdrive:Laboratorio\ 6/

	sudo chown lsd:lsd /home/lsd/.config/rclone/rclone.conf

	bash /home/lsd/actualizar_repo.sh
fi
