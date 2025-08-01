Servidor Granxa – Manual en Galego

Este proxecto recolle a configuración e scripts necesarios para
despregar un pequeno servidor doméstico orientado á videovixiancia e
domótica.  Utilízase Docker Compose para levantar os
contedores de Home Assistant, Frigate (NVR con IA), Mosquitto,
CompreFace e un listener en Python que automatiza o recoñecemento de
caras e matrículas.  Ademais, engádese o servizo Watchtower para
mantelos actualizados.

Estrutura do proxecto
serverGranxa/
├── docker-compose.yml        # definición de contedores
├── .env                      # variables sensibles (copiar de .env.example)
├── setup-toni.sh            # script de instalación e despliegue
├── frigate/
│   ├── config/
│   │   ├── general.yml       # configuración global de Frigate
│   │   └── cameras/
│   │       ├── cam1.yml      # configuración individual de cada cámara
│   │       ├── cam2.yml
│   │       ├── cam3.yml
│   │       ├── cam4.yml
│   │       └── cam5.yml
│   └── automations/
│       ├── generate_config.py # xera config.yml combinando general+cámaras
│       ├── event_listener.py  # escoita eventos de Frigate via MQTT
│       ├── utils.py           # funcións auxiliares
│       └── known_plates.json  # matrículas coñecidas
└── README.md                # este manual

docker-compose.yml

Define os servizos e montaxes de volumes.  Os puntos salientables son:
	•	Home Assistant expón a súa interface no porto 8123 da máquina
anfitrioa e utiliza /home/toni/homeassistant/config como volume
persistente.
	•	Frigate corre en modo host e usa a Coral PCIe para
aceleración; monta /home/toni/frigate/config en /config,
/mnt/frigate/media en /media/frigate e as automatizacións en
/automations.  A configuración final xérase a partir de
general.yml e os ficheiros de cámaras.
	•	Mosquitto é un broker MQTT local; o script xera un
mosquitto.conf que desactiva o acceso anónimo e crea unhas
credenciais por defecto (debense cambiar).
	•	CompreFace só escoita en localhost:8000, polo que non é
accesible dende Tailscale a non ser que se modifique a ligazón
(podese modificar en docker-compose).  Serve para recoñecer
identidade facial a través do API.
	•	frigate-listener é un contedor Python baseado en
python:3.11-slim que instala paho-mqtt, requests e
PyYAML e executa event_listener.py.  Este script subscribe
aos eventos de Frigate e consulta CompreFace e a lista de
matrículas para xerar notificacións.  Só enviará unha
notificación por identificador cada hora.
	•	Watchtower supervisa todos os contedores e comproba periodicamente se hai
unha nova imaxe dispoñible.  Se a hai, actualízaa automaticamente e
elimina as imaxes antigas (--cleanup).  Isto simplifica a
actualización pero hai que ter en conta que pode reiniciar
contedores de xeito non planificado.

setup-toni.sh

Este script automatiza a preparación do servidor:
	1.	Comprobacións: verifica que /mnt/frigate existe e está en
/etc/fstab e que o usuario toni existe.
	2.	Actualización do sistema e instalación de paquetes: instala
dependencias básicas, docker e docker-compose desde o repositorio
oficial, Tailscale, UFW e Fail2Ban.
	3.	Seguridade: desactiva o login por contrasinal para SSH,
restablece as regras de UFW e abre só os portos necesarios
(22, 9090, 8123, 5000, 8554 e 1883) na rede local
192.168.0.0/24; o porto 8000 de CompreFace non se expón.
	4.	Carpetas persistentes: crea as carpetas
/home/toni/frigate/config/cameras, /home/toni/frigate/automations,
/mnt/frigate/media e subcarpetas de snapshots, ademais das rutas
para Home Assistant, Mosquitto e CompreFace.
	5.	Copia de configuracións: copia docker-compose.yml, .env,
os ficheiros de configuración de Frigate e os scripts de
automatización ao home do usuario se non existen.
	6.	Configuración de Mosquitto: xera un mosquitto.conf básico e
