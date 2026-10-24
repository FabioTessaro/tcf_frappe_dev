#!/bin/bash
set -e

# Work relative to this script's location
cd "$(dirname "$0")"
source lib.sh 2>/dev/null || true

echo "======================================================"
echo "FTP Server Setup (vsftpd)"
echo "======================================================"

# Confirm with user whether to proceed with FTP setup
if command -v confirm &> /dev/null; then
  if ! confirm "Do you want to set up and configure the FTP server (vsftpd)?"; then
    echo "Skipping FTP setup."
    exit 0
  fi
else
  read -r -p "Do you want to set up and configure the FTP server (vsftpd)? [y/N]: " reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *) echo "Skipping FTP setup."; exit 0 ;;
  esac
fi

# Prompt for the FTP username, defaulting to the current user (e.g. fabio or ubuntu)
DEFAULT_USER="${SUDO_USER:-$USER}"
read -r -p "Enter the system username to allow for FTP access [$DEFAULT_USER]: " FTP_USER
FTP_USER="${FTP_USER:-$DEFAULT_USER}"

if ! id "$FTP_USER" &>/dev/null; then
  echo "Error: User '$FTP_USER' does not exist on this system."
  echo "Please create the user first (e.g., sudo adduser $FTP_USER) before running this setup."
  exit 1
fi

echo "Setting up FTP for user: $FTP_USER"

# 1. Install vsftpd if not installed
if ! dpkg -l | grep -q vsftpd; then
  echo "Installing vsftpd..."
  sudo apt update
  sudo apt install -y vsftpd
fi

# Ensure service is enabled and started
sudo systemctl enable vsftpd

# 2. Configure /etc/vsftpd.conf
CONFIG_FILE="/etc/vsftpd.conf"
if [ -f "$CONFIG_FILE" ]; then
  if [ ! -f "${CONFIG_FILE}.bak" ]; then
    echo "Backing up default $CONFIG_FILE to ${CONFIG_FILE}.bak"
    sudo cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
  fi
fi

echo "Updating $CONFIG_FILE..."

set_vsftpd_conf() {
  local key="$1"
  local value="$2"
  if sudo grep -q "^[#[:space:]]*${key}=" "$CONFIG_FILE"; then
    sudo sed -i "s|^[#[:space:]]*${key}=.*|${key}=${value}|" "$CONFIG_FILE"
  else
    echo "${key}=${value}" | sudo tee -a "$CONFIG_FILE" > /dev/null
  fi
}

set_vsftpd_conf "anonymous_enable" "NO"
set_vsftpd_conf "local_enable" "YES"
set_vsftpd_conf "write_enable" "YES"
set_vsftpd_conf "chroot_local_user" "YES"
set_vsftpd_conf "allow_writeable_chroot" "YES"
set_vsftpd_conf "userlist_enable" "YES"
set_vsftpd_conf "userlist_file" "/etc/vsftpd.userlist"
set_vsftpd_conf "userlist_deny" "NO"
set_vsftpd_conf "pasv_min_port" "40000"
set_vsftpd_conf "pasv_max_port" "50000"

# 3. Configure /etc/vsftpd.userlist
echo "Configuring FTP user list..."
echo "$FTP_USER" | sudo tee /etc/vsftpd.userlist > /dev/null

# 4. Configure Firewall (UFW)
if command -v ufw &> /dev/null && sudo ufw status | grep -q "Status: active"; then
  echo "Configuring UFW firewall rules for FTP..."
  sudo ufw allow 20,21/tcp
  sudo ufw allow 40000:50000/tcp
  sudo ufw reload
else
  echo "UFW is not active or installed. Skipping firewall rules adjustment."
  echo "Note: If your server is behind an external firewall (AWS Security Groups, GCP Firewall, etc.), ensure TCP ports 21 and 40000-50000 are open."
fi

# 5. Restart vsftpd
echo "Restarting vsftpd service..."
sudo systemctl restart vsftpd

echo "======================================================"
echo "FTP setup complete!"
echo "User '$FTP_USER' can now connect via FTP (Port 21) using their system password."
echo "======================================================"