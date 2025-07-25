#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
# Treat unset variables as an error.
# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -euo pipefail

# === Argument Check ===
if [[ $# -lt 2 ]]; then
    echo "[ERROR] Missing arguments."
    echo "Usage: $0 <HOST_IP> <FLOATING_RANGE> [BRANCH]"
    echo "Example: $0 192.168.27.100 172.24.4.0/24 stable/2025.1"
    exit 1
fi

# === Assign Arguments to Variables === 
HOST_IP="$1"
FLOATING_RANGE="$2"
BRANCH="${3:-stable/2025.1}"

# === Check root ===
if [[ "$EUID" -ne 0 ]]; then
    echo "[ERROR] This script must be run as root."
    echo "Usage: curl -sL <URL> | sudo bash -s <HOST_IP> <FLOATING_RANGE> [BRANCH]"
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

# === Debug Information ===
echo "--------------------------------------------------------"
echo "--- Starting DevStack Full Automation ---"
echo "Host IP:        $HOST_IP"
echo "Floating Range: $FLOATING_RANGE"
echo "DevStack Branch: $BRANCH"
echo "A random password has been generated for all services."
echo "--------------------------------------------------------"

# === 1. Add Stack User ===
if ! id -u stack >/dev/null 2>&1; then
    echo "-> Creating user 'stack'..."
    useradd -s /bin/bash -d /opt/stack -m stack
    echo "stack ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/stack
    chmod 0440 /etc/sudoers.d/stack
else
    echo "-> User 'stack' already exists."
fi
chmod 755 /opt/stack

# === 2. Clone Devstack Repo (as stack user) ===
DEVSTACK_DIR="/opt/stack/devstack"
if [[ ! -d "$DEVSTACK_DIR" ]]; then
    echo "-> Cloning DevStack repository (branch: $BRANCH)..."
    sudo -u stack git clone https://opendev.org/openstack/devstack.git "$DEVSTACK_DIR" -b "$BRANCH"
else
    echo "-> DevStack directory already exists. Skipping clone."
fi

# === 3. Create Local Configuration File (local.conf) ===
LOCAL_CONF_PATH="$DEVSTACK_DIR/local.conf"
SAMPLE_CONF_PATH="$DEVSTACK_DIR/samples/local.conf"

echo "-> Copying sample config and appending custom settings..."
cp "$SAMPLE_CONF_PATH" "$LOCAL_CONF_PATH"

# Append necessary settings for a fully non-interactive run.
cat << EOF >> "$LOCAL_CONF_PATH"

# --- Custom Settings for Automated Installation ---
HOST_IP=$HOST_IP
FLOATING_RANGE=$FLOATING_RANGE
IP_VERSION=4
EOF

# === 4. Set Ownership ===
echo "-> Setting ownership for /opt/stack..."
chown -R stack:stack /opt/stack

# === 5. Start DevStack Installation ===
echo ""
echo "--- ✅ System Prepared. Starting DevStack Installation... ---"
echo "This will take a long time. You can monitor the progress below."
echo "The output of stack.sh will be streamed here."
echo "----------------------------------------------------------------"
echo ""

# Execute stack.sh as the 'stack' user.
# The -H flag is important to set the HOME environment variable correctly.
sudo -H -u stack bash -c "cd /opt/stack/devstack && ./stack.sh"

# === 6. Post-Installation Configuration ===
echo ""
echo "--- ✅ DevStack Installation Completed ---"
echo ""
echo "-> install openstack client"
sudo apt install python3-openstackclient -y

# === Final Message ===
echo ""
echo "--- ✅ DevStack Installation Script has Finished ---"
echo "If there were no errors above, your OpenStack cloud should be running."
echo ""
echo "You can try accessing OpenStack image service with the following command:"
echo "su - stack"
echo "source /opt/stack/devstack/openrc"
echo "openstack image list"
echo ""
echo "To access the Horizon Dashboard, open your web browser and go to:"
echo "You can access the Horizon Dashboard at http://$HOST_IP/dashboard"
echo "User: admin"
env | grep 'OS_' | sed 's/^/OS_/' | sort
echo ""
