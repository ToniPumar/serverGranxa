#!/bin/bash

# === ACTUALIZACIÓN DEL SISTEMA ===
apt update && apt upgrade -y

# === HERRAMIENTAS BÁSICAS ===
apt install -y curl htop net-tools unzip software-properties-common ufw fail2ban python3 python3-pip docker.io docker-compose cockpit unattended-upgrades

# === USUARIO TONI CON SUDO ===
#useradd -m -s /bin/bash toni
#echo "toni:Aqui Contrasinal" | chpasswd
#usermod -aG sudo toni
usermod -aG docker toni

# === CONFIGURAR SSH SEGURO ===
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart ssh

# === CLAVE PÚBLICA PARA TONI (SUSTITUIR POR TU CLAVE REAL) ===
mkdir -p /home/toni/.ssh
echo "TU_CLAVE_PUBLICA" > /home/toni/.ssh/authorized_keys
chown -R toni:toni /home/toni/.ssh
chmod 700 /home/toni/.ssh
chmod 600 /home/toni/.ssh/authorized_keys

# Configurar UFW para usar solo red local (y Tailscale para remoto)
ufw default deny incoming
ufw default allow outgoing

# Permitir SSH y Cockpit desde red local (ajusta si usas otra subred)
ufw allow from 192.168.0.0/16 to any port 22 proto tcp
ufw allow from 192.168.0.0/16 to any port 9090 proto tcp

# Habilitar UFW si no lo está
ufw --force enable

# === FAIL2BAN ===
systemctl enable fail2ban
systemctl start fail2ban

# === COCKPIT ===
systemctl enable cockpit.socket
systemctl start cockpit.socket

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
