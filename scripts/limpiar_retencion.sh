#!/bin/bash
#
# limpiar_retencion.sh - acota el almacenamiento LOCAL por tamaño, borrando
# carpetas de fecha ENTERAS (By_Date/<fecha>/, con todas sus especies
# adentro) empezando por la mas vieja -- nunca archivos sueltos de un dia a
# medias, para que sea predecible ("o esta el dia completo, o no esta").
# Llamado desde cierre_amanecer.sh/cierre_atardecer.sh, DESPUES de que el
# rclone copy de esa corrida haya salido bien (si el servidor no esta
# disponible en ese momento, no se toca nada, se reintenta en el proximo
# cierre).
#
# RETENCION_AUDIO_LOCAL_MB en config_general.txt. Es proteccion de la
# microSD, no politica de datos: si la tarjeta se llena, el equipo deja de
# grabar. Lo local es una copia de trabajo de algo que ya subio al servidor
# --y "rclone copy" no propaga borrados, asi que el servidor se queda igual--.
# Del servidor no se borra nada automaticamente.

# El patron va anclado con ^: sin eso, un comentario del config que
# nombrara la clave entra igual en el match, awk devuelve dos lineas y el
# $((...)) de mas abajo se rompe con un error que no dice nada.
RETENCION_LOCAL_MB=$(awk -F'=' '/^RETENCION_AUDIO_LOCAL_MB/{print $2}' /home/lsd/config_general.txt | tr -d ' \r')

# du por carpeta de fecha (mas nueva primero), acumular tamaño, borrar
# carpetas enteras una vez superado el limite.
if [ -n "$RETENCION_LOCAL_MB" ]; then
	CAP_BYTES=$((RETENCION_LOCAL_MB * 1024 * 1024))
	find /home/lsd/BirdSongs/Extracted/By_Date -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
		| sort -r \
		| while IFS= read -r FECHA; do
			echo "$(du -sb "/home/lsd/BirdSongs/Extracted/By_Date/$FECHA" 2>/dev/null | cut -f1) $FECHA"
		done \
		| awk -v cap="$CAP_BYTES" '{ acumulado += $1; if (acumulado > cap) print $2 }' \
		| while IFS= read -r FECHA; do
			rm -rf "/home/lsd/BirdSongs/Extracted/By_Date/$FECHA"
			echo "[$(date '+%Y-%m-%d %H:%M')] RETENCION: borrado audio local de $FECHA (la SD paso los $RETENCION_LOCAL_MB MB; la copia del servidor sigue)" >> /home/lsd/log_sistema.txt
		done
fi
