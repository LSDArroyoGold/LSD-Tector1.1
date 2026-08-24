#!/bin/bash

export RCLONE_CONFIG=/home/lsd/.config/rclone/rclone.conf
export HOME=/home/lsd

HORARIO=$(awk -F' = ' '/inicio_amanecer/{print $2}' /home/lsd/config_horarios.txt |  tr -d '\r')
HORA_ACTUAL=$(date +%H:%M)

HORARIO_DELAY=$(echo "$HORARIO" | awk -F: '{m=$2+2; h=$1; if(m>=60){m=m-60} printf "%02d:%02d\n", h, m}')

if [ "$HORA_ACTUAL" = "$HORARIO_DELAY" ]; then

	sed -i 's/VENTANA_ACTIVA = .*/VENTANA_ACTIVA = NONE/' /home/lsd/config_general.txt
	sed -i 's/CIERRE_FORZADO = .*/CIERRE_FORZADO = FALSE/' /home/lsd/config_general.txt

	FIN_ESPERADO=$(awk -F'=' '/fin_amanecer/{print $2}' /home/lsd/config_horarios.txt | tr -d ' \r')
	python3 /home/lsd/log_sistema.py INICIO amanecer $FIN_ESPERADO
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
	timeout 90 rclone copy /home/lsd/log_sistema.txt gdrive:Laboratorio\ 6/
	bash /home/lsd/generar_log_reciente.sh

	sudo chown lsd:lsd /home/lsd/.config/rclone/rclone.conf

	bash /home/lsd/actualizar_repo.sh
	bash /home/lsd/aplicar_fix_audio_birdnet.sh

	# Migracion a birdnet-lsd (motor propio, en reemplazo de BirdNET-Pi
	# stock): una sola vez, disparada por este mismo ciclo de ventana --
	# el dispositivo esta en el campo sin acceso SSH, asi que tiene que
	# poder completarse sola. migrar_a_birdnet_lsd.sh nunca deja al
	# dispositivo sin motor de deteccion (BirdNET-Pi stock sigue activo
	# hasta confirmar que birdnet-lsd.service arranco bien), y es
	# idempotente -- si ya se migro, o si algo fallo a mitad de camino,
	# no rompe nada y el proximo ciclo retoma solo.
	if [ ! -f /home/lsd/.birdnet_lsd_migrado ]; then
		[ -d /home/lsd/birdnet-lsd ] || git clone https://github.com/LSDArroyoGold/birdnet-lsd.git /home/lsd/birdnet-lsd
		if [ -f /home/lsd/birdnet-lsd/scripts/migrar_a_birdnet_lsd.sh ]; then
			bash /home/lsd/birdnet-lsd/scripts/migrar_a_birdnet_lsd.sh "Laboratorio 6" "BirdNET_Detecciones"
		fi
	fi
fi
