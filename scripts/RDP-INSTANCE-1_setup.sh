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

# PROVEN TLS FIX: Prevent "Internal Error" from broken snakeoil certs and OpenSSL bugs
sudo openssl req -x509 -newkey rsa:2048 -nodes -keyout /etc/xrdp/key.pem -out /etc/xrdp/cert.pem -days 365 -subj "/C=US/ST=NY/L=NY/O=CloudRDP/CN=localhost" 2>/dev/null
sudo chown root:xrdp /etc/xrdp/key.pem
sudo chmod 640 /etc/xrdp/key.pem
sudo chmod 644 /etc/xrdp/cert.pem

sudo sed -i 's|^certificate=.*|certificate=/etc/xrdp/cert.pem|' /etc/xrdp/xrdp.ini
sudo sed -i 's|^key_file=.*|key_file=/etc/xrdp/key.pem|' /etc/xrdp/xrdp.ini
sudo sed -i 's/^.*security_layer=.*/security_layer=negotiate/' /etc/xrdp/xrdp.ini
sudo sed -i 's/^.*tls_ciphers=.*/tls_ciphers=HIGH/' /etc/xrdp/xrdp.ini || echo "tls_ciphers=HIGH" | sudo tee -a /etc/xrdp/xrdp.ini

sudo adduser xrdp ssl-cert
sudo systemctl restart xrdp
sudo systemctl restart xrdp-sesman

echo "CloudRDP: Minimal Setup Complete."
