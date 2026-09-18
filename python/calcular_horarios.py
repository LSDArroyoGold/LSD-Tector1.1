from astral import LocationInfo
from astral.sun import sun
from datetime import date, timedelta
import subprocess

# Leer coordenadas desde config_general.txt
def leer_config(archivo, clave):
    with open(archivo) as f:
        for linea in f:
            if clave + '=' in linea:
                return linea.split('=',1)[1].strip()

# Las coordenadas salen de config_general.txt (las de instalacion), SALVO que
# config_horarios.txt traiga LAT= y LON=: ese archivo lo escribe la app de
# Tector Hub y el equipo lo baja del servidor, asi que es la unica forma de
# cambiarlas a distancia (config_general.txt no se sincroniza). Si lo que
# viene no es un numero, se ignora y se sigue con las de instalacion: un
# valor roto no puede dejar al equipo sin horarios.
def coordenadas():
    try:
        lat = float(leer_config('/home/lsd/config_horarios.txt', 'LAT'))
        lon = float(leer_config('/home/lsd/config_horarios.txt', 'LON'))
        if -90 <= lat <= 90 and -180 <= lon <= 180:
            return lat, lon
    except (TypeError, ValueError):
        pass
    return (float(leer_config('/home/lsd/config_general.txt', 'LAT')),
            float(leer_config('/home/lsd/config_general.txt', 'LON')))

LAT, LON = coordenadas()

DURACION_AMANECER = float(leer_config('/home/lsd/config_horarios.txt', 'duracion_amanecer_sync'))
DURACION_ATARDECER = float(leer_config('/home/lsd/config_horarios.txt', 'duracion_atardecer_sync'))

OFFSET_AMANECER = float(leer_config('/home/lsd/config_horarios.txt', 'offset_amanecer_sync'))
OFFSET_ATARDECER = float(leer_config('/home/lsd/config_horarios.txt', 'offset_atardecer_sync'))

# Calcular horarios de hoy y mañana
ubicacion = LocationInfo(latitude=LAT, longitude=LON)
hoy = sun(ubicacion.observer, date=date.today())
manana = sun(ubicacion.observer, date=date.today() + timedelta(days=1))

#Le resto 3 por el huso horario de Argentina

inicio_atardecer = (hoy['sunset'] - timedelta(hours=3) + timedelta(minutes=OFFSET_ATARDECER)).strftime('%H:%M')
fin_atardecer = (hoy['sunset'] - timedelta(hours=3) + timedelta(hours=DURACION_ATARDECER) + timedelta(minutes=OFFSET_ATARDECER)).strftime('%H:%M')
inicio_amanecer = (manana['sunrise'] - timedelta(hours=3) + timedelta(minutes=OFFSET_AMANECER)).strftime('%H:%M')
fin_amanecer = (manana['sunrise'] - timedelta(hours=3) + timedelta(hours=DURACION_AMANECER) + timedelta(minutes=OFFSET_AMANECER)).strftime('%H:%M')

print(f"inicio_atardecer = {inicio_atardecer}")
print(f"fin_atardecer = {fin_atardecer}")
print(f"inicio_amanecer = {inicio_amanecer}")
print(f"fin_amanecer = {fin_amanecer}")

import re

with open('/home/lsd/config_horarios.txt','r') as f:
	contenido = f.read()

contenido = re.sub(r'inicio_amanecer = .*', f'inicio_amanecer = {inicio_amanecer}', contenido)
contenido = re.sub(r'fin_amanecer = .*', f'fin_amanecer = {fin_amanecer}', contenido)
contenido = re.sub(r'inicio_atardecer = .*', f'inicio_atardecer = {inicio_atardecer}', contenido)
contenido = re.sub(r'fin_atardecer = .*', f'fin_atardecer = {fin_atardecer}', contenido)

with open('/home/lsd/config_horarios.txt','w') as f:
	f.write(contenido)

import subprocess
try:
    def _cfg(clave, defecto):
        for linea in open('/home/lsd/config_general.txt'):
            if linea.split('=')[0].strip() == clave:
                return linea.split('=', 1)[1].strip() or defecto
        return defecto
    SYNC_DEST = _cfg('SYNC_REMOTE', 'servidor') + ':' + _cfg('SYNC_PATH', 'data') + '/'
    subprocess.run(['rclone', 'copy', '/home/lsd/config_horarios.txt', SYNC_DEST], timeout=90)
    print("config_horarios.txt actualizado y subido al servidor")
except subprocess.TimeoutExpired:
    print("config_horarios.txt actualizado localmente, pero la subida al servidor tardó más de 90s y se abortó")
