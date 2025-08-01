#!/bin/bash

# ------------------------------------------------------------
# Script unificado de despliegue para el servidor Granxa
#
# Este script prepara un servidor Debian/Ubuntu para ejecutar
# Home Assistant, Frigate, Mosquitto y CompreFace mediante
# Docker Compose.  Además, crea la estructura de carpetas de
# configuración, copia ficheros de configuración desde el
# repositorio y lanza los contenedores.
#
# Requisitos:
#   - Debe ejecutarse como root (sudo).
#   - El punto de montaje /mnt/frigate debe existir y estar
#     definido en /etc/fstab.
#   - Debe existir un usuario "toni" en el sistema.

# ----------------------------------------------------------------------------
# Variables configurables
# Es recomendable revisar estas variables antes de ejecutar el script.  Todas
# las reglas de cortafuegos y rutas usan estos valores.

USER_NAME="toni"              # usuario que executará os contedores
LOCAL_NET="192.168.0.0/24"   # rede local permitida por UFW
TAILSCALE_IFACE="tailscale0" # interface de Tailscale (por defecto tailscale0)

# Portos utilizados polos servizos.  Cambia estes valores se modificas os
# mapeos no ficheiro .env ou docker-compose.yml.
HOMEASSISTANT_PORT=8123        # Home Assistant (UI)
FRIGATE_UI_PORT=5000           # Frigate UI
FRIGATE_RTSP_PORT=8554         # Frigate RTSP re-stream
COCKPIT_PORT=9090              # Cockpit (administración web)

# Credenciais MQTT por defecto (modifica no .env).  Estes valores úsanse
# para xerar un ficheiro passwd en mosquitto se non existe.
MQTT_USERNAME="mqttuser"
MQTT_PASSWORD="mqttpass"

# Directorio base de este script (directorio del repositorio)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Rutas de destino en la máquina anfitriona
FRIGATE_CONFIG_DIR="/home/${USER_NAME}/frigate/config"
FRIGATE_CAMERAS_DIR="${FRIGATE_CONFIG_DIR}/cameras"
FRIGATE_AUTOMATIONS_DIR="/home/${USER_NAME}/frigate/automations"
HOMEASSISTANT_CONFIG_DIR="/home/${USER_NAME}/homeassistant/config"
MOSQUITTO_BASE_DIR="/home/${USER_NAME}/mosquitto"
COMPREFACE_DB_DIR="/home/${USER_NAME}/compreface-db"

# Archivo de configuración docker-compose y variables de entorno
COMPOSE_FILE="/home/${USER_NAME}/docker-compose.yml"
ENV_FILE="/home/${USER_NAME}/.env"

# Ficheros de configuración que se copiarán desde el repositorio
REPO_COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
REPO_ENV_FILE="${SCRIPT_DIR}/.env"
REPO_FRIGATE_CONFIG="${SCRIPT_DIR}/frigate/config"
REPO_AUTOMATIONS="${SCRIPT_DIR}/frigate/automations"
REPO_README="${SCRIPT_DIR}/README.md"

# Función de pausa con mensaje.  Mantener la interactividad
# ayuda a identificar errores en el proceso de instalación.  Si
# desea un script completamente desatendido, comente las
# llamadas a pausa.
pausa() {
  local msg="$1"
  echo
  read -rp "${msg} Pulse ENTER para continuar... "
  echo
}

echo -e "\n========== Configuración del servidor Granxa =========="

## --- Comprobaciones iniciales ---
echo "[INFO] Verificando precondiciones..."

# Comprobar que la partición /mnt/frigate existe
if [ ! -d /mnt/frigate ]; then
  echo "[ERROR] La ruta /mnt/frigate no existe. Conecte y monte el segundo disco en /mnt/frigate antes de continuar."
  exit 1
fi

# Comprobar que /mnt/frigate está declarada en /etc/fstab
if ! grep -qs '/mnt/frigate' /etc/fstab; then
  echo "[ERROR] El punto de montaje /mnt/frigate no está definido en /etc/fstab. Añádalo para que sea persistente y vuelva a ejecutar este script."
  exit 1
fi

# Comprobar que el usuario existe
if ! id -u "${USER_NAME}" >/dev/null 2>&1; then
  echo "[ERROR] El usuario '${USER_NAME}' no existe. Cree el usuario antes de continuar."
  exit 1
fi

pausa "Precondiciones comprobadas."

## --- Actualización del sistema y paquetes base ---
echo "[INFO] Actualizando lista de paquetes y sistema..."
apt update && apt upgrade -y

