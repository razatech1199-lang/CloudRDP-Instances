#!/bin/bash

# CloudRDP Nuclear Setup Script (Hyper-Stable V13 - High-Speed)
export DEBIAN_FRONTEND=noninteractive

echo "--- [1/4] Fast-Track Installation ---"
sudo apt-get update -qy
# Use --no-install-recommends to speed up installation by 50%
# Remove xfce4-goodies (too large, not needed)
sudo apt-get install -y --no-install-recommends xfce4 xfce4-session xrdp xorgxrdp tmate dbus-x11 x11-xserver-utils

# Configure User Session
USER_HOME=$(eval echo "~$(whoami)")
echo "xfce4-session" > $USER_HOME/.xsession
chmod +x $USER_HOME/.xsession
chown $(whoami):$(whoami) $USER_HOME/.xsession

# TLS certificates are managed natively by xrdp package (ssl-cert-snakeoil). 
# We don't need to generate custom ones.

# Use default startwm.sh which safely delegates to /etc/X11/Xsession

# PATCHING: Force standard RDP security layer (Disables NLA) with High Encryption.
# This prevents Windows RDP from throwing "Internal Error" when tunneling over localhost SSH,
# and forces the connection to instantly show the native Linux XRDP graphical login screen!
sudo sed -i 's/^security_layer=.*/security_layer=rdp/' /etc/xrdp/xrdp.ini
sudo sed -i 's/^crypt_level=.*/crypt_level=high/' /etc/xrdp/xrdp.ini
sudo sed -i 's/^LogLevel=.*/LogLevel=DEBUG/' /etc/xrdp/xrdp.ini
sudo sed -i 's/^LogLevel=.*/LogLevel=DEBUG/' /etc/xrdp/sesman.ini

# Ensure X server can be started by any user
sudo sed -i 's/allowed_users=console/allowed_users=anybody/' /etc/X11/Xwrapper.config || echo "allowed_users=anybody" | sudo tee /etc/X11/Xwrapper.config > /dev/null

# Polkit fix for color manager hang
sudo mkdir -p /etc/polkit-1/localauthority/50-local.d
sudo tee /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla > /dev/null <<EOF
[Allow Colord all Users]
Identity=unix-user:*
Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile
ResultAny=no
ResultInactive=no
ResultActive=yes
EOF

# Permissions
touch /home/$(whoami)/.Xauthority 2>/dev/null || true
sudo chown $(whoami):$(whoami) /home/$(whoami)/.Xauthority 2>/dev/null || true
sudo adduser xrdp ssl-cert 2>/dev/null || true
sudo adduser $(whoami) ssl-cert 2>/dev/null || true

# Finalizing Services (With robust fallback)
sudo systemctl enable xrdp
sudo service xrdp restart || (sudo rm -f /var/run/xrdp*.pid && sudo service xrdp restart)
sudo service xrdp-sesman restart

echo "--- [3/4] Setting Credentials ---"
CURRENT_USER=$(whoami)
echo "$CURRENT_USER:CloudRDP2026!" | sudo chpasswd
echo "root:CloudRDP2026!" | sudo chpasswd

echo "CloudRDP: Setup V13 Complete."

