#!/bin/bash

echo "[INFO] === INICIO DEL SCRIPT DE CONFIGURACIÓN DE SERVICIOS ==="

# 1. Verificar si el punto de montaje está en /etc/fstab
echo "[INFO] Verificando si /mnt/frigate está configurado en /etc/fstab..."
if ! grep -qs "/mnt/frigate" /etc/fstab; then
  echo "[ERROR] El punto de montaje /mnt/frigate no está en /etc/fstab."
  echo "Por favor configúralo antes de ejecutar este script."
  exit 1
fi

# 2. Crear directorios necesarios
echo "[INFO] Creando carpetas para Frigate, Home Assistant y Mosquitto..."
mkdir -p /home/toni/frigate/config
mkdir -p /mnt/frigate/media
mkdir -p /home/toni/homeassistant/config
mkdir -p /home/toni/mosquitto/config
mkdir -p /home/toni/mosquitto/data
mkdir -p /home/toni/mosquitto/log

# 3. Copiar archivos necesarios
echo "[INFO] Copiando archivo docker-compose.yml..."
cp ./docker-compose.yml /home/toni/docker-compose.yml

echo "[INFO] Copiando archivo mosquitto.conf..."
cat <<EOF > /home/toni/mosquitto/config/mosquitto.conf
persistence true
persistence_location /mosquitto/data/
log_dest file /mosquitto/log/mosquitto.log
allow_anonymous true
listener 1883
EOF

# 4. Asegurar que Docker esté activo
echo "[INFO] Asegurando que Docker esté activo..."
systemctl start docker

# 5. Lanzar contenedores con Docker Compose
echo "[INFO] Lanzando los contenedores con Docker Compose..."
cd /home/toni
docker compose up -d

if [ $? -ne 0 ]; then
  echo "[ERROR] Falló el arranque de Docker Compose. Verifica el archivo docker-compose.yml y el estado de Docker."
  exit 1
fi

# 6. Asegurar que Docker arranque siempre al iniciar el sistema
echo "[INFO] Habilitando Docker al arranque..."
systemctl enable docker

echo "[OK] Todos los servicios están en marcha y arrancarán automáticamente al reiniciar el servidor."
echo "[OK] Frigate, Home Assistant y Mosquitto están en marcha."
