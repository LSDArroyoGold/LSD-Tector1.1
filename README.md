# LSD-Tector 1.1 — Software

Este repositorio contiene todo el software necesario para replicar el sistema de monitoreo autónomo de aves LSD-Tector, desarrollado en el Laboratorio de Sistemas Dinámicos (LSD), Facultad de Ciencias Exactas y Naturales, Universidad de Buenos Aires.

El sistema gestiona automáticamente ventanas de grabación en horarios de amanecer y atardecer, identifica especies mediante BirdNET-Pi, envía detecciones a Google Drive, y administra el ciclo de encendido y apagado de la Raspberry Pi mediante el RTC de la PiJuice HAT. Para una descripción completa del hardware y el diseño físico del dispositivo, referirse al artículo asociado.

Este software fue desarrollado y probado sobre una **Raspberry Pi 4 Model B (4GB RAM)** con una **PiJuice HAT** como módulo de gestión de energía. No se garantiza compatibilidad con otros modelos o configuraciones de hardware.

---

## Dependencias

- Raspberry Pi OS Full 64-bit (Bookworm)
- BirdNET-Pi
- Python 3 (incluido en Raspberry Pi OS)
- rclone
- astral (librería Python)
- API Python de PiJuice
- nmcli (incluido en Raspberry Pi OS)
- dnsmasq y util-linux-extra

### 1. Sistema operativo