echo "[INFO] Instalando herramientas básicas y dependencias..."
# Instalación desde el repositorio de Docker oficial
apt install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  iputils-ping \
  net-tools \
  unzip \
  software-properties-common \
  libedgetpu1-std \
  ufw \
  fail2ban \
  python3 \
  python3-pip \
  mosquitto \
  mosquitto-clients \
  git \
  unattended-upgrades

# Instalar Docker Engine y Docker Compose desde el repositorio oficial
if ! command -v docker >/dev/null 2>&1; then
  echo "[INFO] Instalando Docker Engine desde el repositorio oficial..."
  curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") $(lsb_release -cs) stable\" \
    > /etc/apt/sources.list.d/docker.list
  apt update
  apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

# Añadir usuario al grupo docker para ejecutar contenedores sin sudo
echo "[INFO] Añadiendo al usuario '${USER_NAME}' al grupo docker..."
usermod -aG docker "${USER_NAME}"

pausa "Sistema actualizado e instaladas herramientas básicas."

## --- Instalación de Tailscale ---
echo "[INFO] Instalando Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

echo "[INFO] Configurando Tailscale (se abrirá una autenticación en el navegador si es necesario)..."
tailscale up --ssh || true

pausa "Tailscale instalado."

## --- Endurecimiento de SSH ---
echo "[INFO] Configurando acceso SSH: deshabilitando login por contraseña y root..."
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart ssh

pausa "SSH configurado."

## --- Configuración de UFW ---
echo "[INFO] Configurando el cortafuegos UFW..."
# Reiniciar reglas previas para asegurarnos de un estado limpio
ufw --force reset

# Denegar todo el tráfico entrante por defecto y permitir todo el tráfico saliente
ufw default deny incoming
ufw default allow outgoing

# Permitir tráfico entrante y saliente en la interfaz de Tailscale
ufw allow in on ${TAILSCALE_IFACE}
ufw allow out on ${TAILSCALE_IFACE}

# Permitir tráfico local para servicios básicos
ufw allow from ${LOCAL_NET} to any port 22 proto tcp              # SSH
ufw allow from ${LOCAL_NET} to any port ${COCKPIT_PORT} proto tcp # Cockpit
ufw allow from ${LOCAL_NET} to any port ${HOMEASSISTANT_PORT} proto tcp # Home Assistant
ufw allow from ${LOCAL_NET} to any port ${FRIGATE_UI_PORT} proto tcp    # Frigate UI
ufw allow from ${LOCAL_NET} to any port ${FRIGATE_RTSP_PORT} proto tcp  # Frigate RTSP
ufw allow from ${LOCAL_NET} to any port 1883 proto tcp              # Mosquitto
# No exponemos CompreFace fuera de localhost; no se abre puerto 8000

# Habilitar UFW
ufw --force enable

pausa "Cortafuegos configurado."

## --- Fail2Ban y Cockpit ---
echo "[INFO] Habilitando y arrancando servicios de seguridad (fail2ban) y administración (cockpit)..."
systemctl enable --now fail2ban
systemctl enable --now cockpit.socket

pausa "Servicios de seguridad y administración habilitados."

## --- Configuración de actualizaciones automáticas ---
echo "[INFO] Configurando actualizaciones automáticas de seguridad..."
dpkg-reconfigure --priority=low unattended-upgrades
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'CFGEOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Verbose "1";
CFGEOF

pausa "Actualizaciones automáticas configuradas."