crea un ficheiro de contrasinais.  As credenciais por defecto
(usuario mqttuser, contrasinal mqttpass) están definidas no
script e tamén no ficheiro .env; débense cambiar antes de poñer o
sistema en produción.
	7.	Xeración de configuración de Frigate: se existe
generate_config.py, combínase general.yml cos ficheiros de
cámaras e créase config.yml.
	8.	Despregar contedores: executa docker compose pull para
descargar as imaxes máis recentes e docker compose up -d para
iniciar todos os servizos.  Tamén activa os servizos docker e
containerd no arranque.

Automatizacións en Python
	•	generate_config.py: combina a configuración xeral coa das
cámaras para xerar config.yml.  Úsase no script de instalación.
	•	event_listener.py: subscribe a frigate/events e procesa
eventos de persoas e coches.  Consulta CompreFace para saber se a
cara é coñecida e compara matrículas con
known_plates.json.  Utiliza utils.py para determinar se se
debe notificar (non máis dunha vez por hora por identificador) e
imprime as notificacións por consola.  Podes modificar
notify_user() para integrar Telegram, Home Assistant ou outro
sistema de avisos.
	•	utils.py: contén funcións auxiliares como
check_face() (consulta o API de CompreFace),
check_plate() (esqueleto para recoñecemento de matrículas),
should_notify() (controla o tempo de espera) e
notify_user() (envía mensaxes).
	•	known_plates.json: lista de matrículas autorizadas.  Podes
engadir ou eliminar entradas en formato clave/valor.

Watchtower e logrotación

Watchtower é un servizo que comproba periodicamente se hai
actualizacións das imaxes docker utilizadas.  Se atopa unha versión
máis recente, descárgaa e reinicia o contedor.  A opción
--cleanup elimina as imaxes antigas para liberar espazo.  Isto
permite manter os contedores ao día sen intervención manual, pero é
recomendable revisar as notas de versión antes de actualizar en
entornos de produción.

Todos os servizos están configurados para usar o driver de log
json-file con rotación: cada ficheiro de log ten un tamaño
máximo de 10 MB e gárdanse ata 3 ficheiros.  Isto evita que os logs
enchen o disco.  Os logs pódense consultar con docker logs <contedor>.

Adicionalmente, o script setup-toni.sh instala un ficheiro
logrotate en /etc/logrotate.d/docker-containers que xestiona a
rotación dos ficheiros *.log dentro de /var/lib/docker/containers.
Esta configuración realiza unha rotación semanal, conserva catro
versiones comprimidas e emprega copytruncate para evitar perdas
mentres os contedores escriben.  Grazas a isto, o sistema non se
saturará por logs antigos.

Acceso por Tailscale

Podes acceder á interface web de Home Assistant, Frigate e
CompreFace a través de Tailscale.  Como CompreFace está ligado a
127.0.0.1, non se expón por defecto; se desexas consultalo desde
Tailscale, modifica o porto na sección compreface de
docker-compose para que escoite en todas as interfaces.

Pasos para despregar
	1.	Editar .env: copia o ficheiro .env e personaliza as
contrasinais e as claves de API.
	2.	Executar o script: como root,
cd serverGranxa
chmod +x setup-toni.sh
sudo ./setup-toni.sh

	3.	Configurar CompreFace: accede a http://127.0.0.1:8000
dende a máquina anfitrioa, crea unha aplicación e copia a API key
no ficheiro .env.
	4.	Editar as cámaras: cambia as URLs RTSP e parámetros nos
ficheiros cam?.yml segundo corresponda.  Volve executar
generate_config.py ou deixa que o script o faga por ti.

Con estes pasos, terás un sistema integrado que grava as túas cámaras,
detecta persoas e caras, recoñece matrículas e envía notificacións de
forma intelixente.  Lembra revisar periodicamente as actualizacións e
facer copias de seguridade das carpetas de configuración e medios.
