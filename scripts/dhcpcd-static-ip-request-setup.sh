#!/bin/bash

# DHCPCD Static IP Configuration Script
# This script configures dhcpcd to use a static IP address for WiFi (wlan0) and optionally Ethernet (eth0)
# It also handles port forwarding configuration via UPnP (if available)
# Usage:
#   WiFi only: sudo ./dhcpcd-static-ip-request-setup.sh <ip_address> <gateway> [dns_servers] [ports]
#   WiFi + Ethernet: sudo ./dhcpcd-static-ip-request-setup.sh <ip_address> <gateway> [dns_servers] [ports] --ethernet <eth_ip_address>
# Examples:
#   sudo ./dhcpcd-static-ip-request-setup.sh 192.168.0.10/24 192.168.0.1
#   sudo ./dhcpcd-static-ip-request-setup.sh 192.168.0.10/24 192.168.0.1 "192.168.0.1 8.8.8.8"
#   sudo ./dhcpcd-static-ip-request-setup.sh 192.168.0.10/24 192.168.0.1 "192.168.0.1 8.8.8.8" "80,443,3000"
#   sudo ./dhcpcd-static-ip-request-setup.sh 192.168.0.10/24 192.168.0.1 "192.168.0.1 8.8.8.8" "80,443" --ethernet 192.168.0.11/24

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

