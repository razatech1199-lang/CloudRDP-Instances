#!/bin/bash

# CloudRDP Robust Setup Script
# Hardened for Ubuntu 22.04 GitHub Actions Runners to prevent "Configuring remote session" hangs.

export DEBIAN_FRONTEND=noninteractive

echo "--- [1/3] Installing Hardened Dependencies ---"
sudo apt-get update -qy
sudo apt-get install -y xrdp xorgxrdp xfce4 xfce4-goodies dbus-x11 tmate

echo "--- [2/3] Configuring Session & Services ---"
USER_HOME=$(eval echo "~$(whoami)")
echo "xfce4-session" > $USER_HOME/.xsession
chmod +x $USER_HOME/.xsession
chown $(whoami):$(whoami) $USER_HOME/.xsession

# Fix Polkit issues that cause hangs
sudo tee /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla <<EOF
[Allow Colord all Users]
Identity=unix-user:*
Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile
ResultAny=no
ResultInactive=no
ResultActive=yes
EOF

# Hardened startwm.sh
sudo mv /etc/xrdp/startwm.sh /etc/xrdp/startwm.sh.bak
cat << 'EOF' | sudo tee /etc/xrdp/startwm.sh > /dev/null
#!/bin/sh
if [ -r /etc/default/locale ]; then
  . /etc/default/locale
  export LANG LANGUAGE
fi

# Essential for stability on Ubuntu 22.04
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR

export XDG_CURRENT_DESKTOP=XFCE
export XDG_SESSION_TYPE=x11

exec dbus-run-session -- startxfce4
EOF
sudo chmod +x /etc/xrdp/startwm.sh

# Optimize xrdp.ini
sudo sed -i 's/^port=3389/port=3389/' /etc/xrdp/xrdp.ini
sudo sed -i 's/^security_layer=.*/security_layer=negotiate/' /etc/xrdp/xrdp.ini
sudo sed -i 's/^crypt_level=.*/crypt_level=high/' /etc/xrdp/xrdp.ini
sudo sed -i 's/^bitmap_compression=.*/bitmap_compression=yes/' /etc/xrdp/xrdp.ini

# Fix Xorg permissions
sudo sed -i 's/allowed_users=console/allowed_users=anybody/' /etc/X11/Xwrapper.config || echo "allowed_users=anybody" | sudo tee /etc/X11/Xwrapper.config > /dev/null

echo "--- [3/3] Setting Credentials & Restarting ---"
CURRENT_USER=$(whoami)
echo "$CURRENT_USER:CloudRDP2026!" | sudo chpasswd
echo "root:CloudRDP2026!" | sudo chpasswd

# Ensure services are enabled and restarted
sudo systemctl enable xrdp
sudo systemctl restart xrdp
sudo systemctl restart xrdp-sesman

echo "CloudRDP: Robust Setup Complete."
