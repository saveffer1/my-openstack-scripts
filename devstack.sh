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
useradd -s /bin/bash -d /opt/stack -m stack || echo "[*] user 'stack' already exists."
chmod +x /opt/stack
echo "stack ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/stack

# === Set Password ===
HASH=$(openssl passwd -6 -salt "$(openssl rand -hex 8)" "$STACK_PASS")
echo "stack:${HASH}" | chpasswd -e

# === Clone DevStack ===
echo "[*] Cloning DevStack branch ${BRANCH}..."
sudo -u stack bash -c "
    cd /opt/stack
    if [[ ! -d devstack ]]; then
        git clone -b ${BRANCH} https://opendev.org/openstack/devstack
    fi
    cd devstack
    cp samples/local.conf local.conf
"

# === Generate local.conf ===
echo "[*] Generating local.conf..."
cat <<EOF > local.conf
[[local|localrc]]
HOST_IP=$HOST_IP
FLOATING_RANGE=$FLOATING_RANGE
IP_VERSION=4
EOF

# === Install Devstack ===
echo "[*] Installing DevStack..."
sudo byobu ~/devstack/stack.sh
echo "[*] DevStack installation completed successfully."

# === Install openstackclient ===
echo "[*] Installing openstackclient..."
sudo apt-get install -y python3-openstackclient

# === Post-installation Instructions ===
echo "=== Installation Complete ==="
echo "DevStack has been installed successfully."
echo "=== Post-installation Instructions ==="
echo "1. Source the DevStack environment:"
echo "   source ~/devstack/openrc"
echo "2. Show images:"
echo "   openstack image list"
echo "3. Access the Horizon dashboard at:"
echo "   http://$HOST_IP/dashboard"
echo "4. Show credentials:"
echo "   env | grep OS_"