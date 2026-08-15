import sys
sys.path.append('/home/lsd/BirdNET-Pi/PiJuice/Software/Source')
from datetime import datetime
from pijuice import PiJuice

pj = PiJuice(1, 0x14)
nivel = pj.status.GetChargeLevel()['data']
evento = sys.argv[1]
ventana = sys.argv[2]

timestamp = datetime.now().strftime('%Y-%m-%d %H:%M')

if evento == 'FIN':
	proxima_ventana = sys.argv[3]
	detecciones = sys.argv[4] if len(sys.argv) > 4 else '0'
	linea = f"[{timestamp}] FIN ventana {ventana} | Batería: {nivel}% | Detecciones subidas: {detecciones} | Próxima ventana: {proxima_ventana}\n"
elif evento == 'SIN_CONEXION':
	proxima_ventana = sys.argv[3]
	detecciones = sys.argv[4] if len(sys.argv) > 4 else '0'
	linea = f"[{timestamp}] FIN ventana {ventana} | SIN CONEXIÓN, archivos se subirán en la próxima ventana | Batería: {nivel}% | Detecciones: {detecciones} | Próxima ventana: {proxima_ventana}\n"
else:
	fin_esperado = sys.argv[3]
	linea = f"[{timestamp}] INICIO ventana {ventana} | Batería: {nivel}% | Fin esperado: {fin_esperado}\n"

with open('/home/lsd/log_sistema.txt','a') as f:
	f.write(linea)

print(linea.strip())
