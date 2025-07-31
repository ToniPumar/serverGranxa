#!/bin/bash

# ------------------------------------------------------------
# Script unificado de despliegue para el servidor Granxa
#
# Requisitos:
#   - Debe ejecutarse como root (sudo).
#   - El punto de montaje /mnt/frigate debe existir y estar definido en
#     /etc/fstab.
#   - Debe existir un usuario "toni" en el sistema.

set -e

# Ruta del directorio donde reside este script (directorio del repo)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Función de pausa con mensaje
pausa() {
  local msg="$1"
  echo
  read -rp "${msg} Pulse ENTER para continuar... "
  echo
}

echo "\n========== Configuración del servidor Granxa =========="

# --- Comprobaciones iniciales ---
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

# Comprobar que el usuario toni existe
if ! id -u toni >/dev/null 2>&1; then
  echo "[ERROR] El usuario 'toni' no existe. Cree el usuario antes de continuar."
  exit 1
fi

pausa "Precondiciones comprobadas."

# --- Actualización del sistema y paquetes base ---
echo "[INFO] Actualizando lista de paquetes y sistema..."
apt update && apt upgrade -y

echo "[INFO] Instalando herramientas básicas y dependencias..."
apt install -y curl iputils-ping net-tools unzip software-properties-common libedgetpu1-std \
  ufw fail2ban python3 python3-pip docker.io docker-compose git unattended-upgrades mosquitto mosquitto-clients

# Añadir usuario toni al grupo docker para poder ejecutar contenedores sin sudo
echo "[INFO] Añadiendo al usuario 'toni' al grupo docker..."
usermod -aG docker toni

pausa "Sistema actualizado e instaladas herramientas básicas."

# --- Instalación de Tailscale ---
echo "[INFO] Instalando Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

# Levantar Tailscale con soporte SSH.  Esto solicitará autenticación en
# el dispositivo de administración y habilitará acceso cifrado.
echo "[INFO] Configurando Tailscale (se abrirá una autenticación en el navegador si es necesario)..."
tailscale up --ssh || true

pausa "Tailscale instalado."

# --- Endurecimiento de SSH ---
echo "[INFO] Configurando acceso SSH: deshabilitando login por contraseña y root..."
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart ssh

pausa "SSH configurado."

# --- Configuración de UFW ---
echo "[INFO] Configurando el cortafuegos UFW..."
# Reiniciar reglas previas para asegurarnos de un estado limpio
ufw --force reset

# Denegar todo el tráfico entrante por defecto y permitir todo el tráfico saliente
ufw default deny incoming
ufw default allow outgoing

# Permitir tráfico entrante y saliente en la interfaz de Tailscale
ufw allow in on tailscale0
ufw allow out on tailscale0

# Definir red local (ajuste esto si su red local no es 192.168.0.0/24)
LOCAL_NET="192.168.0.0/24"

# Permitir tráfico local para servicios básicos
ufw allow from ${LOCAL_NET} to any port 22 proto tcp      # SSH
ufw allow from ${LOCAL_NET} to any port 9090 proto tcp    # Cockpit
ufw allow from ${LOCAL_NET} to any port 8123 proto tcp    # Home Assistant
ufw allow from ${LOCAL_NET} to any port 5000:5500 proto tcp # Frigate
ufw allow from ${LOCAL_NET} to any port 1883 proto tcp    # Mosquitto
ufw allow from ${LOCAL_NET} to any port 8000 proto tcp    # CompreFace (UI)

# Habilitar UFW
ufw --force enable

pausa "Cortafuegos configurado."

# --- Fail2Ban y Cockpit ---
echo "[INFO] Habilitando y arrancando servicios de seguridad (fail2ban) y administración (cockpit)..."
systemctl enable --now fail2ban
systemctl enable --now cockpit.socket

pausa "Servicios de seguridad y administración habilitados."

# --- Configuración de actualizaciones automáticas ---
echo "[INFO] Configurando actualizaciones automáticas de seguridad..."
dpkg-reconfigure --priority=low unattended-upgrades
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'CFGEOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Verbose "1";
CFGEOF

pausa "Actualizaciones automáticas configuradas."

# --- Preparación de directorios persistentes ---
echo "[INFO] Creando directorios para contenedores y datos persistentes..."

# Frigate: configuración, automatizaciones y almacenamiento de medios
mkdir -p /home/toni/frigate/config
mkdir -p /home/toni/frigate/automations
mkdir -p /mnt/frigate/media
mkdir -p /mnt/frigate/media/snapshots/matriculas
mkdir -p /mnt/frigate/media/snapshots/coches
mkdir -p /mnt/frigate/media/snapshots/caras
mkdir -p /mnt/frigate/media/snapshots/personas

# Home Assistant
mkdir -p /home/toni/homeassistant/config

# Mosquitto
mkdir -p /home/toni/mosquitto/config /home/toni/mosquitto/data /home/toni/mosquitto/log

# CompreFace: base de datos de PostgreSQL persistente para el contenedor
mkdir -p /home/toni/compreface-db

pausa "Directorios creados."

# --- Configuración de Docker Compose y Mosquitto ---
echo "[INFO] Preparando archivos de configuración para Docker Compose y Mosquitto..."

# Copiar el archivo docker-compose.yml del repositorio al home de toni
cp "${SCRIPT_DIR}/docker-compose.yml" /home/toni/docker-compose.yml
chown toni:toni /home/toni/docker-compose.yml

# Generar configuración de Mosquitto más segura (modifique según sus necesidades)
cat > /home/toni/mosquitto/config/mosquitto.conf <<'EOF'
persistence true
persistence_location /mosquitto/data/
log_dest file /mosquitto/log/mosquitto.log
allow_anonymous false
listener 1883
password_file /mosquitto/config/passwd
EOF

# Crear fichero de contraseñas para Mosquitto con credenciales de ejemplo
if [ ! -f /home/toni/mosquitto/config/passwd ]; then
  echo "[INFO] Creando credenciales por defecto para Mosquitto (usuario mqttuser / contraseña mqttpass). Cambie estas credenciales posteriormente."
  mosquitto_passwd -c -b /home/toni/mosquitto/config/passwd mqttuser mqttpass
fi

chown -R toni:toni /home/toni/mosquitto

pausa "Archivo docker-compose y configuración de Mosquitto preparados."

# --- Lanzar contenedores principales ---
echo "[INFO] Iniciando todos los contenedores definidos en docker-compose.yml (Home Assistant, Frigate, Mosquitto y CompreFace) ..."

# Cambiar al directorio del usuario toni donde reside docker-compose.yml
cd /home/toni

# Levantar todos los servicios definidos en el archivo docker-compose.yml.  Esto
# incluye Home Assistant, Frigate, Mosquitto y CompreFace en un único
# docker-compose, tal como solicita el usuario.
docker compose -f docker-compose.yml up -d

# Asegurar que el servicio docker arranca al iniciar el sistema
systemctl enable docker

echo "\n[✓] Configuración completa. Todos los servicios (Home Assistant, Frigate, Mosquitto y CompreFace) se han desplegado utilizando un único archivo docker-compose.\n"