Instalar **Raspberry Pi OS Full 64-bit (Bookworm)** en la microSD usando [Raspberry Pi Imager](https://www.raspberrypi.com/software/). Durante el proceso de flasheo, en la sección de configuración avanzada del Imager (ícono del engranaje), crear un usuario con nombre y contraseña a elección.

> [!WARNING]
> Todos los scripts y archivos de configuración de este repositorio tienen la ruta `/home/lsd/` hardcodeada como directorio de trabajo. Esta ruta corresponde al usuario `lsd` utilizado en nuestra instalación de referencia. Si se utiliza un nombre de usuario diferente, será necesario reemplazar manualmente **todas las apariciones** de `/home/lsd/` por la ruta correspondiente al usuario elegido, en cada uno de los scripts `.sh` y `.py` del repositorio antes de utilizarlos. En versiones futuras esta configuración será centralizada y más fácil de personalizar.

Una vez flasheada la microSD, insertarla en la Raspberry Pi y encenderla.

### 2. BirdNET-Pi

Desde la terminal de la RP, ejecutar:

```bash
curl -s https://raw.githubusercontent.com/Nachtzuster/BirdNET-Pi/main/newinstaller.sh | bash
```

La instalación tarda varios minutos. Una vez finalizada, BirdNET-Pi queda corriendo automáticamente y es accesible desde cualquier dispositivo en la misma red ingresando `http://[IP_de_la_RP]` en el navegador. Para obtener la IP de la Raspberry Pi, ejecutar desde su terminal:

```bash
hostname -I
```

El primer valor que devuelve es la IP local del dispositivo.

Una vez instalado, configurar la gestión de disco para evitar que la tarjeta microSD se llene con el tiempo:

```bash
sudo nano /etc/birdnet/birdnet.conf
```
Buscar los parámetros `FULL_DISK` y `PURGE_THRESHOLD` y establecerlos así:

```
FULL_DISK=purge
PURGE_THRESHOLD=75
```
Con esta configuración, cuando el disco supere el 75% de ocupación, BirdNET-Pi eliminará automáticamente las grabaciones del día más antiguo para liberar espacio. Guardar con **Ctrl+O** y salir con **Ctrl+X**.

### 3. Reducir el consumo de BirdNET-Pi para uso desatendido

BirdNET-Pi instala por defecto un conjunto de servicios pensados para cuando alguien mira el dashboard desde el navegador en la misma red (streaming de audio en vivo, visor de espectrograma, gráficos, terminal web, panel de estadísticas). En un dispositivo desatendido en el campo no hay nadie mirando esos servicios, y miden un consumo real: apagarlos, junto con no arrancar el entorno gráfico de escritorio (que tampoco tiene sentido sin monitor conectado), midió una reducción de **~19% en el consumo instantáneo** en pruebas de campo — sin afectar la grabación, el análisis ni la subida a BirdWeather, que no dependen de ninguno de estos servicios.

Deshabilitar los servicios de dashboard/streaming (quedan enmascarados, no se pueden arrancar ni por accidente):

```bash
sudo systemctl disable --now icecast2.service livestream.service chart_viewer.service \
    spectrogram_viewer.service web_terminal.service caddy.service birdnet_stats.service \
    birdnet_log.service php8.4-fpm.service
sudo systemctl mask icecast2.service livestream.service chart_viewer.service \
    spectrogram_viewer.service web_terminal.service caddy.service birdnet_stats.service \
    birdnet_log.service php8.4-fpm.service
```

> **Nota:** `icecast2` y `php8.4-fpm` son scripts SysV, no unidades systemd nativas — si el `disable --now` no los frena del todo, parar el proceso a mano con `sudo systemctl stop icecast2.service` (o el que corresponda) y confirmar con `systemctl is-active`.

Arrancar directamente en modo consola, sin sesión gráfica (la grabación y el análisis no dependen del escritorio — `birdnet_recording.sh` ya inicia su propio `pulseaudio` si hace falta):

```bash
sudo systemctl set-default multi-user.target
```

Si en algún momento hace falta conectar un monitor en el laboratorio para debug visual, activar el entorno gráfico puntualmente con `sudo systemctl isolate graphical.target` (no hace falta revertir el paso anterior; con el próximo reinicio vuelve a arrancar en modo consola).

### 4. Paquetes del sistema

```bash
sudo apt update
sudo apt install -y dnsmasq util-linux-extra
sudo systemctl enable dnsmasq
sudo systemctl start dnsmasq
```

Verificar que `hwclock` quedó disponible:

```bash
which hwclock
```

Debe devolver `/usr/sbin/hwclock`.

### 5. Habilitar I2C

La PiJuice se comunica con la Raspberry Pi mediante el protocolo I2C. Para habilitarlo:

```bash
sudo raspi-config
```

Navegar a **Interface Options → I2C → Enable**. Confirmar y salir. Luego reiniciar:

```bash
sudo reboot
```

Verificar que la PiJuice es detectada correctamente en el bus I2C (debe aparecer `14` en la dirección 0x14):

```bash
sudo i2cdetect -y 1
```

### 6. Dependencias Python

```bash
pip install astral --break-system-packages
```

### 7. API Python de PiJuice

El paquete oficial de PiJuice no está disponible en los repositorios estándar de Raspberry OS. Instalarlo directamente desde GitHub:

```bash
git clone https://github.com/PiSupply/PiJuice.git /home/lsd/BirdNET-Pi/PiJuice
cd /home/lsd/BirdNET-Pi/PiJuice/Software/Source
pip install . --break-system-packages
```

Verificar que la API funciona correctamente:

```bash
python3 -c "
import sys
sys.path.append('/home/lsd/BirdNET-Pi/PiJuice/Software/Source')
from pijuice import PiJuice
pj = PiJuice(1, 0x14)
print(pj.status.GetStatus())
print(pj.status.GetChargeLevel())
"
```

Si la PiJuice responde sin errores, la instalación fue exitosa.

### 8. Clonar el repositorio

Clonar este repositorio en la Raspberry Pi:

```bash
cd /home/lsd
git clone https://github.com/LSDArroyoGold/LSD-Tector1.1.git
```

Copiar los scripts y archivos de configuración a `/home/lsd/`:

```bash
cp /home/lsd/LSD-Tector1.1/scripts/* /home/lsd/
cp /home/lsd/LSD-Tector1.1/python/* /home/lsd/
cp /home/lsd/LSD-Tector1.1/config/* /home/lsd/
chmod +x /home/lsd/*.sh
```

> **Nota:** el asterisco `*` es un comodín de bash que significa "todos los archivos". Por ejemplo, `scripts/*` copia todos los archivos dentro de la carpeta `scripts/`.

Copiar los archivos de servicio de systemd:

```bash
sudo cp /home/lsd/LSD-Tector1.1/systemd/sync-rtc.service /etc/systemd/system/
sudo cp /home/lsd/LSD-Tector1.1/systemd/hotspot.service /etc/systemd/system/
```

Una vez copiado todo, borrar el clon — en la Pi no queda ninguna carpeta del repositorio, todos los archivos operativos viven sueltos directamente en `/home/lsd/` (`actualizar_repo.sh`, ver paso 15, tampoco necesita el clon: se actualiza descargando archivo por archivo):

```bash
rm -rf /home/lsd/LSD-Tector1.1
```

Dar permisos correctos a los archivos de servicio:

```bash
sudo chmod 644 /etc/systemd/system/sync-rtc.service
sudo chmod 644 /etc/systemd/system/hotspot.service
```

Recargar la configuración de systemd para que reconozca los nuevos servicios:

```bash
sudo systemctl daemon-reload
```

### 9. rclone

Instalar rclone:

```bash
sudo apt install rclone
```

**Autenticación con Google Drive**

La autenticación con Google requiere un navegador con interfaz gráfica. Como BirdNET-Pi ocupa el navegador de la Raspberry Pi, la autenticación se realiza desde una PC con Windows o Linux como intermediaria.

**En la PC intermediaria:**

1. Descargar rclone para el sistema operativo correspondiente desde [https://rclone.org/downloads/](https://rclone.org/downloads/)
2. Descomprimir el archivo
3. Abrir una terminal (PowerShell en Windows) en la carpeta donde se descomprimió rclone
4. Ejecutar el siguiente comando:

```bash
.\rclone.exe authorize "drive"
```

> **Nota:** en Linux o macOS el comando es `./rclone authorize "drive"`.

5. El navegador se abrirá automáticamente. Iniciar sesión con la cuenta de Google deseada y otorgar los permisos solicitados.
6. La terminal mostrará un token JSON entre llaves (`{...}`). Copiar el token completo, incluyendo las llaves.

**En la Raspberry Pi:**

Ejecutar el asistente de configuración:

```bash
rclone config
```

Seguir el asistente interactivo con las siguientes respuestas:

- `n` → crear una nueva configuración
- Nombre: `gdrive`
- Seleccionar el número correspondiente a **Google Drive** en la lista
- `client_id`: dejar vacío y presionar Enter
- `client_secret`: dejar vacío y presionar Enter
- Scope: opción `1` (acceso completo)
- `service_account_file`: dejar vacío y presionar Enter
- Configuración avanzada: `n`
- Autenticación desde este dispositivo (auto config): `n`
- Pegar el token JSON obtenido desde la PC intermediaria
- Configurar como shared drive: `n`
- Confirmar configuración: `y`
- Salir del asistente: `q`

> **Nota sobre `client_id` y `client_secret`:** dejarlos vacíos hace que rclone utilice las credenciales OAuth por defecto, que son compartidas entre todos los usuarios de rclone. Esa cuota compartida es global (no depende de cuánto suba este dispositivo en particular) y en la práctica puede saturarse — ya pasó, dejando un `rclone copy` reintentando durante varios minutos con errores `403 rateLimitExceeded`. Todas las llamadas a `rclone` en este proyecto tienen un `timeout` de 90 segundos para que, si esto ocurre, el script en curso continúe igual (el archivo pendiente queda para la próxima sincronización) en vez de quedarse esperando indefinidamente. Si se desea eliminar esta dependencia de la cuota compartida, generar un Client ID y Client Secret propios en Google Cloud Console siguiendo la guía oficial de rclone: [https://rclone.org/drive/#making-your-own-client-id](https://rclone.org/drive/#making-your-own-client-id). 

**Verificación**

Verificar que la conexión funciona correctamente listando las carpetas de Google Drive:

```bash
rclone lsd gdrive:
```

Si el comando devuelve la lista de carpetas existentes en la cuenta de Google, la configuración fue exitosa.

### 10. Archivos de configuración

Los archivos `config_general.txt` y `config_horarios.txt` ya fueron copiados a `/home/lsd/` en el paso 8. Ahora hay que editarlos según las necesidades del dispositivo.

**Editar `config_general.txt`:**

```bash
nano /home/lsd/config_general.txt
```

El archivo contiene los siguientes parámetros:

```
FIRST_START = TRUE

LAT=<latitud_inicial>
LON=<longitud_inicial>

UMBRAL_BATERIA = <porcentaje_minimo_de_bateria>
VENTANA_ACTIVA = NONE
CIERRE_FORZADO = FALSE
```

Descripción de cada parámetro y cómo completarlo:

| Parámetro | Descripción |
|---|---|
| `FIRST_START` | Mantener en `TRUE` para activar el modo hotspot en el primer arranque. Una vez configurada la red WiFi exitosamente, el sistema lo cambia automáticamente a `FALSE`. |
| `LAT` y `LON` | Coordenadas geográficas del lugar de instalación. Pueden dejarse con valores aproximados ya que se actualizan automáticamente mediante geolocalización por IP al utilizar el modo hotspot. |
| `UMBRAL_BATERIA` | Porcentaje mínimo de batería. Toda ventana arranca siempre, sin importar el nivel de batería; este valor lo usa únicamente `chequeo_bateria.sh` para forzar un cierre anticipado si el nivel cae por debajo mientras la ventana está corriendo (ver más abajo). Valor recomendado: `15`. |
| `VENTANA_ACTIVA` | Estado interno: `NONE`, `amanecer` o `atardecer`, según si hay una ventana de grabación corriendo. La actualizan automáticamente `inicio_*.sh` y `cierre_*.sh`; no editar a mano salvo para depurar. |
| `CIERRE_FORZADO` | Estado interno: lo pone en `TRUE` `chequeo_bateria.sh` cuando detecta batería por debajo de `UMBRAL_BATERIA` con una ventana activa. `cierre_*.sh` lo consume y lo resetea a `FALSE`. No editar a mano salvo para depurar. |

> **Importante:** respetar el formato de cada línea. Las variables `LAT` y `LON` no llevan espacios alrededor del signo `=`. El resto de las variables sí llevan espacios.

**Mecanismo de corte por batería baja:** en vez de estimar de antemano cuánta batería va a consumir una ventana y decidir si arrancarla o no, el sistema siempre arranca la ventana y mide el nivel real de batería cada 5 minutos mientras está corriendo (`chequeo_bateria.sh`, agregado al crontab en el paso 15), cortándola apenas cae por debajo de `UMBRAL_BATERIA` sin esperar al horario de fin programado. Esto reemplaza al mecanismo anterior, que combinaba una fórmula de consumo estimado (`CONSUMO_W`/`CAPACIDAD_MAH`/`VOLTAJE_BATERIA`/`MARGEN_SEGURIDAD`) con un chequeo único al arranque de la ventana — un enfoque predictivo que en la práctica podía estar lejos del consumo real y que además no protegía contra una caída de batería a mitad de ventana.

El WiFi se enciende al arrancar la ventana y ya no se vuelve a apagar por software: queda activo de forma permanente (incluso después del cierre de la ventana), para que el dispositivo esté conectado en la medida de lo posible y sea posible reconectarse a él en cualquier momento.

**Editar `config_horarios.txt`:**

```bash
nano /home/lsd/config_horarios.txt
```

El archivo contiene los siguientes parámetros:

```
inicio_amanecer = 06:00
fin_amanecer = 08:00
inicio_atardecer = 17:00
fin_atardecer = 19:00

AUTO_SYNC=ON
duracion_amanecer_sync=<duracion_en_horas>
duracion_atardecer_sync=<duracion_en_horas>
```

Descripción de cada parámetro y cómo completarlo:

| Parámetro | Descripción |
|---|---|
| `inicio_amanecer`, `fin_amanecer`, `inicio_atardecer`, `fin_atardecer` | Los valores que se muestran son simplemente valores iniciales. Estos horarios se calculan y completan automáticamente con `astral` a partir de las coordenadas geográficas y las duraciones configuradas. |
| `AUTO_SYNC` | Mantener en `ON` para que el sistema recalcule automáticamente los horarios al final de cada ventana, usando la librería `astral` y las coordenadas del archivo `config_general.txt`. |
| `duracion_amanecer_sync` y `duracion_atardecer_sync` | Duración en horas de cada ventana de grabación. Reemplazar por la duración deseada (por ejemplo, `2` para una ventana de 2 horas). Es una duración máxima: la ventana puede cortarse antes si la batería cae por debajo de `UMBRAL_BATERIA`. |

> **Importante:** respetar el formato de cada línea. Las primeras cuatro variables (`inicio_amanecer`, `fin_amanecer`, `inicio_atardecer`, `fin_atardecer`) llevan espacios alrededor del signo `=`. Las demás no llevan espacios.

**Verificación**

Una vez editados ambos archivos, verificar que el contenido quedó correcto:

```bash
cat /home/lsd/config_general.txt
cat /home/lsd/config_horarios.txt
```

Revisar que todos los valores fueron reemplazados correctamente, que los espacios alrededor del signo `=` respetan el formato indicado, y que no quedaron placeholders del tipo `<...>` sin reemplazar.
### 11. Configurar el perfil de batería en la PiJuice

Este paso le indica a la PiJuice las características de la batería conectada para que el fuel gauge y el gestor de carga funcionen correctamente. Ejecutar el script provisto:

```bash
python3 /home/lsd/configurar_bateria_pijuice.py
```

> **Nota:** los parámetros del perfil de batería están definidos dentro del script `configurar_bateria_pijuice.py`. Si se utiliza una batería con características distintas (capacidad, voltaje de regulación, voltaje de corte, etc.), modificar los valores correspondientes en el script antes de ejecutarlo.

Verificar que el perfil quedó correctamente aplicado:

```bash
python3 -c "
import sys
sys.path.append('/home/lsd/BirdNET-Pi/PiJuice/Software/Source')
from pijuice import PiJuice
pj = PiJuice(1, 0x14)
print(pj.config.GetBatteryProfile())
"
```

La salida debe mostrar los parámetros configurados en el script.

### 12. Configurar el comportamiento de encendido de la PiJuice

Por defecto, la PiJuice enciende automáticamente la Raspberry Pi al detectar alimentación externa (por ejemplo, cuando el panel solar empieza a entregar potencia al amanecer). Este comportamiento no es deseado en el sistema LSD-Tector, donde la RP solo debe encenderse mediante la alarma programada del RTC.

Para deshabilitar el encendido automático, ejecutar:

```bash
python3 -c "
import sys
sys.path.append('/home/lsd/BirdNET-Pi/PiJuice/Software/Source')
from pijuice import PiJuice
pj = PiJuice(1, 0x14)
config = pj.config.GetPowerInputsConfig()['data']
config['no_battery_turn_on'] = True
pj.config.SetPowerInputsConfig(config)
print(pj.config.GetPowerInputsConfig())
"
```

La salida debe mostrar `'no_battery_turn_on': True`.


### 13. Habilitar la sincronización del reloj al arranque

La Raspberry Pi 4 no tiene reloj de tiempo real propio. La PiJuice registra su RTC como `rtc0` en el sistema, y ese RTC es el que conserva la hora cuando el dispositivo está apagado entre ventanas. El servicio `sync-rtc.service` copia la hora del RTC al reloj del sistema en cada arranque, mediante `hwclock --hctosys`.

Esto es imprescindible para la operación en campo: la PiJuice despierta a la Raspberry Pi a la hora programada, y este servicio garantiza que el reloj del sistema tenga la hora real correcta antes de que el crontab evalúe los horarios de las ventanas. Sin esta sincronización, tras un arranque sin conexión a internet el reloj del sistema quedaría con la hora del último apagado y las ventanas no dispararían a la hora correcta.

El archivo del servicio ya fue copiado a `/etc/systemd/system/` en el paso 8. Habilitarlo:

```bash
sudo systemctl enable sync-rtc.service
sudo systemctl start sync-rtc.service
```

Verificar que está activo:

```bash
sudo systemctl status sync-rtc.service
```

La salida debe indicar `active (exited)` o similar, sin errores.


### 14. Habilitar el servicio hotspot

El servicio `hotspot.service` ejecuta el script `hotspot.sh` al arrancar el sistema. Este script verifica si `FIRST_START=TRUE` en `config_general.txt` y, en ese caso, activa el modo hotspot para configurar la red WiFi. El archivo del servicio ya fue copiado a `/etc/systemd/system/` en el paso 8. Habilitarlo:

```bash
sudo systemctl enable hotspot.service
```

> **Nota:** no es necesario ejecutar `start` sobre este servicio en este momento. Se ejecutará automáticamente en el próximo arranque de la Raspberry Pi.

### 15. Configurar el crontab

El crontab define las tareas periódicas del sistema. Los cuatro scripts principales (`cierre_amanecer.sh`, `cierre_atardecer.sh`, `inicio_amanecer.sh`, `inicio_atardecer.sh`) y la rutina del botón deben ejecutarse cada minuto. Cada uno verifica internamente si la hora actual coincide con su horario configurado (o si `CIERRE_FORZADO` fue activado, en el caso de los `cierre_*.sh`) y, de ser así, ejecuta su rutina. `chequeo_bateria.sh` corre cada 5 minutos y mide la batería mientras hay una ventana activa. `sincronizar_detecciones.sh` también corre cada 5 minutos y, mientras hay una ventana activa, sube a Drive las detecciones ya grabadas hasta ese momento — así no se acumula todo para un único `rclone copy` grande al final de la ventana, y si la subida final de `cierre_*.sh` llegara a fallar (por ejemplo, por la cuota de Drive, ver la nota sobre `client_id`/`client_secret` en el paso 9), la mayoría de las detecciones ya están arriba de todas formas.

Abrir el crontab del usuario `lsd`:

```bash
crontab -e
```

> **Importante:** no utilizar `sudo` con este comando. El crontab debe pertenecer al usuario `lsd`, no a root.

La primera vez que se ejecuta, el sistema pregunta qué editor utilizar. Seleccionar `nano` (opción 1).

Al final del archivo, agregar las siguientes líneas:

```
* * * * * /home/lsd/cierre_amanecer.sh
* * * * * /home/lsd/cierre_atardecer.sh
* * * * * /home/lsd/inicio_amanecer.sh
* * * * * /home/lsd/inicio_atardecer.sh
* * * * * python3 /home/lsd/check_button.py
*/5 * * * * /home/lsd/chequeo_bateria.sh
*/5 * * * * /home/lsd/sincronizar_detecciones.sh
```

Guardar con **Ctrl+O**, Enter, y salir con **Ctrl+X**.

Verificar que las tareas quedaron registradas:

```bash
crontab -l
```

La salida debe mostrar las siete líneas agregadas.

Verificar también que el servicio cron está activo en el sistema:

```bash
sudo systemctl status cron
```

La salida debe mostrar `active (running)`. Si no estuviera activo, iniciarlo y habilitarlo para que arranque automáticamente con el sistema:

```bash
sudo systemctl enable cron
sudo systemctl start cron
```

**Actualización automática del dispositivo:** al final de cada `inicio_amanecer.sh`/`inicio_atardecer.sh` exitoso (con conexión), el dispositivo corre `actualizar_repo.sh`. Este script no mantiene ningún clon del repositorio en la Pi: consulta la API de GitHub para saber cuál es el último commit de la rama `main`, lo compara contra el último que aplicó (guardado en `/home/lsd/.ultima_actualizacion`) y, solo si cambió, descarga cada archivo de `scripts/`, `python/` y `systemd/` directamente desde GitHub (`raw.githubusercontent.com`) y los deja en su ubicación activa en `/home/lsd/`. Nunca toca `config_general.txt` ni `config_horarios.txt` (esos archivos guardan estado en vivo del dispositivo, no solo configuración). Como el repo es público, no requiere ninguna credencial en la Pi, ni `git` instalado más allá de lo necesario para el paso 8. Para publicar una actualización, simplemente hacer `git push` a la rama `main` de este repositorio — el dispositivo la va a levantar en su próxima ventana con conexión (hasta ~12 h de demora, no es instantáneo).

### 16. Crear carpetas en Google Drive y subir archivos de configuración

Crear las carpetas que utilizará el sistema en Google Drive:

```bash
rclone mkdir "gdrive:Laboratorio 6"
rclone mkdir "gdrive:Laboratorio 6/BirdNET_Detecciones"
```

Subir los archivos de configuración iniciales:

```bash
rclone copy /home/lsd/config_horarios.txt "gdrive:Laboratorio 6/"
rclone copy /home/lsd/config_general.txt "gdrive:Laboratorio 6/"
```

Verificar que los archivos fueron subidos correctamente:

```bash
rclone ls "gdrive:Laboratorio 6/"
```

La salida debe listar los dos archivos de configuración.

> **Nota:** los nombres de las carpetas en Google Drive (`Laboratorio 6` y `BirdNET_Detecciones`) están definidos por los scripts del sistema. Si se desea utilizar nombres diferentes, modificar las referencias correspondientes en todos los scripts antes de ejecutarlos.

---

## Primer arranque en campo

Una vez completados todos los pasos de instalación, el dispositivo está listo para ser desplegado en campo. El procedimiento de primer arranque es el siguiente:

1. Verificar que en `/home/lsd/config_general.txt` el parámetro `FIRST_START` está en `TRUE`.
2. Encender la Raspberry Pi. Esperar aproximadamente 30 segundos a que el sistema arranque completamente y se active el servicio `hotspot.service`.
3. Desde un celular o computadora, buscar redes WiFi disponibles. Conectarse a la red **LSD-Tector** con la contraseña `birdnet123`.
4. Abrir un navegador web y navegar a `http://192.168.4.1:5000`. Se mostrará el portal de configuración.
5. Seleccionar de la lista la red WiFi a la que se conectará el dispositivo en campo. Ingresar la contraseña correspondiente. Presionar **Conectar**.
6. El dispositivo se desconecta del modo hotspot e intenta conectarse a la red indicada. Si la conexión es exitosa:
   - Las coordenadas geográficas se actualizan automáticamente mediante geolocalización por IP.
   - Los horarios de amanecer y atardecer se calculan y se escriben en `config_horarios.txt`.
   - El parámetro `FIRST_START` se cambia a `FALSE`.
   - El dispositivo programa la alarma para la próxima ventana de grabación y se apaga.
7. Si la conexión falla, la red `LSD-Tector` vuelve a aparecer automáticamente. Reconectarse y reintentar con las credenciales correctas.
8. Si nadie completa la configuración dentro de los 15 minutos posteriores a activar el hotspot, el dispositivo se apaga automáticamente para no drenar la batería en vano. `FIRST_START` sigue en `TRUE`, así que el hotspot vuelve a activarse en el próximo encendido manual (botón físico o desconectando/reconectando la batería).

A partir de este momento, el dispositivo opera de forma completamente autónoma siguiendo el ciclo programado de ventanas de grabación.

---

## Control remoto via Google Drive

Una vez el dispositivo está en operación en campo, los archivos `config_horarios.txt` y `config_general.txt` en la carpeta `Laboratorio 6` de Google Drive pueden editarse desde cualquier lugar para modificar la configuración del dispositivo. Los cambios se aplican en el siguiente ciclo, cuando el dispositivo descarga la versión actualizada de Drive al final de la ventana de grabación.

El archivo `log_sistema.txt` se sube a Drive al final de cada ventana y permite monitorear el estado del dispositivo de forma remota: nivel de batería y cantidad de detecciones registradas. Un cierre forzado por batería baja (ver el mecanismo descripto en el paso 10) se registra igual que un cierre normal (`FIN ventana ...`), pero con un horario anterior al de fin programado y un nivel de batería cercano a `UMBRAL_BATERIA`.

Junto con `log_sistema.txt` también se sube `log_reciente.txt`, con el mismo contenido pero filtrado a solo los últimos 2 días — pensado para revisar la actividad reciente sin tener que scrollear todo el historial completo.

