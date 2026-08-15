#!/bin/bash

export HOME=/home/lsd

REPO="LSDArroyoGold/LSD-Tector1.1"
RAW="https://raw.githubusercontent.com/$REPO/main"
API="https://api.github.com/repos/$REPO/commits/main"
MARCA="/home/lsd/.ultima_actualizacion"
TMP="/home/lsd/.actualizar_tmp"

ULTIMO_SHA=$(cat "$MARCA" 2>/dev/null)

SHA_ACTUAL=$(curl -s "$API" | python3 -c "import sys,json; print(json.load(sys.stdin)['sha'])" 2>/dev/null)

if [ -z "$SHA_ACTUAL" ] || [ "$SHA_ACTUAL" = "$ULTIMO_SHA" ]; then
	exit 0
fi

# Todos los archivos que corren activamente en /home/lsd. config/ queda
# afuera a propósito: config_general.txt y config_horarios.txt guardan
# estado en vivo del dispositivo (VENTANA_ACTIVA, CIERRE_FORZADO,
# coordenadas reales, horarios recalculados), no solo configuración de fábrica.
ARCHIVOS="scripts/inicio_amanecer.sh scripts/inicio_atardecer.sh scripts/cierre_amanecer.sh scripts/cierre_atardecer.sh scripts/hotspot.sh scripts/auto_sync_horarios.sh scripts/chequeo_bateria.sh scripts/sincronizar_detecciones.sh scripts/actualizar_repo.sh python/calcular_horarios.py python/check_button.py python/configurar_bateria_pijuice.py python/log_sistema.py python/portal_configuracion.py python/set_wake_pijuice.py python/sync_pijuice_rtc.py systemd/hotspot.service systemd/sync-rtc.service"

rm -rf "$TMP"
mkdir -p "$TMP"

for ARCHIVO in $ARCHIVOS; do
	NOMBRE=$(basename "$ARCHIVO")
	if ! curl -sf -o "$TMP/$NOMBRE" "$RAW/$ARCHIVO"; then
		echo "Fallo la descarga de $ARCHIVO, aborto sin tocar nada" >&2
		rm -rf "$TMP"
		exit 1
	fi
done

SELF_CAMBIO=0
if [ ! -f /home/lsd/actualizar_repo.sh ] || ! cmp -s "$TMP/actualizar_repo.sh" /home/lsd/actualizar_repo.sh; then
	SELF_CAMBIO=1
fi

# $TMP está en /home/lsd, mismo filesystem que los destinos: el mv es un
# rename atómico, seguro incluso si el archivo que se reemplaza es el que
# está corriendo en este momento (este mismo script, o el inicio_*.sh que
# lo llamó).
for ARCHIVO in $ARCHIVOS; do
	NOMBRE=$(basename "$ARCHIVO")
	case "$ARCHIVO" in
		systemd/*)
			sudo mv "$TMP/$NOMBRE" "/etc/systemd/system/$NOMBRE"
			sudo chmod 644 "/etc/systemd/system/$NOMBRE"
			;;
		*)
			mv "$TMP/$NOMBRE" "/home/lsd/$NOMBRE"
			;;
	esac
done

chmod +x /home/lsd/*.sh
sudo systemctl daemon-reload

rm -rf "$TMP"

# Si actualizar_repo.sh cambió, la lista de $ARCHIVOS que acabamos de usar
# para bajar todo puede ser la vieja (la que ya estaba cargada en memoria
# al arrancar esta corrida) — por ejemplo, si el mismo commit que nos trajo
# esta versión nueva también agregó un archivo a la lista. Nos volvemos a
# ejecutar una vez con la versión ya instalada para completar el ciclo con
# la lista correcta antes de marcar la actualización como terminada.
# _REEXEC evita un bucle si por lo que sea el archivo siguiera "cambiando".
if [ "$SELF_CAMBIO" = "1" ] && [ -z "$_REEXEC" ]; then
	_REEXEC=1 exec bash /home/lsd/actualizar_repo.sh
fi

echo "$SHA_ACTUAL" > "$MARCA"

echo "[$(date '+%Y-%m-%d %H:%M')] Software actualizado ($SHA_ACTUAL)" >> /home/lsd/log_sistema.txt
