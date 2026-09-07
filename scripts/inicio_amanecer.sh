#!/bin/bash

export RCLONE_CONFIG=/home/lsd/.config/rclone/rclone.conf
export HOME=/home/lsd

HORARIO=$(awk -F' = ' '/inicio_amanecer/{print $2}' /home/lsd/config_horarios.txt |  tr -d '\r')
HORA_ACTUAL=$(date +%H:%M)
FECHA_HOY=$(date +%Y-%m-%d)

HORARIO_DELAY=$(echo "$HORARIO" | awk -F: '{m=$2+2; h=$1; if(m>=60){m=m-60; h=h+1; if(h>=24){h=h-24}} printf "%02d:%02d\n", h, m}')
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
	timeout 90 rclone copy /home/lsd/log_sistema.txt "gdrive:Tector 1/"
	bash /home/lsd/generar_log_reciente.sh

	sudo chown lsd:lsd /home/lsd/.config/rclone/rclone.conf

	bash /home/lsd/actualizar_repo.sh
	bash /home/lsd/aplicar_fix_audio_birdnet.sh

	# Migracion/renombrado del motor propio (TectorNET-Pi, antes
	# birdnet-lsd, renombrado el 7/9/2026): disparado por este mismo ciclo
	# de ventana -- el dispositivo esta en el campo sin acceso SSH, asi que
	# tiene que poder completarse solo. Tres estados posibles segun la
	# marca presente:
	#   - sin ninguna marca: nunca se instalo el motor propio, todavia en
	#     BirdNET-Pi stock -> migrar_a_tectornet_pi.sh (clone + instalacion
	#     completa, nunca deja al dispositivo sin motor de deteccion:
	#     BirdNET-Pi stock sigue activo hasta confirmar que
	#     TectorNET-Pi.service arranco bien).
	#   - marca vieja (.birdnet_lsd_migrado) sin la nueva: motor propio ya
	#     instalado bajo el nombre viejo -> renombrar_a_tectornet_pi.sh (mv
	#     en el lugar, sin reinstalar nada, mismo principio de no dejar el
	#     dispositivo sin motor sano a mitad de camino).
	#   - marca nueva (.tectornet_pi_migrado): ya en el nombre nuevo ->
	#     actualizar_tectornet_pi.sh (git pull + chequeo de salud, revierte
	#     solo si el commit nuevo rompe el servicio).
	# Los tres scripts son idempotentes -- si algo falla a mitad de camino,
	# no rompe nada y el proximo ciclo retoma solo.
	if [ -f /home/lsd/.tectornet_pi_migrado ]; then
		if [ -f /home/lsd/TectorNET-Pi/scripts/actualizar_tectornet_pi.sh ]; then
			bash /home/lsd/TectorNET-Pi/scripts/actualizar_tectornet_pi.sh
		fi
	elif [ -f /home/lsd/.birdnet_lsd_migrado ]; then
		if [ -f /home/lsd/birdnet-lsd/scripts/renombrar_a_tectornet_pi.sh ]; then
			bash /home/lsd/birdnet-lsd/scripts/renombrar_a_tectornet_pi.sh
		fi
	else
		# LSD-Tector1.1 evita depender de git a proposito (todo via curl) --
		# TectorNET-Pi si lo necesita (clone/pull), asi que se instala aca si
		# hace falta antes de intentar el clone.
		command -v git &>/dev/null || sudo apt-get install -y git &>/dev/null
		if [ -d /home/lsd/TectorNET-Pi ] || git clone https://github.com/LSDArroyoGold/TectorNET-Pi.git /home/lsd/TectorNET-Pi; then
			if [ -f /home/lsd/TectorNET-Pi/scripts/migrar_a_tectornet_pi.sh ]; then
				bash /home/lsd/TectorNET-Pi/scripts/migrar_a_tectornet_pi.sh "Tector 1" "Detecciones"
			fi
		else
			python3 /home/lsd/log_sistema.py MSG "ALERTA: no se pudo clonar TectorNET-Pi (git no disponible?)"
		fi
	fi
fi
