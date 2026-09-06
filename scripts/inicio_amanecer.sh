#!/bin/bash

export RCLONE_CONFIG=/home/lsd/.config/rclone/rclone.conf
export HOME=/home/lsd

HORARIO=$(awk -F' = ' '/inicio_amanecer/{print $2}' /home/lsd/config_horarios.txt |  tr -d '\r')
HORA_ACTUAL=$(date +%H:%M)
FECHA_HOY=$(date +%Y-%m-%d)

HORARIO_DELAY=$(echo "$HORARIO" | awk -F: '{m=$2+2; h=$1; if(m>=60){m=m-60} printf "%02d:%02d\n", h, m}')
FIN_ESPERADO=$(awk -F'=' '/fin_amanecer/{print $2}' /home/lsd/config_horarios.txt | tr -d ' \r')
MARCA="/home/lsd/.inicio_amanecer_hecho_$FECHA_HOY"

# Antes: comparacion de MINUTO EXACTO (HORA_ACTUAL = HORARIO_DELAY) -- cron
# corre cada 60s, asi que si el equipo no respondia justo en ese minuto
# puntual (bootenado a medias, ocupado, lo que sea) se perdia el dia
# entero sin reintento. Encontrado el 6/9/2026: el amanecer no corrio ese
# dia pese a que el reloj y el cron estaban sanos -- no hay prueba de que
# haya sido justo esto, pero es una fragilidad real de por si. Ahora:
# ventana de tolerancia desde HORARIO_DELAY hasta FIN_ESPERADO, con una
# marca de "ya arranco hoy" para no repetir el INICIO en cada minuto
# subsiguiente de esa misma ventana.
if [ ! -f "$MARCA" ] && [[ ! "$HORA_ACTUAL" < "$HORARIO_DELAY" ]] && [[ "$HORA_ACTUAL" < "$FIN_ESPERADO" ]]; then

	touch "$MARCA"
	find /home/lsd -maxdepth 1 -name '.inicio_amanecer_hecho_*' -mtime +3 -delete 2>/dev/null

	sed -i 's/VENTANA_ACTIVA = .*/VENTANA_ACTIVA = NONE/' /home/lsd/config_general.txt
	sed -i 's/CIERRE_FORZADO = .*/CIERRE_FORZADO = FALSE/' /home/lsd/config_general.txt

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
	timeout 90 rclone copy /home/lsd/log_sistema.txt gdrive:
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
		# LSD-Tector1.1 evita depender de git a proposito (todo via curl) --
		# birdnet-lsd si lo necesita (clone/pull), asi que se instala aca si
		# hace falta antes de intentar el clone.
		command -v git &>/dev/null || sudo apt-get install -y git &>/dev/null
		if [ -d /home/lsd/birdnet-lsd ] || git clone https://github.com/LSDArroyoGold/birdnet-lsd.git /home/lsd/birdnet-lsd; then
			if [ -f /home/lsd/birdnet-lsd/scripts/migrar_a_birdnet_lsd.sh ]; then
				bash /home/lsd/birdnet-lsd/scripts/migrar_a_birdnet_lsd.sh "Laboratorio 6" "BirdNET_Detecciones"
			fi
		else
			python3 /home/lsd/log_sistema.py MSG "ALERTA: no se pudo clonar birdnet-lsd (git no disponible?)"
		fi
	elif [ -d /home/lsd/birdnet-lsd ]; then
		# Ya migrado: el bloque de arriba no vuelve a correr nunca mas, asi
		# que sin este paso birdnet-lsd quedaria congelado en la version del
		# dia de la migracion para siempre.
		if [ -f /home/lsd/birdnet-lsd/scripts/actualizar_birdnet_lsd.sh ]; then
			# git pull + reinicio con chequeo de salud (revierte solo si el
			# commit nuevo rompe el servicio).
			bash /home/lsd/birdnet-lsd/scripts/actualizar_birdnet_lsd.sh
		else
			# Arranque en frio: la primera vez que este mecanismo llega a un
			# dispositivo ya migrado, el checkout esta congelado en la
			# version de la migracion y todavia no tiene actualizar_birdnet_lsd.sh
			# (que vive en el repo birdnet-lsd, recien lo trae este mismo
			# pull). Un pull simple sin chequeo de salud, aceptable porque
			# los commits pendientes en este caso puntual son de bajo riesgo
			# (config y nombre de archivo, no logica de deteccion). Desde la
			# proxima ventana ya existe el script y se usa la logica
			# completa con rollback.
			git -C /home/lsd/birdnet-lsd pull --quiet 2>/dev/null
			sudo systemctl restart birdnet-lsd.service 2>/dev/null
		fi
	fi
fi