## --- Configuración de logrotate para contedores Docker ---
echo "[INFO] Configurando rotación de logs para os contedores..."
cat > /etc/logrotate.d/docker-containers <<'LOGEOF'
/var/lib/docker/containers/*/*.log {
  rotate 4
  weekly
  compress
  delaycompress
  missingok
  copytruncate
}
LOGEOF

pausa "Logrotate configurado para os logs dos contedores."

## --- Preparación de directorios persistentes ---
echo "[INFO] Creando directorios para contenedores y datos persistentes..."

# Frigate: configuración, cámaras y automatizaciones
mkdir -p "${FRIGATE_CONFIG_DIR}" "${FRIGATE_CAMERAS_DIR}" "${FRIGATE_AUTOMATIONS_DIR}"
mkdir -p /mnt/frigate/media
mkdir -p /mnt/frigate/media/snapshots/matriculas /mnt/frigate/media/snapshots/coches /mnt/frigate/media/snapshots/caras /mnt/frigate/media/snapshots/personas

# Home Assistant
mkdir -p "${HOMEASSISTANT_CONFIG_DIR}"

# Mosquitto (config, data y log)
mkdir -p "${MOSQUITTO_BASE_DIR}/config" "${MOSQUITTO_BASE_DIR}/data" "${MOSQUITTO_BASE_DIR}/log"

# CompreFace: base de datos de PostgreSQL persistente para el contenedor
mkdir -p "${COMPREFACE_DB_DIR}"

pausa "Directorios creados."

## --- Copia de configuraciones y ficheros del repositorio ---
echo "[INFO] Copiando ficheros de configuración y automatizaciones..."

# Copiar docker-compose.yml si no existe o si hay cambios
cp "${REPO_COMPOSE_FILE}" "${COMPOSE_FILE}"
chown "${USER_NAME}:${USER_NAME}" "${COMPOSE_FILE}"

# Copiar archivo .env
cp "${REPO_ENV_FILE}" "${ENV_FILE}"
chown "${USER_NAME}:${USER_NAME}" "${ENV_FILE}"

# Copiar configuración de Frigate
if [ -d "${REPO_FRIGATE_CONFIG}" ]; then
  # Copiar general.yml
  if [ -f "${REPO_FRIGATE_CONFIG}/general.yml" ]; then
    cp "${REPO_FRIGATE_CONFIG}/general.yml" "${FRIGATE_CONFIG_DIR}/general.yml"
  fi
  # Copiar archivos de cámaras
  if [ -d "${REPO_FRIGATE_CONFIG}/cameras" ]; then
    cp -a "${REPO_FRIGATE_CONFIG}/cameras/." "${FRIGATE_CAMERAS_DIR}/"
  fi
fi

# Copiar scripts de automatización
if [ -d "${REPO_AUTOMATIONS}" ]; then
  cp -a "${REPO_AUTOMATIONS}/." "${FRIGATE_AUTOMATIONS_DIR}/"
fi

# Copiar README en gallego
if [ -f "${REPO_README}" ]; then
  cp "${REPO_README}" "/home/${USER_NAME}/README.md"
fi

# Establecer permisos para el directorio Mosquitto
chown -R "${USER_NAME}:${USER_NAME}" "${MOSQUITTO_BASE_DIR}"

pausa "Ficheros de configuración preparados."

## --- Configuración de Mosquitto ---
echo "[INFO] Preparando configuración de Mosquitto..."
cat > "${MOSQUITTO_BASE_DIR}/config/mosquitto.conf" <<'EOF'
persistence true
persistence_location /mosquitto/data/
log_dest file /mosquitto/log/mosquitto.log
allow_anonymous false
listener 1883
password_file /mosquitto/config/passwd
EOF

# Crear fichero de contraseñas si no existe
if [ ! -f "${MOSQUITTO_BASE_DIR}/config/passwd" ]; then
  echo "[INFO] Creando credenciales por defecto para Mosquitto (usuario mqttuser / contraseña mqttpass). Cambie estas credenciales posteriormente."
  mosquitto_passwd -c -b "${MOSQUITTO_BASE_DIR}/config/passwd" "${MQTT_USERNAME:-mqttuser}" "${MQTT_PASSWORD:-mqttpass}"
fi

chown -R "${USER_NAME}:${USER_NAME}" "${MOSQUITTO_BASE_DIR}"

pausa "Archivo docker-compose y configuración de Mosquitto preparados."

## --- Generación de configuración de Frigate ---
# Si existe el script generate_config.py en automatizaciones, generamos el
# fichero config.yml combinando general.yml y cámaras.
if [ -f "${FRIGATE_AUTOMATIONS_DIR}/generate_config.py" ]; then
  echo "[INFO] Generando configuración combinada de Frigate..."
  # Instalamos dependencias de Python necesarias para generar la configuración
  python3 -m pip install --no-cache-dir pyyaml >/dev/null 2>&1 || true
  python3 "${FRIGATE_AUTOMATIONS_DIR}/generate_config.py"
fi

## --- Lanzar contenedores principales ---
echo "[INFO] Iniciando todos los contenedores definidos en docker-compose.yml..."

# Cambiar ao directorio do usuario onde reside docker-compose.yml
# e executar docker compose como o usuario non privilexiado.  Isto
# evita que os ficheiros creados polos contedores pertenzan a root.
sudo -u "${USER_NAME}" bash -c "cd /home/${USER_NAME} && \
  docker compose --env-file '${ENV_FILE}' -f '${COMPOSE_FILE}' pull && \
  docker compose --env-file '${ENV_FILE}' -f '${COMPOSE_FILE}' up -d"

# Aseguramos que o servizo docker e containerd arranquen co sistema
systemctl enable docker
systemctl enable containerd

echo -e "\n[✓] Configuración completa.  Todos os servizos (Home Assistant, Frigate, Mosquitto, CompreFace, Frigate Listener e Watchtower) foron despregados utilizando un único ficheiro docker-compose.\n"