#!/bin/bash

set -euo pipefail

# === Check root ===
if [[ "$EUID" -ne 0 ]]; then
    echo "[ERROR] This script must be run as root."
    exit 1
fi

# === Check OS Version ===
. /etc/os-release

if [[ "$ID" != "ubuntu" ]]; then
    echo "[ERROR] This script only supports Ubuntu."
    exit 1
fi

if [[ "$VERSION_ID" != "22.04" && "$VERSION_ID" != "24.04" ]]; then
    echo "[ERROR] Unsupported Ubuntu version: $VERSION_ID"
    echo "This script supports only Ubuntu 22.04 and 24.04."
    exit 1
fi

echo "=== DevStack Installation Script ==="
echo "Please enter the required configuration values below..."

# === Interactive Input ===
read -rp "1) Password for user 'stack': " -s STACK_PASS
echo
read -rp "2) HOST_IP (e.g., 192.168.27.100): " HOST_IP
read -rp "3) FLOATING_RANGE (e.g., 172.24.4.0/24): " FLOATING_RANGE
read -rp "4) DevStack branch (default: stable/2025.1 just press Enter): " BRANCH
BRANCH=${BRANCH:-stable/2025.1}

# === Create User ===
echo "[*] Creating user 'stack'..."
STACK_USER=stack
DEST=/opt/stack

# Ensure group exists
if ! getent group $STACK_USER >/dev/null; then
    groupadd $STACK_USER
fi

# Ensure user exists
if ! id -u $STACK_USER >/dev/null 2>&1; then
    useradd -g $STACK_USER -s /bin/bash -d $DEST -m $STACK_USER
fi

# Ensure DEST exists (important if -m fails)
if [[ ! -d "$DEST" ]]; then
    mkdir -p "$DEST"
    chown "$STACK_USER:$STACK_USER" "$DEST"
fi

# Ensure DEST has executable bits for traversal
if [[ $(stat -c '%A' "$DEST" | grep -o x | wc -l) -lt 3 ]]; then
    chmod +x "$DEST"
fi

# Add sudoers include if missing
if ! grep -q "^#includedir.*/etc/sudoers.d" /etc/sudoers; then
    echo "#includedir /etc/sudoers.d" >> /etc/sudoers
fi

# Grant NOPASSWD sudo to stack user
echo "$STACK_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/50_stack_sh
chmod 440 /etc/sudoers.d/50_stack_sh


# === Set Password ===
HASH=$(openssl passwd -6 -salt "$(openssl rand -hex 8)" "$STACK_PASS")
echo "stack:${HASH}" | chpasswd -e

# === Clone DevStack ===
echo "[*] Cloning DevStack branch ${BRANCH}..."
sudo -u stack -i bash <<EOF
set -euo pipefail
cd /opt/stack
if [[ ! -d devstack ]]; then
    git clone -b ${BRANCH} https://opendev.org/openstack/devstack
fi
cd devstack
cp samples/local.conf /opt/stack/devstack/local.conf
EOF


# === Generate local.conf ===
echo "[*] Generating local.conf..."
sudo -u stack -i tee /opt/stack/devstack/local.conf >/dev/null <<EOF
#saveffer
#[[local|localrc]]
HOST_IP=$HOST_IP
FLOATING_RANGE=$FLOATING_RANGE
IP_VERSION=4
EOF

# === Install Devstack ===
echo "[*] Installing DevStack..."
sudo -u stack -i bash /opt/stack/devstack/stack.sh
echo "[*] DevStack installation completed successfully."

# === Install openstackclient ===
echo "[*] Installing openstackclient..."
sudo apt-get install -y python3-openstackclient

# === Post-installation Instructions ===
echo "=== Installation Complete ==="
echo "DevStack has been installed successfully."
echo "=== Post-installation Instructions ==="
echo "1. Source the DevStack environment:"
echo "   source /opt/stack/openrc"
echo "2. Show images:"
echo "   openstack image list"
echo "3. Access the Horizon dashboard at:"
echo "   http://$HOST_IP/dashboard"
echo "4. Show credentials:"
echo "   env | grep OS_"