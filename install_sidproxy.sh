#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${YELLOW}[INFO]${NC} $1"; }
ok() { echo -e "${GREEN}[OK]${NC} $1"; }
err() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Root check
[[ $EUID -ne 0 ]] && err "Run as root"

# =============================================
# 1. Firewall
# =============================================
log "Configuring firewall..."
if command -v ufw &>/dev/null; then
    ufw allow 22/tcp >/dev/null 2>&1 || true
    ufw allow 1080/tcp >/dev/null 2>&1 || true
    ufw allow 3128/tcp >/dev/null 2>&1 || true
    ufw --force enable >/dev/null 2>&1 || true
    ufw reload >/dev/null 2>&1 || true
    ok "Firewall ready"
else
    log "UFW not found, skipping firewall config"
fi

# =============================================
# 2. Install 3proxy
# =============================================
log "Installing 3proxy..."
apt-get update -qq
apt-get install -y -qq 3proxy >/dev/null 2>&1 || {
    # Fallback: build from source if package not available
    log "Package not found, building from source..."
    apt-get install -y -qq build-essential git >/dev/null 2>&1
    cd /tmp
    rm -rf 3proxy
    git clone --depth 1 https://github.com/3proxy/3proxy.git >/dev/null 2>&1
    cd 3proxy
    make -f Makefile.Linux >/dev/null 2>&1
    install bin/3proxy /usr/local/bin/3proxy
    cd /
    rm -rf /tmp/3proxy
}

# Verify
if ! command -v 3proxy &>/dev/null && [[ ! -f /usr/local/bin/3proxy ]]; then
    err "3proxy installation failed"
fi
ok "3proxy installed"

# =============================================
# 3. Generate credentials
# =============================================
PROXY_USER=$(tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w 8 | head -n 1)
PROXY_PASS=$(tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w 12 | head -n 1)
SERVER_IP=$(curl -s ifconfig.me || curl -s api.ipify.org || hostname -I | awk '{print $1}')

# =============================================
# 4. Configure 3proxy
# =============================================
log "Configuring sidproxy..."

mkdir -p /etc/sidproxy
cat > /etc/sidproxy/3proxy.cfg << EOF
daemon
pidfile /var/run/sidproxy.pid
nserver 8.8.8.8
nserver 1.1.1.1
nscache 65536
timeouts 1 5 30 60 180 1800 15 60

log /var/log/sidproxy.log D
logformat "- +_L%t.%. %N.%p %E %U %C:%c %R:%r %O %I %h %T"

auth strong
users ${PROXY_USER}:CL:${PROXY_PASS}

allow ${PROXY_USER}

# HTTP proxy on port 3128
proxy -p3128 -n

# SOCKS5 proxy on port 1080
socks -p1080 -n
EOF

chmod 600 /etc/sidproxy/3proxy.cfg

# =============================================
# 5. Create systemd service
# =============================================
PROXY_BIN=$(command -v 3proxy || echo "/usr/local/bin/3proxy")

cat > /etc/systemd/system/sidproxy.service << EOF
[Unit]
Description=SidProxy (3proxy)
After=network.target

[Service]
Type=forking
PIDFile=/var/run/sidproxy.pid
ExecStart=${PROXY_BIN} /etc/sidproxy/3proxy.cfg
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# =============================================
# 6. Stop old services & start
# =============================================
for svc in sidproxy canawan_proxy 3proxy; do
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
done

systemctl daemon-reload
systemctl enable sidproxy >/dev/null 2>&1
systemctl start sidproxy || err "Service start failed"
sleep 2

if ! systemctl is-active --quiet sidproxy; then
    err "Service not running. Check: journalctl -u sidproxy -n 50"
fi
ok "sidproxy is running"

# =============================================
# 7. Output
# =============================================
echo ""
echo "========================================="
echo " SidProxy installed successfully"
echo "========================================="
echo ""
echo " Server IP:    ${SERVER_IP}"
echo " Username:     ${PROXY_USER}"
echo " Password:     ${PROXY_PASS}"
echo ""
echo " HTTP Proxy:   http://${PROXY_USER}:${PROXY_PASS}@${SERVER_IP}:3128"
echo " SOCKS5 Proxy: socks5h://${PROXY_USER}:${PROXY_PASS}@${SERVER_IP}:1080"
echo ""
echo " Test HTTP:    curl -x http://${PROXY_USER}:${PROXY_PASS}@${SERVER_IP}:3128 https://api.ipify.org"
echo " Test SOCKS5:  curl -x socks5h://${PROXY_USER}:${PROXY_PASS}@${SERVER_IP}:1080 https://api.ipify.org"
echo "========================================="
