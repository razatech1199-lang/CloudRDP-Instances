#!/bin/bash

# CloudRDP "Safe Mode" Setup Script
# Using VNC backend for maximum reliability on headless runners.

export DEBIAN_FRONTEND=noninteractive

echo "--- [1/3] Installing Dependencies ---"
sudo apt-get update -qy
sudo apt-get install -y xrdp xfce4 xfce4-goodies tightvncserver dbus-x11 tmate

echo "--- [2/3] Configuring Safe Mode Session ---"
USER_HOME=$(eval echo "~$(whoami)")
echo "xfce4-session" > $USER_HOME/.xsession
chmod +x $USER_HOME/.xsession
chown $(whoami):$(whoami) $USER_HOME/.xsession

# Configure XRDP to use VNC by default (more stable than Xorg on GHA)
sudo sed -i 's/WaitTime=2/WaitTime=30/g' /etc/xrdp/sesman.ini
sudo sed -i 's/^security_layer=.*/security_layer=rdp/g' /etc/xrdp/xrdp.ini
sudo sed -i 's/^crypt_level=.*/crypt_level=low/g' /etc/xrdp/xrdp.ini
sudo sed -i 's/^max_bpp=.*/max_bpp=24/g' /etc/xrdp/xrdp.ini

# Ensure startwm.sh is minimalist
sudo mv /etc/xrdp/startwm.sh /etc/xrdp/startwm.sh.bak
cat << 'EOF' | sudo tee /etc/xrdp/startwm.sh > /dev/null
#!/bin/sh
if [ -r /etc/default/locale ]; then
  . /etc/default/locale
  export LANG LANGUAGE
fi
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
startxfce4
EOF
sudo chmod +x /etc/xrdp/startwm.sh

# Force Xvnc as the first priority in xrdp.ini
sudo sed -i '0,/\[Xorg\]/s/\[Xorg\]/\[Xvnc\]/' /etc/xrdp/xrdp.ini
sudo sed -i '0,/libxup.so/s/libxup.so/libvnc.so/' /etc/xrdp/xrdp.ini

echo "--- [3/3] Finalizing ---"
# Create a dedicated RDP user to avoid GHA runner restrictions
sudo useradd -m -s /bin/bash cloudrdp
echo "cloudrdp:1Pakistan@143" | sudo chpasswd
sudo usermod -aG sudo cloudrdp

# Setup X session for the new user
echo "xfce4-session" | sudo tee /home/cloudrdp/.xsession
sudo chown cloudrdp:cloudrdp /home/cloudrdp/.xsession

sudo systemctl enable xrdp
sudo systemctl restart xrdp
sudo systemctl restart xrdp-sesman

echo "CloudRDP: Safe Mode Setup Complete."
