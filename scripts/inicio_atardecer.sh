#!/bin/bash

export RCLONE_CONFIG=/home/lsd/.config/rclone/rclone.conf
export HOME=/home/lsd

SYNC_REMOTE=$(awk -F'=' '/^SYNC_REMOTE/{print $2}' /home/lsd/config_general.txt | tr -d ' \r')
SYNC_PATH=$(awk -F'=' '/^SYNC_PATH/{print $2}' /home/lsd/config_general.txt | tr -d ' \r')
SYNC_REMOTE=${SYNC_REMOTE:-servidor}
SYNC_PATH=${SYNC_PATH:-data}

HORARIO=$(awk -F' = ' '/inicio_atardecer/{print $2}' /home/lsd/config_horarios.txt |  tr -d '\r')
HORA_ACTUAL=$(date +%H:%M)
FECHA_HOY=$(date +%Y-%m-%d)

HORARIO_DELAY=$(echo "$HORARIO" | awk -F: '{m=$2+2; h=$1; if(m>=60){m=m-60; h=h+1; if(h>=24){h=h-24}} printf "%02d:%02d\n", h, m}')
FIN_ESPERADO=$(awk -F'=' '/fin_atardecer/{print $2}' /home/lsd/config_horarios.txt | tr -d ' \r')
MARCA="/home/lsd/.inicio_atardecer_hecho_$FECHA_HOY"

# Ver la nota completa en inicio_amanecer.sh sobre por que se cambio de
# minuto exacto a una ventana de tolerancia con marca de "ya arranco hoy".
if [ ! -f "$MARCA" ] && [[ ! "$HORA_ACTUAL" < "$HORARIO_DELAY" ]] && [[ "$HORA_ACTUAL" < "$FIN_ESPERADO" ]]; then

	touch "$MARCA"
	find /home/lsd -maxdepth 1 -name '.inicio_atardecer_hecho_*' -mtime +3 -delete 2>/dev/null

	sed -i 's/VENTANA_ACTIVA = .*/VENTANA_ACTIVA = NONE/' /home/lsd/config_general.txt
	sed -i 's/CIERRE_FORZADO = .*/CIERRE_FORZADO = FALSE/' /home/lsd/config_general.txt

	python3 /home/lsd/log_sistema.py INICIO atardecer $FIN_ESPERADO
	sed -i 's/VENTANA_ACTIVA = .*/VENTANA_ACTIVA = atardecer/' /home/lsd/config_general.txt
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
	timeout 90 rclone copy /home/lsd/log_sistema.txt "$SYNC_REMOTE:$SYNC_PATH/"
	bash /home/lsd/generar_log_reciente.sh

	sudo chown lsd:lsd /home/lsd/.config/rclone/rclone.conf

	bash /home/lsd/actualizar_repo.sh

	# Actualiza el motor (git pull + chequeo de salud, revierte solo si el
	# commit nuevo rompe el servicio).
	if [ -f /home/lsd/TectorNET-Pi/scripts/actualizar_tectornet_pi.sh ]; then
		bash /home/lsd/TectorNET-Pi/scripts/actualizar_tectornet_pi.sh
	fi
fi
