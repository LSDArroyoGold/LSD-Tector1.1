#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Escribe el resumen de un dia: una fila por deteccion, sin el audio.

POR QUE EXISTE
--------------
En este equipo el registro de una deteccion ES su archivo de audio: la
especie, la confianza y la hora estan en el nombre del mp3, y no hay ninguna
otra base de datos. Ni en el equipo, ni en Drive, ni en el servidor.

Eso significa que el dia que un mp3 se va --por retencion, o porque alguien
limpio una carpeta vieja a mano, que es la politica desde el 11/9/2026-- no
se pierde solo la posibilidad de escucharlo: se pierde el dato. El histograma
de horarios, el ranking de especies y la riqueza acumulada de todo lo
anterior desaparecen con los archivos.

Este resumen separa las dos cosas. El audio es lo que se puede escuchar y es
lo pesado; el resumen es el dato y no se borra nunca.

Portado de LSD-Tector2.1, donde nacio. Las diferencias son de esta version:
las rutas son fijas (/home/lsd/...), no hay numero de serie --en la 1.1 no
existe, lo asigna el servidor-- y los nombres de archivo son "birdnet-",
aunque se aceptan los dos por si en algun momento se migra.

CUANTO PESA
-----------
Un dia de este equipo son ~10 MB de audio. El mismo dia como CSV son unos
pocos KB. Guardar el resumen para siempre no cuesta nada.

LA PRIMERA CORRIDA HACE MAS TRABAJO
-----------------------------------
Ademas del dia pedido, resume cualquier fecha que todavia no tenga CSV. La
primera vez eso recupera TODO el historial que hoy existe unicamente como
nombres de archivo, siempre que la carpeta local siga teniendolo. Las
corridas siguientes solo reescriben el dia de hoy, que es el unico que puede
haber cambiado.

Uso:
    python3 resumir_dia.py             # hoy, mas lo que falte
    python3 resumir_dia.py 2026-09-10  # un dia puntual, mas lo que falte
    python3 resumir_dia.py --solo-hoy  # sin recuperar lo que falte
"""
import csv
import os
import re
import sys
from datetime import date

BY_DATE = '/home/lsd/BirdSongs/Extracted/By_Date'
DESTINO = '/home/lsd/resumenes'

# Mismo patron que usan el servidor y la app.
PATRON = re.compile(
    r'^(?P<especie>.+?)-(?P<confianza>\d{1,3})-'
    r'(?P<fecha>\d{4}-\d{2}-\d{2})-(?:birdnet|tectornet)-'
    r'(?P<hora>\d{2}:\d{2}:\d{2})\.(?:mp3|wav|flac)$')

# La columna "serie" va vacia y esta igual: el CSV tiene que poder leerse con
# el mismo codigo que el de la 2.1.
COLUMNAS = ['fecha', 'hora', 'especie', 'confianza', 'serie', 'archivo',
            'bytes']


def filas_de(fecha):
    carpeta = os.path.join(BY_DATE, fecha)
    if not os.path.isdir(carpeta):
        return []
    filas = []
    for raiz, _, nombres in os.walk(carpeta):
        for nombre in nombres:
            m = PATRON.match(nombre)
            if not m:
                continue
            ruta = os.path.join(raiz, nombre)
            try:
                tam = os.path.getsize(ruta)
            except OSError:
                tam = 0
            filas.append({
                'fecha': m.group('fecha'),
                'hora': m.group('hora'),
                'especie': m.group('especie').replace('_', ' '),
                'confianza': int(m.group('confianza')),
                'serie': '',
                'archivo': nombre,
                'bytes': tam,
            })
    filas.sort(key=lambda f: f['hora'])
    return filas


def escribir(fecha):
    filas = filas_de(fecha)
    if not filas:
        return None
    salida = os.path.join(DESTINO, fecha + '.csv')
    # utf-8-sig: estos CSV se terminan abriendo en Excel, y sin BOM los
    # nombres con acentos salen rotos.
    with open(salida, 'w', newline='', encoding='utf-8-sig') as f:
        w = csv.DictWriter(f, fieldnames=COLUMNAS)
        w.writeheader()
        w.writerows(filas)
    return len(filas)


def main():
    args = [a for a in sys.argv[1:] if a != '--solo-hoy']
    solo_hoy = '--solo-hoy' in sys.argv
    fecha = args[0] if args else date.today().isoformat()
    if not re.match(r'^\d{4}-\d{2}-\d{2}$', fecha):
        sys.stderr.write('Fecha invalida: ' + fecha + os.linesep)
        return 2

    if not os.path.isdir(BY_DATE):
        print('No hay carpeta de detecciones.')
        return 0
    if not os.path.isdir(DESTINO):
        os.makedirs(DESTINO)

    n = escribir(fecha)
    if n is None:
        print('No hay detecciones de ' + fecha + '.')
    else:
        print(fecha + ': ' + str(n) + ' detecciones')

    if solo_hoy:
        return 0

    # Lo que falte. En la primera corrida esto es el historial entero; de ahi
    # en adelante, normalmente nada.
    recuperados = 0
    for nombre in sorted(os.listdir(BY_DATE)):
        if nombre == fecha:
            continue
        if not re.match(r'^\d{4}-\d{2}-\d{2}$', nombre):
            continue
        if os.path.exists(os.path.join(DESTINO, nombre + '.csv')):
            continue
        if escribir(nombre):
            recuperados += 1
    if recuperados:
        print('Recuperados ' + str(recuperados) + ' dias que no tenian resumen.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
