#!/bin/bash

# CloudRDP Absolute Minimalist Setup Script
# Restoring the exact universally proven method for GitHub Actions without hacks.

export DEBIAN_FRONTEND=noninteractive

echo "--- [1/3] Installing Dependencies ---"
sudo apt-get update -qy
# REMOVED --no-install-recommends to ensure background services (like snakeoil cert generators) run properly
sudo apt-get install -y xrdp xfce4 xfce4-goodies tmate

echo "--- [2/3] Configuring Session ---"
USER_HOME=$(eval echo "~$(whoami)")
echo "xfce4-session" > $USER_HOME/.xsession
chmod +x $USER_HOME/.xsession
chown $(whoami):$(whoami) $USER_HOME/.xsession

# Proven patch: insert startxfce4 before the Xsession execution
sudo sed -i.bak '/fi/a startxfce4' /etc/xrdp/startwm.sh

# Fix Xorg permissions for non-root users
sudo sed -i 's/allowed_users=console/allowed_users=anybody/' /etc/X11/Xwrapper.config || echo "allowed_users=anybody" | sudo tee /etc/X11/Xwrapper.config > /dev/null

echo "--- [3/3] Setting Credentials & Restarting ---"
CURRENT_USER=$(whoami)
echo "$CURRENT_USER:CloudRDP2026!" | sudo chpasswd
echo "root:CloudRDP2026!" | sudo chpasswd

sudo adduser xrdp ssl-cert
sudo systemctl restart xrdp
sudo systemctl restart xrdp-sesman

echo "CloudRDP: Minimal Setup Complete."
