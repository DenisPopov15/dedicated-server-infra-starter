#!/bin/bash

# Extend an existing Caddy install (after scripts/caddy-setup.sh) with a second site:
# reverse_proxy from DOMAIN to localhost:PORT.
# Typical setup: first app on 3000 (caddy-setup.sh), further apps on 3001, 3002, ...
#
# Usage:
#   sudo ./caddy-extend-setup.sh <port> <domain>
# Examples:
#   sudo ./caddy-extend-setup.sh 3001 app2.example.duckdns.org
#   sudo ./caddy-extend-setup.sh 3002 app3.example.com

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

error_exit() {
    log_error "$1"
    exit 1
}

if [ "$EUID" -ne 0 ]; then
    error_exit "This script must be run as root (use sudo)"
fi

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    echo "Usage: sudo $0 <port> <domain>" >&2
    echo "  Adds a Caddy site for <domain> -> reverse_proxy localhost:<port>" >&2
    echo "  Example: sudo $0 3001 app2.example.duckdns.org  (extra apps often use 3001, 3002, ...)" >&2
    exit 0
fi

if [ $# -ne 2 ]; then
    echo "Usage: sudo $0 <port> <domain>" >&2
    echo "  Example: sudo $0 3001 app2.example.duckdns.org" >&2
    exit 1
fi

PORT="$1"
DOMAIN="$2"

if [[ ! "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    error_exit "Invalid port: $PORT (use 1-65535)"
fi

if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9\.-]*[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
    error_exit "Invalid domain format: $DOMAIN. Example: mysubdomain.duckdns.org"
fi

CADDYFILE="/etc/caddy/Caddyfile"

if [ ! -f "$CADDYFILE" ]; then
    error_exit "Caddyfile not found at ${CADDYFILE}. Run scripts/caddy-setup.sh first."
fi

if ! command -v caddy &> /dev/null; then
    error_exit "caddy binary not found. Install Caddy first."
fi

if grep -qF "${DOMAIN} {" "$CADDYFILE" || grep -qF "http://${DOMAIN} {" "$CADDYFILE"; then
    error_exit "A site block for ${DOMAIN} already exists in ${CADDYFILE}"
fi

# Match caddy-setup.sh: HTTP-only installs use only :80 { ... }; use http:// for the new host on those.
# Hostname-based first site (e.g. duckdns) uses automatic HTTPS; new site uses the same style.
SITE_ADDR="${DOMAIN}"
if grep -qE '^[[:space:]]*:80[[:space:]]*\{' "$CADDYFILE" &&
    ! grep -qE '^[[:space:]]*[a-zA-Z0-9*][a-zA-Z0-9.-]*\.[a-zA-Z]{2,}[[:space:]]*\{' "$CADDYFILE"; then
    SITE_ADDR="http://${DOMAIN}"
    log "Detected HTTP-only :80 setup; new site will use ${SITE_ADDR} (no automatic HTTPS for this vhost)"
fi

BACKUP_FILE="${CADDYFILE}.backup.extend.$(date +%Y%m%d_%H%M%S)"
log "Backing up Caddyfile to ${BACKUP_FILE}..."
cp "$CADDYFILE" "$BACKUP_FILE"

log "Appending site ${SITE_ADDR} -> localhost:${PORT}..."

{
    echo ""
    echo "# --- Added by caddy-extend-setup.sh $(date -Iseconds) ---"
    echo "${SITE_ADDR} {"
    echo "    reverse_proxy localhost:${PORT}"
    echo ""
    echo "    header {"
    echo "        -Server"
    echo "        Access-Control-Allow-Origin *"
    echo "        Access-Control-Allow-Methods \"GET, POST, PUT, DELETE, OPTIONS\""
    echo "    }"
    echo ""
    echo "    @health {"
    echo "        path /health"
    echo "    }"
    echo "    handle @health {"
    echo "        respond \"OK\" 200"
    echo "    }"
    echo "}"
} >> "$CADDYFILE"

log "Validating Caddyfile..."
if ! caddy validate --config "$CADDYFILE" 2>&1; then
    log_error "Validation failed; restoring backup..."
    cp "$BACKUP_FILE" "$CADDYFILE"
    error_exit "Caddyfile validation failed. Backup restored from ${BACKUP_FILE}"
fi

if systemctl is-active --quiet caddy 2>/dev/null; then
    log "Reloading Caddy..."
    if systemctl reload caddy 2>/dev/null; then
        log_success "Caddy reloaded"
    else
        log_warning "reload failed; trying restart..."
        systemctl restart caddy || error_exit "Failed to restart Caddy. Restore with: sudo cp ${BACKUP_FILE} ${CADDYFILE} && sudo systemctl restart caddy"
        log_success "Caddy restarted"
    fi
else
    log_warning "Caddy is not active; starting it..."
    systemctl enable caddy 2>/dev/null || true
    systemctl start caddy || error_exit "Failed to start Caddy. Restore with: sudo cp ${BACKUP_FILE} ${CADDYFILE}"
    log_success "Caddy started"
fi

sleep 1
if systemctl is-active --quiet caddy 2>/dev/null; then
    log_success "Caddy is running"
else
    error_exit "Caddy is not running. Check: journalctl -u caddy -e"
fi

log_success "Extended Caddy: ${SITE_ADDR} -> http://127.0.0.1:${PORT}"
if [[ "$SITE_ADDR" == http://* ]]; then
    log "Access (HTTP): http://${DOMAIN}/"
else
    log "Access (HTTPS): https://${DOMAIN}/"
    log_warning "Ensure DNS for ${DOMAIN} points to this server for certificate issuance"
fi
log "Backup: ${BACKUP_FILE}"
