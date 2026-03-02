#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

err() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Root check
[[ $EUID -ne 0 ]] && err "Run as root"

# Stop old service
if systemctl is-active --quiet canawan_proxy; then
    log "Stopping canawan_proxy..."
    service canawan_proxy stop || true
    sleep 2
fi

# Cleanup
log "Cleaning up old files..."
rm -rf /etc/systemd/system/canawan_proxy.service
rm -rf proxy.sh

# Download & install
log "Downloading proxy.sh..."
curl -fsSL -o proxy.sh https://mautic.canawan.com/shell/proxy.sh || err "Download failed"
chmod +x ./proxy.sh

log "Installing proxy (IPv4 only)..."
./proxy.sh canawan_proxy --routeIPV6=none --serverRouteIPV6=none --ipv6=false || err "Installation failed"

# Firewall
log "Configuring firewall..."
ufw allow 443 -y >/dev/null 2>&1 || true
ufw allow 80 -y >/dev/null 2>&1 || true
ufw reload -y >/dev/null 2>&1 || true

# Restart service
log "Restarting service..."
service canawan_proxy stop || true
sleep 2
service canawan_proxy start || err "Service start failed"
sleep 2

API_PORT=8888
API_TOKEN="66778899"
SERVER_IP=$(curl -s ifconfig.me || curl -s api.ipify.org || hostname -I | awk '{print $1}')

# Verify
if ! systemctl is-active --quiet canawan_proxy; then
    err "Service not running. Check: journalctl -u canawan_proxy -n 50"
fi

ok "canawan_proxy is running"

# Install jq if not available
if ! command -v jq &>/dev/null; then
    log "Installing jq..."
    apt-get install -y jq >/dev/null 2>&1 || true
fi

# Wait for API ready
log "Waiting for proxy API..."
API_READY=false
for _ in $(seq 1 30); do
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: ${API_TOKEN}" \
        "http://127.0.0.1:${API_PORT}/apiProxy/info" 2>/dev/null)
    if [[ "$RESPONSE" == "200" ]]; then
        API_READY=true
        break
    fi
    sleep 2
done

[[ "$API_READY" != "true" ]] && err "Proxy API not responding on port ${API_PORT}"

# Get all proxies
log "Fetching proxy list..."
PROXY_IDS=()
PAGE=1
while true; do
    RESULT=$(curl -s -X POST -H "Authorization: ${API_TOKEN}" -H "Content-Type: application/json" \
        -d "{\"pageIndex\":${PAGE},\"pageSize\":100}" "http://127.0.0.1:${API_PORT}/apiProxy/list" 2>/dev/null)
    IDS=$(echo "$RESULT" | jq -r '.data.proxies[]?.id // empty' 2>/dev/null)
    [[ -z "$IDS" ]] && break
    while IFS= read -r id; do
        PROXY_IDS+=("$id")
    done <<< "$IDS"
    PAGE=$((PAGE + 1))
done

if [[ ${#PROXY_IDS[@]} -eq 0 ]]; then
    err "No proxies found from API"
fi

ok "Found ${#PROXY_IDS[@]} proxy(s)"

# Generate credentials
PROXY_USER=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
PROXY_PASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)

# Set username/password for all proxies
log "Setting credentials for ${#PROXY_IDS[@]} proxy(s)..."
FAIL_COUNT=0
for PROXY_ID in "${PROXY_IDS[@]}"; do
    CONFIG_RESULT=$(curl -s -X POST -H "Authorization: ${API_TOKEN}" -H "Content-Type: application/json" \
        -d "{\"ids\":[\"${PROXY_ID}\"],\"auth\":{\"type\":\"username\",\"data\":{\"userCredentials\":[{\"user\":\"${PROXY_USER}\",\"password\":\"${PROXY_PASS}\"}],\"addUserCredential\":true}}}" \
        "http://127.0.0.1:${API_PORT}/apiProxy/config" 2>/dev/null)
    if echo "$CONFIG_RESULT" | grep -q "success"; then
        ok "Proxy ${PROXY_ID} credentials set"
    else
        echo -e "${RED}[FAIL]${NC} Proxy ${PROXY_ID}: ${CONFIG_RESULT}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    sleep 1
done

if [[ $FAIL_COUNT -gt 0 ]]; then
    echo -e "${RED}[WARN]${NC} ${FAIL_COUNT} proxy(s) failed to set credentials"
fi

# Final proxy list
PROXY_LIST=$(curl -s -X POST -H "Authorization: ${API_TOKEN}" -H "Content-Type: application/json" \
    -d '{"pageIndex":1,"pageSize":100}' "http://127.0.0.1:${API_PORT}/apiProxy/list" 2>/dev/null)

PROXY_INFO=$(curl -s -H "Authorization: ${API_TOKEN}" \
    "http://127.0.0.1:${API_PORT}/apiProxy/info" 2>/dev/null)

echo ""
echo "========================================="
echo " IPv4 Proxy installed successfully"
echo "========================================="
echo ""
echo " Server IP:    ${SERVER_IP}"
echo " API Port:     ${API_PORT}"
echo " Proxy Port:   8889 (SOCKS5)"
echo " Username:     ${PROXY_USER}"
echo " Password:     ${PROXY_PASS}"
echo ""
echo " SOCKS5:       socks5h://${PROXY_USER}:${PROXY_PASS}@${SERVER_IP}:8889"
echo " Proxy API:    http://${SERVER_IP}:${API_PORT}/apiProxy/list"
echo ""

if [[ -n "$PROXY_INFO" ]]; then
    echo " Version: $(echo "$PROXY_INFO" | jq -r '.version // .data.version // "unknown"' 2>/dev/null)"
fi

echo " Total proxies: ${#PROXY_IDS[@]}"
echo ""
echo "========================================="
