echo "--- [1/3] Installing Core GUI & RDP ---"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qy
sudo apt-get install -y xrdp xfce4 xfce4-goodies tightvncserver dbus-x11 autocutsel

echo "--- [2/3] Configuring Diagnostic Session ---"
# Set password for runner (as a backup)
echo "runner:1Pakistan@143" | sudo chpasswd
sudo usermod -aG sudo,video,ssl-cert,render,xrdp runner

# DIAGNOSTIC: Bypass PAM password check for RDP
cat << 'EOF' | sudo tee /etc/pam.d/xrdp-sesman > /dev/null
auth       required   pam_permit.so
account    required   pam_permit.so
session    required   pam_permit.so
password   required   pam_permit.so
EOF

# Setup desktop session for runner
USER_HOME="/home/runner"
cat << 'EOF' | sudo tee $USER_HOME/.xsession > /dev/null
#!/bin/bash
autocutsel -fork
xrdp-chansrv &
exec dbus-launch --exit-with-session startxfce4
EOF
sudo chown runner:runner $USER_HOME/.xsession
chmod +x $USER_HOME/.xsession

echo "--- [3/3] Restarting Services ---"
sudo systemctl enable xrdp
sudo systemctl restart xrdp
sudo systemctl restart xrdp-sesman

# Verification: Show AllowRootLogin status in logs
grep "AllowRootLogin" /etc/xrdp/sesman.ini

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
