#!/bin/bash

# CloudRDP Vanilla Bulletproof Setup Script
export DEBIAN_FRONTEND=noninteractive

echo "--- [1/4] Installing Core Components ---"
sudo apt-get update -qy
sudo apt-get install -y --no-install-recommends \
    xfce4 \
    xfce4-session \
    xrdp \
    xorgxrdp \
    xserver-xorg-core \
    xserver-xorg-video-dummy \
    dbus-x11 \
    x11-xserver-utils \
    tmate

echo "--- [2/4] Configuring Session ---"
USER_HOME=$(eval echo "~$(whoami)")
echo "xfce4-session" > $USER_HOME/.xsession
chmod +x $USER_HOME/.xsession
chown $(whoami):$(whoami) $USER_HOME/.xsession

# Fix Xorg permissions for headless runners
sudo sed -i 's/allowed_users=console/allowed_users=anybody/' /etc/X11/Xwrapper.config || echo "allowed_users=anybody" | sudo tee /etc/X11/Xwrapper.config > /dev/null

# Fix Polkit Color Manager hang
sudo mkdir -p /etc/polkit-1/localauthority/50-local.d
sudo tee /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla > /dev/null <<EOF
[Allow Colord all Users]
Identity=unix-user:*
Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile
ResultAny=no
ResultInactive=no
ResultActive=yes
EOF

echo "--- [3/4] Securing and Restarting ---"
touch $USER_HOME/.Xauthority 2>/dev/null || true
sudo chown $(whoami):$(whoami) $USER_HOME/.Xauthority 2>/dev/null || true

# Generate custom TLS certificates because GitHub Actions lacks the default snakeoil certs!
sudo openssl req -x509 -newkey rsa:2048 -nodes -keyout /etc/xrdp/key.pem -out /etc/xrdp/cert.pem -days 365 -subj "/C=US/ST=NY/L=NY/O=CloudRDP/CN=localhost" 2>/dev/null
sudo chown xrdp:xrdp /etc/xrdp/key.pem /etc/xrdp/cert.pem
sudo chmod 640 /etc/xrdp/key.pem
sudo chmod 644 /etc/xrdp/cert.pem

sudo sed -i 's|^certificate=.*|certificate=/etc/xrdp/cert.pem|' /etc/xrdp/xrdp.ini
sudo sed -i 's|^key_file=.*|key_file=/etc/xrdp/key.pem|' /etc/xrdp/xrdp.ini
sudo sed -i 's/^.*security_layer=.*/security_layer=negotiate/' /etc/xrdp/xrdp.ini
sudo sed -i 's/^.*crypt_level=.*/crypt_level=high/' /etc/xrdp/xrdp.ini

sudo adduser xrdp ssl-cert
sudo adduser $(whoami) ssl-cert

sudo systemctl enable xrdp
sudo service xrdp restart
sudo service xrdp-sesman restart

echo "--- [4/4] Setting Credentials ---"
CURRENT_USER=$(whoami)
echo "$CURRENT_USER:CloudRDP2026!" | sudo chpasswd
echo "root:CloudRDP2026!" | sudo chpasswd

echo "CloudRDP: Setup Complete."
