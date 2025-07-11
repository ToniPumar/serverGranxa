#!/bin/bash
echo " +-+-+-+-+ +-+-+-+-+-+"
echo " |T|o|n|i| |P|u|m|a|r|"
echo " +-+-+-+-+ +-+-+-+-+-+"
echo "Script de configuración de servidor"
read -p "Recorde ter a clave publica agregada o documento para poder conectarse... pulsa"
read -p "Recorde ter montado o segundo disco en /mnt/frigate para proseguir co segundo escript"
echo "Iniciando script Toni pumar"
echo "Revisa las configuraciones y comenta las lineas pertinentes"
# === ACTUALIZACIÓN DEL SISTEMA ===
apt update && apt upgrade -y

# === HERRAMIENTAS BÁSICAS ===
apt install -y curl htop net-tools unzip software-properties-common ufw fail2ban python3 python3-pip docker.io docker-compose cockpit unattended-upgrades

# === USUARIO TONI CON SUDO ===
#useradd -m -s /bin/bash toni
#echo "toni:Aqui Contrasinal" | chpasswd
#usermod -aG sudo toni
usermod -aG docker toni

read -p "Actualizado e programas base instalados.. pulse para continuar"

# === CONFIGURAR SSH SEGURO ===
echo "[INFO] Desactivando acceso por contraseña y root en SSH..."

# Desactiva el login con contraseña
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config

# Desactiva login como root
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

# Reinicia SSH para aplicar cambios
systemctl restart ssh

read -p "Vamos a añadir clave publica"
# === CLAVE PÚBLICA PARA TONI ===
echo "[INFO] Añadiendo clave pública SSH para el usuario toni..."

mkdir -p /home/toni/.ssh

echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEuWxu0EjemploDeClavePublicaEnTextoPlanoUsuarioToni" > /home/toni/.ssh/authorized_keys

chown -R toni:toni /home/toni/.ssh
chmod 700 /home/toni/.ssh
chmod 600 /home/toni/.ssh/authorized_keys

echo "[✅] SSH seguro configurado con clave pública."

# Por defecto, denegar todo lo que entra
ufw default deny incoming

# Permitir todo lo que sale
ufw default allow outgoing

# Permitir tráfico entrante por la interfaz de Tailscale (remoto seguro)
ufw allow in on tailscale0

# Permitir tráfico desde la red local a servicios (ajusta el rango si es necesario)
ufw allow from 192.168.0.0/16 to any port 22 proto tcp     # SSH
ufw allow from 192.168.0.0/16 to any port 9090 proto tcp   # Cockpit
ufw allow from 192.168.0.0/16 to any port 8123 proto tcp   # Home Assistant
ufw allow from 192.168.0.0/16 to any port 5000:5500 proto tcp # Frigate (si usas ese rango)

# Habilitar UFW si no lo está
ufw --force enable

# === FAIL2BAN ===
systemctl enable fail2ban
systemctl start fail2ban

# === COCKPIT ===
systemctl enable cockpit.socket
systemctl start cockpit.socket

read -p "Preparate para instalar tailscale"
# === TAILSCALE VPN ===
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --ssh

# === ACTUALIZACIONES AUTOMÁTICAS SOLO DE SEGURIDAD ===
dpkg-reconfigure --priority=low unattended-upgrades
cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Verbose "1";
EOF

# === SNAPSHOT LVM SI EXISTE ===
if lvdisplay /dev/ubuntu-vg/root &>/dev/null; then
    lvcreate --size 2G --snapshot --name snap-basico /dev/ubuntu-vg/root
    echo "✅ Snapshot LVM creado: snap-basico"
else
    echo "⚠️ No se detecta LVM. No se ha creado snapshot."
fi

echo "✅ Configuración inicial completa."
