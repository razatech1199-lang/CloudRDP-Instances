#!/bin/bash

# CloudRDP Absolute Final Setup Script
export DEBIAN_FRONTEND=noninteractive

echo "--- [1/4] Installing Core Components ---"
sudo apt-get update -qy
sudo apt-get install -y --no-install-recommends \
    xfce4 \
    xfce4-session \
    xfce4-terminal \
    xrdp \
    xorgxrdp \
    xserver-xorg-core \
    xserver-xorg-video-dummy \
    dbus-x11 \
    x11-xserver-utils \
    tmate \
    ssl-cert

echo "--- [2/4] Bulletproof startwm.sh ---"
# Bypass all native Xsession complexity and directly launch DBUS + XFCE4
sudo mv /etc/xrdp/startwm.sh /etc/xrdp/startwm.sh.bak
cat << 'EOF' | sudo tee /etc/xrdp/startwm.sh > /dev/null
#!/bin/sh
if [ -r /etc/default/locale ]; then
  . /etc/default/locale
  export LANG LANGUAGE
fi
export XDG_CURRENT_DESKTOP=XFCE
exec dbus-launch --exit-with-session startxfce4
EOF
sudo chmod +x /etc/xrdp/startwm.sh

echo "--- [3/4] Permissions & Polkit ---"
sudo sed -i 's/allowed_users=console/allowed_users=anybody/' /etc/X11/Xwrapper.config || echo "allowed_users=anybody" | sudo tee /etc/X11/Xwrapper.config > /dev/null

sudo mkdir -p /etc/polkit-1/localauthority/50-local.d
sudo tee /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla > /dev/null <<EOF
[Allow Colord all Users]
Identity=unix-user:*
Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile
ResultAny=no
ResultInactive=no
ResultActive=yes
EOF

echo "--- [4/4] Security & Restart ---"
# Custom TLS to prevent "Internal Error"
sudo openssl req -x509 -newkey rsa:2048 -nodes -keyout /etc/xrdp/key.pem -out /etc/xrdp/cert.pem -days 365 -subj "/C=US/ST=NY/L=NY/O=CloudRDP/CN=localhost" 2>/dev/null
sudo chown root:xrdp /etc/xrdp/key.pem
sudo chmod 640 /etc/xrdp/key.pem
sudo chmod 644 /etc/xrdp/cert.pem

sudo sed -i 's|^certificate=.*|certificate=/etc/xrdp/cert.pem|' /etc/xrdp/xrdp.ini
sudo sed -i 's|^key_file=.*|key_file=/etc/xrdp/key.pem|' /etc/xrdp/xrdp.ini
sudo sed -i 's/^.*security_layer=.*/security_layer=negotiate/' /etc/xrdp/xrdp.ini
# Fix TLS Cipher hang:
sudo sed -i 's/^.*tls_ciphers=.*/tls_ciphers=HIGH/' /etc/xrdp/xrdp.ini || echo "tls_ciphers=HIGH" | sudo tee -a /etc/xrdp/xrdp.ini

sudo adduser xrdp ssl-cert
sudo systemctl enable xrdp
sudo service xrdp restart
sudo service xrdp-sesman restart

CURRENT_USER=$(whoami)
echo "$CURRENT_USER:CloudRDP2026!" | sudo chpasswd
echo "root:CloudRDP2026!" | sudo chpasswd

echo "CloudRDP: Setup Complete."
