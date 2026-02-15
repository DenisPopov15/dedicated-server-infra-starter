#!/bin/bash

# Caddy Installation and Configuration Script for Raspberry Pi
# This script installs Caddy and configures it as a reverse proxy to localhost:3000
# Usage:
#   HTTP only: sudo ./caddy-setup.sh
#   HTTPS with domain: sudo ./caddy-setup.sh yourdomain.duckdns.org
# Examples:
#   sudo ./caddy-setup.sh
#   sudo ./caddy-setup.sh mysubdomain.duckdns.org

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to log messages
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

# Function to log errors and exit
error_exit() {
    log_error "$1"
    exit 1
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error_exit "This script must be run as root (use sudo)"
fi

# Parse optional domain parameter
DOMAIN="${1:-}"
USE_HTTPS=false

if [ -n "$DOMAIN" ]; then
    # Basic domain validation
    if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9\.-]*[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        error_exit "Invalid domain format: $DOMAIN. Example: mysubdomain.duckdns.org"
    fi
    USE_HTTPS=true
    log "Domain provided: ${DOMAIN} - HTTPS will be configured"
else
    log "No domain provided - HTTP only mode (port 80)"
fi

log "Starting Caddy installation and configuration..."

# Check if Caddy is already installed
if command -v caddy &> /dev/null; then
    log_warning "Caddy is already installed: $(caddy version)"
    read -p "Do you want to continue and reconfigure? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Installation cancelled."
        exit 0
    fi
fi

# Install Caddy
log "Updating package lists..."
# Allow apt update to continue even if some repositories fail (e.g., old Raspbian versions)
apt update || {
    log_warning "Some repositories failed to update (this is common with older Raspbian versions)"
    log_warning "Continuing with installation - we only need the Caddy repository to work"
}

log "Installing prerequisites..."
apt install -y debian-keyring debian-archive-keyring apt-transport-https curl

log "Adding Caddy repository..."
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null

log "Updating package lists with Caddy repository..."
# Allow apt update to continue even if some repositories fail
apt update || {
    log_warning "Some repositories failed to update, but Caddy repository should be available"
}

log "Installing Caddy..."
apt install -y caddy

log_success "Caddy installed successfully: $(caddy version)"

# Setup Caddy configuration
if [ "$USE_HTTPS" = true ]; then
    log "Configuring Caddy reverse proxy to localhost:3000 with HTTPS for ${DOMAIN}..."
else
    log "Configuring Caddy reverse proxy to localhost:3000 (HTTP only)..."
fi

CADDYFILE="/etc/caddy/Caddyfile"
BACKUP_FILE="${CADDYFILE}.backup.$(date +%Y%m%d_%H%M%S)"

# Backup existing Caddyfile if it exists
if [ -f "$CADDYFILE" ]; then
    log "Backing up existing Caddyfile to ${BACKUP_FILE}..."
    cp "$CADDYFILE" "$BACKUP_FILE"
fi

# Create Caddyfile configuration
if [ "$USE_HTTPS" = true ]; then
    # HTTPS configuration with automatic SSL certificate from Let's Encrypt
    cat > "$CADDYFILE" << EOF
# Reverse proxy configuration for localhost:3000 with HTTPS
# Caddy will automatically obtain and renew SSL certificate from Let's Encrypt
# Make sure your domain ${DOMAIN} points to this server's IP address

${DOMAIN} {
    reverse_proxy localhost:3000
    
    # Security headers
    header {
        # Remove server header for security
        -Server
        
        # Enable CORS if needed
        Access-Control-Allow-Origin *
        Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
    }
    
    # Health check endpoint (optional)
    @health {
        path /health
    }
    handle @health {
        respond "OK" 200
    }
}
EOF
    log_success "Caddyfile created at ${CADDYFILE} with HTTPS configuration for ${DOMAIN}"
    log_warning "IMPORTANT: Make sure ${DOMAIN} DNS points to this server's IP address"
    log_warning "Caddy will automatically obtain SSL certificate from Let's Encrypt on first start"
else
    # HTTP-only configuration
    cat > "$CADDYFILE" << 'EOF'
# Reverse proxy configuration for localhost:3000
# Caddy will listen on port 80 and forward all requests to localhost:3000

:80 {
    reverse_proxy localhost:3000
    
    # Optional: Add headers for better compatibility
    header {
        # Enable CORS if needed
        # Access-Control-Allow-Origin *
        # Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
        
        # Remove server header for security
        -Server
    }
    
    # Health check endpoint (optional)
    # @health {
    #     path /health
    # }
    # handle @health {
    #     respond "OK" 200
    # }
}
EOF
    log_success "Caddyfile created at ${CADDYFILE} (HTTP only)"
fi

# Validate Caddyfile configuration
log "Validating Caddyfile configuration..."
if caddy validate --config "$CADDYFILE" 2>&1; then
    log_success "Caddyfile validation passed"
else
    error_exit "Caddyfile validation failed. Please check the configuration."
fi

# Enable and start Caddy service
log "Enabling Caddy service to start on boot..."
systemctl enable caddy || error_exit "Failed to enable Caddy service"

log "Starting Caddy service..."
systemctl restart caddy || error_exit "Failed to start Caddy service"

# Wait a moment for service to start
sleep 2

# Check service status
if systemctl is-active --quiet caddy; then
    log_success "Caddy service is running"
else
    error_exit "Caddy service failed to start. Check logs with: journalctl -u caddy"
fi

# Display service status
log "Caddy service status:"
systemctl status caddy --no-pager -l || true

log_success "Caddy setup completed successfully!"

if [ "$USE_HTTPS" = true ]; then
    log "Caddy is now configured to reverse proxy ${DOMAIN} (HTTPS) to localhost:3000"
    log "SSL certificate will be automatically obtained from Let's Encrypt"
    log "Access your service at: https://${DOMAIN}"
else
    log "Caddy is now configured to reverse proxy port 80 (HTTP) to localhost:3000"
    log "Access your service at: http://$(hostname -I | awk '{print $1}')"
fi

log "The service will automatically start on server reboot"
log ""
log "Useful commands:"
log "  - Check status: sudo systemctl status caddy"
log "  - View logs: sudo journalctl -u caddy -f"
log "  - Restart: sudo systemctl restart caddy"
log "  - Edit config: sudo nano ${CADDYFILE}"