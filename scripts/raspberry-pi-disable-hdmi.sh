#!/bin/bash

# Raspberry Pi HDMI Disable Script
# This script permanently disables HDMI output on Raspberry Pi devices
# by modifying the boot configuration file
# Usage: sudo ./raspberry-pi-disable-hdmi.sh

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

# Function to check if running on Raspberry Pi
check_raspberry_pi() {
    log "Checking if running on Raspberry Pi..."
    
    # Check for Raspberry Pi hardware
    if [ -f /proc/device-tree/model ]; then
        MODEL=$(tr -d '\0' < /proc/device-tree/model)
        if echo "$MODEL" | grep -qi "raspberry pi"; then
            log_success "Detected Raspberry Pi: $MODEL"
            return 0
        fi
    fi
    
    # Alternative check: check for Raspberry Pi in /proc/cpuinfo
    if grep -qi "raspberry pi" /proc/cpuinfo 2>/dev/null; then
        log_success "Detected Raspberry Pi hardware"
        return 0
    fi
    
    # Check for BCM chip (Raspberry Pi uses Broadcom chips)
    if grep -qi "BCM" /proc/cpuinfo 2>/dev/null; then
        log_warning "Detected BCM chip, but not confirmed as Raspberry Pi"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
        return 0
    fi
    
    log_warning "Could not confirm Raspberry Pi hardware"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    return 0
}

# Function to find boot config file
find_boot_config() {
    log "Locating boot configuration file..."
    
    # Check for newer Raspberry Pi OS location
    if [ -f /boot/firmware/config.txt ]; then
        echo "/boot/firmware/config.txt"
        return 0
    fi
    
    # Check for standard location
    if [ -f /boot/config.txt ]; then
        echo "/boot/config.txt"
        return 0
    fi
    
    error_exit "Could not find boot configuration file. Expected /boot/config.txt or /boot/firmware/config.txt"
}

# Function to backup config file
backup_config() {
    local config_file="$1"
    local backup_file="${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    log "Creating backup of configuration file..."
    if cp "$config_file" "$backup_file"; then
        log_success "Backup created: $backup_file"
        echo "$backup_file"
    else
        error_exit "Failed to create backup of $config_file"
    fi
}

# Function to check if HDMI is already disabled
check_hdmi_disabled() {
    local config_file="$1"
    
    # Check if HDMI disable settings are already present
    if grep -q "^hdmi_blanking=1" "$config_file" 2>/dev/null || \
       grep -q "^hdmi_ignore_hotplug=1" "$config_file" 2>/dev/null; then
        return 0
    fi
    
    return 1
}

# Function to disable HDMI
disable_hdmi() {
    local config_file="$1"
    
    log "Disabling HDMI in boot configuration..."
    
    # Remove any existing HDMI-related settings that might conflict
    log "Removing conflicting HDMI settings..."
    sed -i '/^hdmi_force_hotplug=/d' "$config_file" 2>/dev/null || true
    sed -i '/^hdmi_blanking=/d' "$config_file" 2>/dev/null || true
    sed -i '/^hdmi_ignore_hotplug=/d' "$config_file" 2>/dev/null || true
    
    # Add HDMI disable settings at the end of the file
    log "Adding HDMI disable settings..."
    
    # Ensure file ends with newline
    if [ -n "$(tail -c 1 "$config_file" 2>/dev/null)" ]; then
        echo "" >> "$config_file"
    fi
    
    # Add comment and settings
    cat >> "$config_file" << 'EOF'

# HDMI Disabled - Added by raspberry-pi-disable-hdmi.sh
# These settings permanently disable HDMI output
hdmi_blanking=1
hdmi_ignore_hotplug=1
hdmi_force_hotplug=0
EOF
    
    log_success "HDMI disable settings added to configuration"
}

