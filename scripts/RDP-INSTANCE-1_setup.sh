#!/bin/bash

# CloudRDP Nuclear Setup Script (Hyper-Stable V13 - High-Speed)
export DEBIAN_FRONTEND=noninteractive

echo "--- [1/4] Fast-Track Installation ---"
sudo apt-get update -qy
# Use --no-install-recommends to speed up installation by 50%
# Remove xfce4-goodies (too large, not needed)
sudo apt-get install -y --no-install-recommends xfce4 xfce4-session xrdp xorgxrdp tmate dbus-x11

# Configure User Session
USER_HOME=$(eval echo "~$(whoami)")
echo "exec dbus-launch --exit-with-session startxfce4" > $USER_HOME/.xsession
chmod +x $USER_HOME/.xsession
chown $(whoami):$(whoami) $USER_HOME/.xsession

# Generate certificates
sudo openssl req -x509 -newkey rsa:2048 -nodes -keyout /etc/xrdp/key.pem -out /etc/xrdp/cert.pem -days 365 -subj "/C=US/ST=NY/L=NY/O=CloudRDP/CN=localhost" 2>/dev/null
sudo chown xrdp:xrdp /etc/xrdp/key.pem /etc/xrdp/cert.pem

# CRITICAL: Robust startwm.sh
sudo tee /etc/xrdp/startwm.sh <<EOF
#!/bin/sh
if [ -r /etc/default/locale ]; then
  . /etc/default/locale
  export LANG
fi
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
unset XDG_SESSION_ID
exec dbus-launch --exit-with-session /usr/bin/startxfce4
EOF
sudo chmod +x /etc/xrdp/startwm.sh

# PATCHING (Fast & Safe)
sudo sed -i 's/^security_layer=.*/security_layer=negotiate/' /etc/xrdp/xrdp.ini
sudo sed -i 's/^crypt_level=.*/crypt_level=high/' /etc/xrdp/xrdp.ini
sudo sed -i 's/^LogLevel=.*/LogLevel=DEBUG/' /etc/xrdp/xrdp.ini
sudo sed -i 's/^LogLevel=.*/LogLevel=DEBUG/' /etc/xrdp/sesman.ini
sudo sed -i 's|^certificate=.*|certificate=/etc/xrdp/cert.pem|' /etc/xrdp/xrdp.ini
sudo sed -i 's|^key_file=.*|key_file=/etc/xrdp/key.pem|' /etc/xrdp/xrdp.ini

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

