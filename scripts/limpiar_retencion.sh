#!/bin/bash
#
# limpiar_retencion.sh - agregado el 4/9/2026, a pedido de Diego: acota
# tanto el almacenamiento LOCAL como el de DRIVE por tamaño, borrando
# carpetas de fecha ENTERAS (By_Date/<fecha>/, con todas sus especies
# adentro) empezando por la mas vieja -- nunca archivos sueltos de un
# dia a medias, para que sea predecible ("o esta el dia completo, o no
# esta"). Llamado desde cierre_amanecer.sh/cierre_atardecer.sh, DESPUES
# de que el rclone copy de esa corrida haya salido bien (si Drive no
# esta disponible en ese momento, no se toca nada, se reintenta en el
# proximo cierre).
#
# RETENCION_AUDIO_LOCAL_MB / RETENCION_DRIVE_MB en config_general.txt --
# pueden ser distintos numeros, aunque hoy (4/9) se usan los mismos 3072
# (3GB) en los dos por pedido explicito de tener un limite parejo.
#
# ============================================================
# 11/9/2026: EL BORRADO DE DRIVE QUEDA APAGADO
# ============================================================
#
# Decision del laboratorio: de Drive no se borra nada automaticamente. La
# limpieza de lo viejo se hace a mano, mirando que carpetas ya no se usan.
# Con pocos equipos, el costo de guardar todo es chico y el de borrar algo
# que hacia falta es alto.
#
# El interruptor esta ACA, en el script, y no en config_general.txt a
# proposito: ese archivo NO se sincroniza (guarda estado en vivo del
# equipo, ver actualizar_repo.sh), asi que en un Tector ya instalado en
# campo no hay forma de cambiarlo sin ir hasta el equipo. El script si se
# sincroniza, o sea que esto llega solo en la proxima ventana.
#
# CUANDO HABRIA EMPEZADO A BORRAR: todavia no lo hizo. El equipo de campo
# tiene RETENCION_DRIVE_MB = 3072 y venia con 1,4 GB en 144 dias (~9,7
# MB/dia, dato real de tector1, no del labo: el labo mide ~50 MB/dia porque
# detecta muchisimo mas). A ese ritmo el tope de 3 GB llega recien a los
# ~310 dias, o sea alrededor de mediados de 2027. No es una urgencia; es
# una bomba con la mecha larga, y el momento de desactivarla es ahora que
# la estamos mirando y no cuando se lleve el primer año de datos.
#
# Vale la pena tener presente que ese ritmo puede cambiar solo: cualquier
# cosa que suba las detecciones --otra ubicacion, ventanas mas largas, un
# umbral mas bajo, un modelo mas sensible-- acorta la mecha, y nadie va a
# estar mirando el tamaño de la carpeta cuando pase.
#
# Y en la 1.1 duele mas que en la 2.1, porque ACA EL ARCHIVO ES EL DATO: la
# especie, la confianza y la hora estan en el nombre del mp3 y no hay
# ninguna otra base. La 2.1 escribe antes un resumen diario en CSV
# (python/resumir_dia.py, ~5 KB por dia contra ~50 MB de audio) y por eso
# ahi el historial sobrevive al audio. Esto no lo tiene. Borrar de Drive
# aca no es perder la grabacion: es perder la deteccion.
#
# Para volver a encenderlo: BORRAR_DE_DRIVE=SI y pushear. Antes de hacerlo,
# portar resumir_dia.py.
BORRAR_DE_DRIVE=NO

# Los patrones van anclados con ^: sin eso, un comentario del config que
# nombrara la clave (por ejemplo para explicar por que esta apagada) entra
# igual en el match, awk devuelve dos lineas y el $((...)) de mas abajo se
# rompe con un error que no dice nada.
RETENCION_LOCAL_MB=$(awk -F'=' '/^RETENCION_AUDIO_LOCAL_MB/{print $2}' /home/lsd/config_general.txt | tr -d ' \r')
RETENCION_DRIVE_MB=$(awk -F'=' '/^RETENCION_DRIVE_MB/{print $2}' /home/lsd/config_general.txt | tr -d ' \r')

# --- Local: du por carpeta de fecha (mas nueva primero), acumular
# tamaño, borrar carpetas enteras una vez superado el limite. ---
#
# Esto SI sigue activo, y es a proposito: no es politica de datos, es la
# proteccion de la microSD. Si la tarjeta se llena, el equipo deja de grabar.
# Lo local es una copia de trabajo de algo que ya subio a Drive --y "rclone
# copy" no propaga borrados, asi que lo de Drive se queda igual--.
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
			echo "[$(date '+%Y-%m-%d %H:%M')] RETENCION: borrado audio local de $FECHA (la SD paso los $RETENCION_LOCAL_MB MB; la copia de Drive sigue)" >> /home/lsd/log_sistema.txt
		done
fi

# --- Drive: un solo listado recursivo con tamaños (rclone lsjson -R),
# agrupado por carpeta de fecha en Python (mas eficiente que un
# "rclone size" por fecha, que seria una llamada de red por dia). Best
# effort: si el listado falla (sin red, Drive caido), no se borra nada.
# ---
if [ "$BORRAR_DE_DRIVE" = "SI" ] && [ -n "$RETENCION_DRIVE_MB" ]; then
	CAP_BYTES=$((RETENCION_DRIVE_MB * 1024 * 1024))
	timeout 60 rclone lsjson -R "gdrive:Tector 1/Detecciones/" --files-only 2>/dev/null \
		| python3 -c "
import sys, json

try:
    items = json.load(sys.stdin)
except Exception:
    sys.exit(0)

por_fecha = {}
for it in items:
    partes = it.get('Path', '').split('/')
    if not partes or not partes[0]:
        continue
    fecha = partes[0]
    por_fecha[fecha] = por_fecha.get(fecha, 0) + it.get('Size', 0)

acumulado = 0
cap = $CAP_BYTES
for fecha in sorted(por_fecha, reverse=True):
    acumulado += por_fecha[fecha]
    if acumulado > cap:
        print(fecha)
" \
		| while IFS= read -r FECHA; do
			if timeout 60 rclone purge "gdrive:Tector 1/Detecciones/$FECHA" 2>/dev/null; then
				echo "[$(date '+%Y-%m-%d %H:%M')] RETENCION: borrado de DRIVE el dia $FECHA (Drive paso los $RETENCION_DRIVE_MB MB)" >> /home/lsd/log_sistema.txt
			fi
		done
fi
