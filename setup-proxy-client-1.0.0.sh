#!/bin/bash

set -e  # Exit immediately if any command fails

grep -qxF "root soft nofile 65535" /etc/security/limits.conf || echo "root soft nofile 65535" | sudo tee -a /etc/security/limits.conf
grep -qxF "root hard nofile 65535" /etc/security/limits.conf || echo "root hard nofile 65535" | sudo tee -a /etc/security/limits.conf

su - root

ulimit -n

echo "✅ Detecting server public IP..."
PUBLIC_IP=$(curl -s4 ifconfig.me || curl -s4 icanhazip.com)
echo "   → Detected IP: $PUBLIC_IP"

if systemctl list-unit-files | grep -q "proxy-client.service"; then
    if systemctl is-active --quiet proxy-client; then
        systemctl stop proxy-client
        echo "Stoped service proxy-client."
    else
        echo "Service proxy-client not running."
    fi
else
    echo "Service proxy-client not found"
fi

echo "🔹 Updating system and installing unzip..."
sudo apt update && sudo apt install -y unzip wget

# Create installation directory
INSTALL_DIR="/config/proxy-service/client"
mkdir -p "$INSTALL_DIR"

echo "--- Clear folder"
rm -rf $INSTALL_DIR/*

echo "🔹 Downloading proxy client..."
wget -O /tmp/BigCat.Proxy.Client.zip "https://dev-proxy-api.canawan.com/proxy/BigCat.Proxy.Client.zip?$(date +%s)"

echo "🔹 Extracting files..."
unzip -o /tmp/BigCat.Proxy.Client.zip -d "$INSTALL_DIR"
rm /tmp/BigCat.Proxy.Client.zip

echo "Granting execute permission to $INSTALL_DIR/BigCat.Proxy.Client"
sudo chmod +x "$INSTALL_DIR/BigCat.Proxy.Client"

echo "🔹 Stopping and removing old proxy-client service if exists..."
sudo systemctl stop proxy-client 2>/dev/null || true
sudo systemctl disable proxy-client 2>/dev/null || true

timeout 10 pkill -9 -f BigCat.Proxy.Client || echo "⚠️ Process not found or timeout reached."
sudo ip -6 addr flush dev ens6
sleep 5
sudo ip link set ens6 down
echo "down ens6"
sleep 5
sudo ip link set ens6 up

echo "apply"
sleep 5 
netplan apply

echo "🔹 Creating new systemd service..."
SERVICE_FILE="/etc/systemd/system/proxy-client.service"
sudo rm -f SERVICE_FILE

cd $INSTALL_DIR

nohup ./BigCat.Proxy.Client --defaultServerEndPointIP=$PUBLIC_IP --portAPI=9000 --passwordAPI=66778899 --defaultPortIPv4=9010 --maxConnections=-1 --maxConnectionPerCredential=-1 --networkInterface=ens6 --ipV6RotationSeconds=-1 --fromPort=20000 --toPort=30000 --autoOffAllFirewall=true     --autoConfigPortFirewall=false     --showFullDebug=true > /var/log/proxy-client.log 2>&1 &

# sudo tee "$SERVICE_FILE" > /dev/null <<EOF
# [Unit]
# Description=Proxy Client Service
# After=network.target

# [Service]
# Environment="LD_LIBRARY_PATH=/config/proxy-service/client"
# User=root
# WorkingDirectory=$INSTALL_DIR
# ExecStartPre=/bin/chmod +x $INSTALL_DIR/BigCat.Proxy.Client
# ExecStart=cd $INSTALL_DIR && ./BigCat.Proxy.Client \
#     --defaultServerEndPointIP=$PUBLIC_IP \
#     --portAPI=9000 \
#     --passwordAPI=66778899 \
#     --defaultPortIPv4=9010 \
#     --maxConnections=-1 \
#     --maxConnectionPerCredential=-1 \
#     --networkInterface=ens6 \
#     --ipV6RotationSeconds=-1 \
#     --fromPort=20000 \
#     --toPort=30000 \
#     --autoOffAllFirewall=true \
#     --autoConfigPortFirewall=false \
#     --showFullDebug=false
# Restart=always
# StandardOutput=append:/var/log/proxy-client.log
# StandardError=append:/var/log/proxy-client-error.log

# [Install]
# WantedBy=multi-user.target
# EOF

sleep 5

# sudo chmod 644 $SERVICE_FILE

echo "🔹 Reloading systemd..."
# sudo systemctl daemon-reload

echo "🔹 Setting execute permissions..."
# sudo chmod +x /config/proxy-service/client/BigCat.Proxy.Client

echo "🔹 Enabling and starting service..."
# sudo systemctl enable --now proxy-client

# echo "🔹 Restarting network interface ens6"
# sudo netplan apply

# sudo ip link set ens6 down
# sudo ip link set ens6 up

echo "✅ Installation complete! Check service status with:"
echo "   sudo systemctl status proxy-client"
echo "   journalctl -u proxy-client -f"