# Function to show usage
show_usage() {
    echo "Usage: $0 <ip_address> <gateway> [dns_servers] [ports] [--ethernet <eth_ip_address>]"
    echo ""
    echo "Arguments:"
    echo "  ip_address      Static IP address with CIDR notation (e.g., 192.168.0.10/24)"
    echo "  gateway         Router/Gateway IP address (e.g., 192.168.0.1)"
    echo "  dns_servers     Optional: DNS servers (space-separated, default: gateway 8.8.8.8)"
    echo "  ports           Optional: Ports to forward (comma-separated, e.g., 80,443,3000)"
    echo "  --ethernet      Optional: Configure Ethernet with static IP (e.g., 192.168.0.11/24)"
    echo ""
    echo "Examples:"
    echo "  $0 192.168.0.10/24 192.168.0.1"
    echo "  $0 192.168.0.10/24 192.168.0.1 \"192.168.0.1 8.8.8.8\""
    echo "  $0 192.168.0.10/24 192.168.0.1 \"192.168.0.1 8.8.8.8\" \"80,443,3000\""
    echo "  $0 192.168.0.10/24 192.168.0.1 \"192.168.0.1 8.8.8.8\" \"80,443\" --ethernet 192.168.0.11/24"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error_exit "This script must be run as root (use sudo)"
fi

# Parse arguments
if [ $# -lt 2 ]; then
    show_usage
    error_exit "Missing required arguments"
fi

WIFI_IP="$1"
GATEWAY="$2"
DNS_SERVERS="${3:-$GATEWAY 8.8.8.8}"
PORTS=""
ETHERNET_IP=""
ETHERNET_ENABLED=false

# Parse remaining optional arguments
shift 2  # Remove first two required args
while [[ $# -gt 0 ]]; do
    case $1 in
        --ethernet)
            if [ -z "${2:-}" ]; then
                error_exit "--ethernet requires an IP address argument"
            fi
            ETHERNET_IP="$2"
            ETHERNET_ENABLED=true
            shift 2
            ;;
        *)
            # Check if it's DNS servers (contains IP addresses)
            if [[ "$1" =~ [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]] && [ "$DNS_SERVERS" = "$GATEWAY 8.8.8.8" ]; then
                DNS_SERVERS="$1"
                shift
            # Check if it's ports (comma-separated numbers)
            elif [[ "$1" =~ ^[0-9,]+$ ]] && [ -z "$PORTS" ]; then
                PORTS="$1"
                shift
            else
                error_exit "Unknown argument: $1"
            fi
            ;;
    esac
done

# Validate IP address format (basic validation)
validate_ip_cidr() {
    local ip_cidr="$1"
    if [[ ! "$ip_cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        return 1
    fi
    return 0
}

# Validate gateway IP format
validate_ip() {
    local ip="$1"
    if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 1
    fi
    return 0
}

# Validate inputs
if ! validate_ip_cidr "$WIFI_IP"; then
    error_exit "Invalid WiFi IP address format: $WIFI_IP (expected format: 192.168.0.10/24)"
fi

if ! validate_ip "$GATEWAY"; then
    error_exit "Invalid gateway IP address format: $GATEWAY"
fi

if [ "$ETHERNET_ENABLED" = true ] && ! validate_ip_cidr "$ETHERNET_IP"; then
    error_exit "Invalid Ethernet IP address format: $ETHERNET_IP (expected format: 192.168.0.11/24)"
fi

# Check if dhcpcd is installed
if ! command -v dhcpcd &> /dev/null; then
    log "dhcpcd is not installed. Installing..."
    if command -v apt-get &> /dev/null; then
        apt-get update -qq
        apt-get install -y dhcpcd5
    elif command -v yum &> /dev/null; then
        yum install -y dhcpcd
    else
        error_exit "Could not detect package manager. Please install dhcpcd manually."
    fi
    log_success "dhcpcd installed successfully"
fi

# Check if interfaces exist
check_interface() {
    local interface="$1"
    if ip link show "$interface" &> /dev/null; then
        return 0
    fi
    return 1
}

if ! check_interface wlan0; then
    log_warning "wlan0 interface not found. It may not be available yet or WiFi is not configured."
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

if [ "$ETHERNET_ENABLED" = true ] && ! check_interface eth0; then
    log_warning "eth0 interface not found. Ethernet configuration will be skipped."
    ETHERNET_ENABLED=false
fi

# Backup dhcpcd.conf
DHCPCD_CONF="/etc/dhcpcd.conf"
BACKUP_FILE="${DHCPCD_CONF}.backup.$(date +%Y%m%d_%H%M%S)"

if [ -f "$DHCPCD_CONF" ]; then
    log "Creating backup of dhcpcd.conf..."
    if cp "$DHCPCD_CONF" "$BACKUP_FILE"; then
        log_success "Backup created: $BACKUP_FILE"
    else
        error_exit "Failed to create backup of $DHCPCD_CONF"
    fi
else
    log "dhcpcd.conf does not exist. It will be created."
fi

# Function to remove existing interface configuration
remove_interface_config() {
    local interface="$1"
    local conf_file="$2"
    
    # Remove existing configuration for this interface
    # This handles both commented and uncommented lines
    sed -i "/^#.*interface ${interface}$/d" "$conf_file" 2>/dev/null || true
    sed -i "/^interface ${interface}$/d" "$conf_file" 2>/dev/null || true
    sed -i "/^#.*static ip_address=.*${interface}/d" "$conf_file" 2>/dev/null || true
    sed -i "/^static ip_address=.*${interface}/d" "$conf_file" 2>/dev/null || true
    
    # Remove all lines between interface declaration and next interface or empty line
    # This is a simplified approach - we'll add our config at the end
}

# Function to add interface configuration
add_interface_config() {
    local interface="$1"
    local ip_address="$2"
    local gateway="$3"
    local dns_servers="$4"
    local conf_file="$5"
    
    log "Configuring ${interface} with static IP ${ip_address}..."
    
    # Remove existing configuration for this interface
    remove_interface_config "$interface" "$conf_file"
    
    # Ensure file ends with newline
    if [ -n "$(tail -c 1 "$conf_file" 2>/dev/null)" ]; then
        echo "" >> "$conf_file"
    fi
    
    # Add configuration section
    cat >> "$conf_file" << EOF

# Static IP configuration for ${interface} - Added by dhcpcd-static-ip-request-setup.sh
interface ${interface}
static ip_address=${ip_address}
static routers=${gateway}
static domain_name_servers=${dns_servers}
EOF
    
    log_success "Configuration added for ${interface}"
}

# Configure WiFi (wlan0)
log "Configuring WiFi interface (wlan0)..."
add_interface_config "wlan0" "$WIFI_IP" "$GATEWAY" "$DNS_SERVERS" "$DHCPCD_CONF"

# Configure Ethernet (eth0) if enabled
if [ "$ETHERNET_ENABLED" = true ]; then
    log "Configuring Ethernet interface (eth0)..."
    add_interface_config "eth0" "$ETHERNET_IP" "$GATEWAY" "$DNS_SERVERS" "$DHCPCD_CONF"
fi

# Function to check if UPnP tools are available
check_upnp_available() {
    if command -v upnpc &> /dev/null; then
        return 0
    fi
    return 1
}

# Function to install UPnP client
install_upnp_client() {
    log "Installing UPnP client (miniupnpc) for port forwarding..."
    if command -v apt-get &> /dev/null; then
        apt-get update -qq
        apt-get install -y miniupnpc || {
            log_warning "Failed to install miniupnpc. Port forwarding will need to be configured manually on the router."
            return 1
        }
    elif command -v yum &> /dev/null; then
        yum install -y miniupnpc || {
            log_warning "Failed to install miniupnpc. Port forwarding will need to be configured manually on the router."
            return 1
        }
    else
        log_warning "Could not detect package manager. Port forwarding will need to be configured manually on the router."
        return 1
    fi
    log_success "UPnP client installed successfully"
    return 0
}

# Function to configure port forwarding via UPnP
configure_port_forwarding() {
    local ports="$1"
    local local_ip="$2"
    
    if [ -z "$ports" ]; then
        return 0
    fi
    
    log "Configuring port forwarding for ports: $ports"
    
    # Check if UPnP is available
    if ! check_upnp_available; then
        log_warning "UPnP client (upnpc) not found. Attempting to install..."
        if ! install_upnp_client; then
            log_warning "UPnP client installation failed or not available."
            log_warning "Port forwarding will need to be configured manually on your router."
            show_port_forwarding_instructions "$ports" "$local_ip"
            return 1
        fi
    fi
    
    # Extract IP address without CIDR
    local_ip_only=$(echo "$local_ip" | cut -d'/' -f1)
    
    # Split ports by comma and forward each
    IFS=',' read -ra PORT_ARRAY <<< "$ports"
    local success_count=0
    local fail_count=0
    
    for port in "${PORT_ARRAY[@]}"; do
        port=$(echo "$port" | xargs)  # Trim whitespace
        
        # Validate port number
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
            log_warning "Invalid port number: $port. Skipping..."
            ((fail_count++)) || true
            continue
        fi
        
        log "Forwarding port $port to $local_ip_only:$port..."
        
        # Use upnpc to add port mapping
        # -a: add port mapping
        # $local_ip_only: internal IP
        # $port: external port
        # $port: internal port
        # TCP: protocol
        # 0: lease duration (0 = permanent)
        if upnpc -a "$local_ip_only" "$port" "$port" TCP 0 2>/dev/null; then
            log_success "Port $port forwarded successfully"
            ((success_count++)) || true
        else
            log_warning "Failed to forward port $port via UPnP"
            log_warning "This may be because:"
            log_warning "  - Router does not support UPnP"
            log_warning "  - UPnP is disabled on router"
            log_warning "  - Port is already forwarded"
            ((fail_count++)) || true
        fi
    done
    
    if [ $success_count -gt 0 ]; then
        log_success "Successfully forwarded $success_count port(s)"
    fi
    
    if [ $fail_count -gt 0 ]; then
        log_warning "Failed to forward $fail_count port(s) via UPnP"
        show_port_forwarding_instructions "$ports" "$local_ip_only"
    fi
    
    return 0
}

# Function to show manual port forwarding instructions
show_port_forwarding_instructions() {
    local ports="$1"
    local local_ip="$2"
    
    echo
    log_warning "Manual Port Forwarding Instructions:"
    echo "=========================================="
    echo "Since automatic port forwarding failed, you need to configure it manually on your router:"
    echo ""
    echo "1. Access your router's web interface (usually at $GATEWAY)"
    echo "2. Navigate to Port Forwarding / Virtual Server / NAT settings"
    echo "3. Add the following port forwarding rules:"
    echo ""
    
    IFS=',' read -ra PORT_ARRAY <<< "$ports"
    for port in "${PORT_ARRAY[@]}"; do
        port=$(echo "$port" | xargs)
        if [[ "$port" =~ ^[0-9]+$ ]]; then
            echo "   - External Port: $port"
            echo "     Internal IP: $local_ip"
            echo "     Internal Port: $port"
            echo "     Protocol: TCP (and UDP if needed)"
            echo ""
        fi
    done
    
    echo "4. Save the configuration and restart your router if needed"
    echo ""
}

# Verify configuration
verify_config() {
    log "Verifying dhcpcd configuration..."
    
    if ! grep -q "^interface wlan0$" "$DHCPCD_CONF"; then
        log_error "WiFi interface configuration not found in dhcpcd.conf"
        return 1
    fi
    
    if ! grep -q "^static ip_address=${WIFI_IP}$" "$DHCPCD_CONF"; then
        log_error "WiFi IP address configuration not found"
        return 1
    fi
    
    if [ "$ETHERNET_ENABLED" = true ]; then
        if ! grep -q "^interface eth0$" "$DHCPCD_CONF"; then
            log_error "Ethernet interface configuration not found in dhcpcd.conf"
            return 1
        fi
    fi
    
    log_success "Configuration verified successfully"
    return 0
}

# Main function
main() {
    echo "========================================"
    echo "DHCPCD Static IP Configuration Script"
    echo "========================================"
    echo
    
    log "Configuration parameters:"
    log "  WiFi IP: $WIFI_IP"
    log "  Gateway: $GATEWAY"
    log "  DNS Servers: $DNS_SERVERS"
    if [ "$ETHERNET_ENABLED" = true ]; then
        log "  Ethernet IP: $ETHERNET_IP"
    fi
    if [ -n "$PORTS" ]; then
        log "  Ports to forward: $PORTS"
    fi
    echo
    
    # Configure interfaces
    if ! verify_config; then
        log_error "Configuration verification failed. Restoring from backup..."
        if [ -f "$BACKUP_FILE" ]; then
            cp "$BACKUP_FILE" "$DHCPCD_CONF"
            log "Configuration restored from backup"
        fi
        error_exit "Failed to configure dhcpcd"
    fi
    
    # Configure port forwarding if ports are specified
    if [ -n "$PORTS" ]; then
        configure_port_forwarding "$PORTS" "$WIFI_IP"
    fi
    
    # Show post-installation instructions
    echo
    log_success "DHCPCD static IP configuration completed!"
    echo
    log "Configuration file: $DHCPCD_CONF"
    log "Backup file: $BACKUP_FILE"
    echo
    log_warning "IMPORTANT: A system reboot is required for the changes to take effect"
    echo
    log "Post-installation steps:"
    echo "1. Review the configuration in $DHCPCD_CONF"
    echo "2. Reboot your device: sudo reboot"
    echo "3. After reboot, verify the IP address with: ip addr show wlan0"
    if [ "$ETHERNET_ENABLED" = true ]; then
        echo "4. Verify Ethernet IP with: ip addr show eth0"
    fi
    echo
    if [ -n "$PORTS" ]; then
        log "Port forwarding:"
        echo "  - If UPnP was successful, ports are already forwarded"
        echo "  - If UPnP failed, follow the manual instructions above"
        echo "  - Verify port forwarding with: upnpc -l"
        echo
    fi
    log "To revert changes, restore from backup:"
    echo "  sudo cp $BACKUP_FILE $DHCPCD_CONF"
    echo "  sudo reboot"
    echo
    
    log_success "Script completed successfully!"
    log "Reboot your device to apply the changes: sudo reboot"
}

# Run main function
main "$@"

