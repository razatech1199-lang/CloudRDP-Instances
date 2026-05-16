echo "--- [1/3] Installing GUI, VNC & Clipboard Helpers ---"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qy
sudo apt-get install -y xrdp xfce4 xfce4-goodies tightvncserver dbus-x11 autocutsel

echo "--- [2/3] Configuring RDP User & Auth ---"
# Create RDP user with pre-encrypted password
PASS=$(openssl passwd -1 "1Pakistan@143")
sudo useradd -m -s /bin/bash -p "$PASS" cloudrdp
sudo usermod -aG sudo,video,ssl-cert,render,xrdp cloudrdp

# Configure XRDP to use VNC backend
sudo sed -i 's/WaitTime=2/WaitTime=30/g' /etc/xrdp/sesman.ini
sudo sed -i 's/^security_layer=.*/security_layer=rdp/g' /etc/xrdp/xrdp.ini

# Fix PAM for xrdp-sesman
cat << 'EOF' | sudo tee /etc/pam.d/xrdp-sesman > /dev/null
auth       required   pam_unix.so
account    required   pam_unix.so
session    required   pam_unix.so
password   required   pam_unix.so
EOF

# Setup desktop session with Clipboard Support
cat << 'EOF' | sudo tee /home/cloudrdp/.xsession > /dev/null
#!/bin/bash
autocutsel -fork
xrdp-chansrv &
exec dbus-launch --exit-with-session startxfce4
EOF
sudo chown cloudrdp:cloudrdp /home/cloudrdp/.xsession
chmod +x /home/cloudrdp/.xsession

echo "--- [3/3] Finalizing Services ---"
sudo systemctl enable xrdp
sudo systemctl restart xrdp
sudo systemctl restart xrdp-sesman

echo "--- [4/4] Starting Tunnel ---"
wget -q https://github.com/ekzhang/bore/releases/download/v0.5.1/bore-v0.5.1-x86_64-unknown-linux-musl.tar.gz
tar -xf bore-v0.5.1-x86_64-unknown-linux-musl.tar.gz
chmod +x bore

nohup ./bore local 3389 --to bore.pub > bore.log 2>&1 &
sleep 5

for i in {1..10}; do
    TUNNEL_URL=$(grep -oE "bore.pub:[0-9]+" bore.log | head -n 1)
    [ ! -z "$TUNNEL_URL" ] && break
    sleep 2
done

if [ ! -z "$TUNNEL_URL" ]; then
    echo "Tunnel Established: $TUNNEL_URL"
    curl -s -X POST "$BACKEND_URL/instance/$INSTANCE_ID/report" \
        -H "Content-Type: application/json" \
        -H "Bypass-Tunnel-Reminder: true" \
        -d "{\"ip_address\": \"$TUNNEL_URL\"}"
fi

echo "CloudRDP: Setup Complete."