# Function to verify changes
verify_changes() {
    local config_file="$1"
    
    log "Verifying configuration changes..."
    
    if grep -q "^hdmi_blanking=1" "$config_file" && \
       grep -q "^hdmi_ignore_hotplug=1" "$config_file" && \
       grep -q "^hdmi_force_hotplug=0" "$config_file"; then
        log_success "HDMI disable settings verified in configuration file"
        return 0
    else
        log_error "Failed to verify HDMI disable settings"
        return 1
    fi
}

# Function to disable HDMI immediately (before reboot)
disable_hdmi_immediately() {
    log "Disabling HDMI output immediately..."
    
    # Try using vcgencmd (modern method, preferred)
    if command -v vcgencmd >/dev/null 2>&1; then
        log "Using vcgencmd to disable HDMI..."
        if vcgencmd display_power 0 >/dev/null 2>&1; then
            log_success "HDMI output disabled immediately using vcgencmd"
            return 0
        else
            log_warning "vcgencmd display_power 0 failed, trying alternative method..."
        fi
    fi
    
    # Fallback: Try using tvservice (older method, deprecated but may work)
    if command -v tvservice >/dev/null 2>&1; then
        log "Using tvservice to disable HDMI..."
        if tvservice -o >/dev/null 2>&1; then
            log_success "HDMI output disabled immediately using tvservice"
            return 0
        else
            log_warning "tvservice -o failed"
        fi
    fi
    
    # If both methods fail, warn but don't exit (config changes will still work after reboot)
    log_warning "Could not disable HDMI immediately. HDMI will be disabled after reboot."
    log_warning "This may be normal if HDMI is already off or not connected."
    return 1
}

# Function to display post-installation instructions
show_post_install_instructions() {
    echo
    log_success "HDMI disable configuration completed!"
    echo
    log_success "HDMI output has been disabled immediately (takes effect now)"
    log_warning "IMPORTANT: A system reboot is recommended to ensure permanent persistence"
    echo
    log "Post-installation steps:"
    echo "1. HDMI is already disabled and will remain off"
    echo "2. Reboot your Raspberry Pi to ensure settings persist: sudo reboot"
    echo "3. After reboot, HDMI output will remain permanently disabled via boot configuration"
    echo "4. To re-enable HDMI in the future, edit the boot config file and remove or comment out:"
    echo "   - hdmi_blanking=1"
    echo "   - hdmi_ignore_hotplug=1"
    echo "   - hdmi_force_hotplug=0"
    echo "   Then run: vcgencmd display_power 1 (or reboot)"
    echo
    log "Configuration file location: $CONFIG_FILE"
    log "Backup file location: $BACKUP_FILE"
    echo
}

# Main function
main() {
    echo "========================================"
    echo "Raspberry Pi HDMI Disable Script"
    echo "========================================"
    echo
    
    # Check if running on Raspberry Pi
    check_raspberry_pi
    
    # Find boot config file
    CONFIG_FILE=$(find_boot_config)
    log_success "Found boot configuration file: $CONFIG_FILE"
    
    # Check if HDMI is already disabled
    if check_hdmi_disabled "$CONFIG_FILE"; then
        log_warning "HDMI appears to be already disabled in the configuration"
        read -p "Do you want to continue and ensure settings are correct? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Operation cancelled."
            exit 0
        fi
    fi
    
    # Backup config file
    BACKUP_FILE=$(backup_config "$CONFIG_FILE")
    
    # Disable HDMI
    disable_hdmi "$CONFIG_FILE"
    
    # Verify changes
    if ! verify_changes "$CONFIG_FILE"; then
        log_error "Verification failed. Restoring from backup..."
        cp "$BACKUP_FILE" "$CONFIG_FILE"
        error_exit "Failed to disable HDMI. Configuration restored from backup."
    fi
    
    # Disable HDMI immediately (before reboot)
    disable_hdmi_immediately
    
    # Show post-installation instructions
    show_post_install_instructions
    
    log_success "Script completed successfully!"
    log "HDMI is now disabled. Reboot recommended for permanent persistence: sudo reboot"
}

# Run main function
main "$@"

