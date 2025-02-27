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
sudo rm -f $SERVICE_FILE

cd $INSTALL_DIR

# nohup ./BigCat.Proxy.Client --defaultServerEndPointIP=$PUBLIC_IP --portAPI=9000 --passwordAPI=66778899 --defaultPortIPv4=9010 --maxConnections=-1 --maxConnectionPerCredential=-1 --networkInterface=ens6 --ipV6RotationSeconds=-1 --fromPort=20000 --toPort=30000 --autoOffAllFirewall=true     --autoConfigPortFirewall=false     --showFullDebug=true > /var/log/proxy-client.log 2>&1 &

sudo tee "/config/proxy-service/start_proxy.sh" > /dev/null <<EOF
#!/bin/bash

LOG_FILE="/var/log/proxy-client.log"
LOG_FILE_CHECK="/var/log/proxy-client-check.log"

WORK_DIR=${1:-"/opt/proxy-client"}
DEFAULT_IP=${2:-"192.168.1.100"}
PORT_API=${3:-9000}
PASSWORD_API=${4:-"66778899"}
PORT_IPV4=${5:-9010}
NETWORK_INTERFACE=${6:-"ens6"}
FROM_PORT=${7:-20000}
TO_PORT=${8:-30000}

API_URL="http://$DEFAULT_IP:$PORT_API/apiProxy/list"
WEBHOOK_URL="https://it-n8n.canawan.com/webhook/worker-server-notice"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting BigCat.Proxy.Client..." | tee -a "$LOG_FILE_CHECK"

cd "$WORK_DIR" || exit 1

./BigCat.Proxy.Client \
    --defaultServerEndPointIP="$DEFAULT_IP" \
    --portAPI="$PORT_API" \
    --passwordAPI="$PASSWORD_API" \
    --defaultPortIPv4="$PORT_IPV4" \
    --maxConnections=-1 \
    --maxConnectionPerCredential=-1 \
    --networkInterface="$NETWORK_INTERFACE" \
    --ipV6RotationSeconds=-1 \
    --fromPort="$FROM_PORT" \
    --toPort="$TO_PORT" \
    --autoOffAllFirewall=true \
    --autoConfigPortFirewall=false \
    --showFullDebug=false \
    >> "$LOG_FILE" 2>&1
EOF

sudo chmod +x /config/proxy-service/start_proxy.sh

sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Proxy Client Service
After=network.target

[Service]
ExecStart=/config/proxy-service/start_proxy.sh $INSTALL_DIR $PUBLIC_IP
Restart=on-failure
User=root
WorkingDirectory=/config/proxy-service/client
StandardOutput=append:/var/log/proxy-client.log
StandardError=append:/var/log/proxy-client-error.log
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

sudo chmod 644 $SERVICE_FILE

echo "🔹 Reloading systemd..."
sudo systemctl daemon-reload

echo "🔹 Setting execute permissions..."
sudo chmod +x /config/proxy-service/client/BigCat.Proxy.Client

echo "🔹 Enabling and starting service..."
sudo systemctl enable proxy-client.service
sudo systemctl start proxy-client.service

echo "✅ Installation complete! Check service status with:"
echo "   sudo systemctl status proxy-client"
echo "   journalctl -u proxy-client -f"
