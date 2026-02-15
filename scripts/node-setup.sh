#!/bin/bash

# NVM and Node.js Setup Script
# This script installs NVM (Node Version Manager) and Node.js v20.0.0 (with npm)
# Designed for Raspberry Pi and other Linux systems
# Usage: ./node-setup.sh

set -eo pipefail  # Exit on error, pipe failures (removed -u to handle NVM's unbound variables)

# Set TERM if not set (fixes tput errors in non-interactive environments)
export TERM="${TERM:-dumb}"

# Set basic locale if not set (fixes locale warnings)
export LC_ALL="${LC_ALL:-C.UTF-8}"
export LANG="${LANG:-C.UTF-8}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Node.js version to install
NODE_VERSION="v20.0.0"

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

# Function to check if nvm is installed
check_nvm_installed() {
    # Check if NVM_DIR is set and directory exists
    if [ -n "${NVM_DIR:-}" ] && [ -d "$NVM_DIR" ]; then
        return 0
    fi
    
    # Check if ~/.nvm directory exists
    if [ -d "$HOME/.nvm" ]; then
        return 0
    fi
    
    # Check if nvm command is available (might be in PATH but not sourced)
    if command -v nvm &> /dev/null; then
        return 0
    fi
    
    return 1
}

# Function to source nvm
source_nvm() {
    # Try to source nvm from common locations
    # Suppress errors from tput and unbound variables
    if [ -s "$HOME/.nvm/nvm.sh" ]; then
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" 2>/dev/null || true
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" 2>/dev/null || true
        return 0
    elif [ -n "${NVM_DIR:-}" ] && [ -s "$NVM_DIR/nvm.sh" ]; then
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" 2>/dev/null || true
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" 2>/dev/null || true
        return 0
    fi
    
    return 1
}

# Function to check libstdc++ compatibility
check_libstdcxx_compatibility() {
    log "Checking system library compatibility..."
    
    # Find libstdc++ library
    local libstdcxx_path=""
    if [ -f "/usr/lib/arm-linux-gnueabihf/libstdc++.so.6" ]; then
        libstdcxx_path="/usr/lib/arm-linux-gnueabihf/libstdc++.so.6"
    elif [ -f "/lib/arm-linux-gnueabihf/libstdc++.so.6" ]; then
        libstdcxx_path="/lib/arm-linux-gnueabihf/libstdc++.so.6"
    elif command -v find &> /dev/null; then
        libstdcxx_path=$(find /usr/lib /lib -name "libstdc++.so.6" 2>/dev/null | head -n 1)
    fi
    
    if [ -z "$libstdcxx_path" ]; then
        log_warning "Could not find libstdc++.so.6, skipping compatibility check"
        return 0
    fi
    
    # Check available GLIBCXX versions
    local available_versions
    available_versions=$(strings "$libstdcxx_path" 2>/dev/null | grep "^GLIBCXX" | sort -V | tail -n 1 || echo "")
    
    if [ -z "$available_versions" ]; then
        log_warning "Could not determine libstdc++ version, proceeding anyway"
        return 0
    fi
    
    # Extract version number (e.g., GLIBCXX_3.4.26 -> 3.4.26)
    local max_version
    max_version=$(echo "$available_versions" | sed 's/GLIBCXX_//')
    
    log "Maximum available GLIBCXX version: $max_version"
    
    # Node.js v20.0.0 requires GLIBCXX_3.4.26
    # Compare versions (simple check - if max is less than 3.4.26, warn)
    local required_major=3
    local required_minor=4
    local required_patch=26
    
    local max_major max_minor max_patch
    max_major=$(echo "$max_version" | cut -d. -f1)
    max_minor=$(echo "$max_version" | cut -d. -f2)
    max_patch=$(echo "$max_version" | cut -d. -f3)
    
    # Ensure we have valid numeric values
    if ! [[ "$max_major" =~ ^[0-9]+$ ]] || ! [[ "$max_minor" =~ ^[0-9]+$ ]]; then
        log_warning "Could not parse libstdc++ version properly, skipping compatibility check"
        return 0
    fi
    
    # Default patch to 0 if not present
    max_patch="${max_patch:-0}"
    if ! [[ "$max_patch" =~ ^[0-9]+$ ]]; then
        max_patch=0
    fi
    
    # Simple version comparison
    if [ "$max_major" -lt "$required_major" ] || \
       ([ "$max_major" -eq "$required_major" ] && [ "$max_minor" -lt "$required_minor" ]) || \
       ([ "$max_major" -eq "$required_major" ] && [ "$max_minor" -eq "$required_minor" ] && [ "$max_patch" -lt "$required_patch" ]); then
        log_error "System libstdc++ version ($max_version) may be too old for Node.js $NODE_VERSION"
        log_error "Node.js $NODE_VERSION requires GLIBCXX_3.4.26 or higher"
        log ""
        log "Possible solutions:"
        log "1. Update your system: sudo apt-get update && sudo apt-get upgrade"
        log "2. Install newer libstdc++: sudo apt-get install libstdc++6"
        log "3. Use a different Node.js version (e.g., v18.x or v16.x)"
        log "4. Build Node.js from source (slower but more compatible)"
        log ""
        
        # Only prompt in interactive mode
        if [ -t 0 ]; then
            read -p "Continue anyway? (y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                error_exit "Installation cancelled by user"
            fi
            log_warning "Proceeding with installation despite compatibility warning..."
        else
            log_warning "Non-interactive mode: proceeding with installation despite compatibility warning..."
            log_warning "If installation fails, please update libstdc++ manually"
        fi
    else
        log_success "System libraries appear compatible"
    fi
}

# Function to install nvm
install_nvm() {
    log "Installing NVM (Node Version Manager)..."
    
    # Check for required dependencies
    if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
        log "Installing curl (required for NVM installation)..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update -qq
            sudo apt-get install -y curl
        elif command -v yum &> /dev/null; then
            sudo yum install -y curl
        else
            error_exit "Neither curl nor wget is available, and package manager not recognized. Please install curl manually."
        fi
    fi
    
    # Download and install nvm using the official install script
    log "Downloading NVM installation script..."
    if command -v curl &> /dev/null; then
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh 2>&1 | \
            bash 2>&1 | grep -v "tput: unknown terminal" | grep -v "manpath:" || true
    elif command -v wget &> /dev/null; then
        wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh 2>&1 | \
            bash 2>&1 | grep -v "tput: unknown terminal" | grep -v "manpath:" || true
    else
        error_exit "Neither curl nor wget is available for downloading NVM"
    fi
    
    # Source nvm after installation
    if ! source_nvm; then
        error_exit "Failed to source NVM after installation"
    fi
    
    log_success "NVM installed successfully"
}

# Function to check if Node.js version is installed
check_node_installed() {
    if ! source_nvm; then
        return 1
    fi
    
    # Use nvm which to check if version is installed (returns 0 if found, non-zero if not)
    if nvm which "$NODE_VERSION" &> /dev/null; then
        return 0
    fi
    
    # Fallback: check nvm list output
    if nvm list | grep -q "$NODE_VERSION"; then
        return 0
    fi
    
    return 1
}

# Function to install Node.js
install_node() {
    log "Installing Node.js $NODE_VERSION..."
    
    if ! source_nvm; then
        error_exit "Failed to source NVM. Cannot install Node.js"
    fi
    
    # Check library compatibility before installation
    check_libstdcxx_compatibility
    
    # Install the specific Node.js version
    # Redirect stderr to filter out tput and manpath warnings
    local install_output
    install_output=$(nvm install "$NODE_VERSION" 2>&1) || {
        # Filter out non-critical errors
        if echo "$install_output" | grep -q "GLIBCXX"; then
            error_exit "Node.js installation failed due to incompatible system libraries. Please update libstdc++ or use a different Node.js version."
        fi
        error_exit "Failed to install Node.js $NODE_VERSION"
    }
    
    # Filter and display output (suppress tput and manpath warnings)
    echo "$install_output" | grep -v "tput: unknown terminal" | grep -v "manpath:" || true
    
    # Verify installation succeeded
    if ! source_nvm; then
        error_exit "Failed to source NVM after installation"
    fi
    
    # Check if node command is available
    if nvm use "$NODE_VERSION" &>/dev/null && command -v node &>/dev/null; then
        log_success "Node.js $NODE_VERSION installed successfully"
    else
        # Check if it's a library compatibility issue
        if node --version &>/dev/null; then
            log_success "Node.js $NODE_VERSION installed successfully"
        else
            local node_error
            node_error=$(node --version 2>&1 || true)
            if echo "$node_error" | grep -q "GLIBCXX"; then
                error_exit "Node.js installed but cannot run due to incompatible system libraries. Please update libstdc++: sudo apt-get update && sudo apt-get install libstdc++6"
            fi
            error_exit "Node.js installation may have failed. Error: $node_error"
        fi
    fi
    
    # Set as default version
    log "Setting Node.js $NODE_VERSION as default..."
    if nvm alias default "$NODE_VERSION" 2>&1 | grep -v "tput: unknown terminal" | grep -v "manpath:" >/dev/null; then
        log_success "Node.js $NODE_VERSION set as default"
    else
        log_warning "Failed to set Node.js $NODE_VERSION as default, but installation succeeded"
    fi
    
    # Use the version in current session
    nvm use "$NODE_VERSION" 2>&1 | grep -v "tput: unknown terminal" | grep -v "manpath:" >/dev/null || log_warning "Failed to switch to Node.js $NODE_VERSION in current session"
}

# Function to verify installation
verify_installation() {
    log "Verifying installation..."
    
    if ! source_nvm; then
        error_exit "Failed to source NVM for verification"
    fi
    
    # Check Node.js version
    if command -v node &> /dev/null; then
        local node_error
        NODE_VER=$(node --version 2>&1) || {
            node_error=$(node --version 2>&1)
            if echo "$node_error" | grep -q "GLIBCXX"; then
                error_exit "Node.js is installed but cannot run due to incompatible system libraries (GLIBCXX). Please run: sudo apt-get update && sudo apt-get install libstdc++6"
            fi
            error_exit "Failed to get Node.js version: $node_error"
        }
        log_success "Node.js version: $NODE_VER"
        
        # Verify it's the correct version
        if [ "$NODE_VER" = "$NODE_VERSION" ]; then
            log_success "Correct Node.js version is active: $NODE_VER"
        else
            log_warning "Node.js version is $NODE_VER, expected $NODE_VERSION"
            log_warning "You may need to run: nvm use $NODE_VERSION"
        fi
    else
        error_exit "Node.js command not found after installation"
    fi
    
    # Check npm version
    if command -v npm &> /dev/null; then
        NPM_VER=$(npm --version 2>&1 | grep -v "tput: unknown terminal" | grep -v "manpath:" || echo "unknown")
        log_success "npm version: $NPM_VER"
    else
        error_exit "npm command not found after installation"
    fi
    
    # Check nvm version
    if command -v nvm &> /dev/null; then
        NVM_VER=$(nvm --version 2>&1 | grep -v "tput: unknown terminal" || echo "unknown")
        log_success "NVM version: $NVM_VER"
    fi
}

# Function to display post-installation instructions
show_post_install_instructions() {
    echo
    log_success "NVM and Node.js setup completed!"
    echo
    log "Post-installation notes:"
    echo "1. NVM is installed in: ${NVM_DIR:-$HOME/.nvm}"
    echo "2. Node.js $NODE_VERSION is set as the default version"
    echo "3. To use NVM in new terminal sessions, add the following to your ~/.bashrc or ~/.zshrc:"
    echo ""
    echo "   export NVM_DIR=\"\$HOME/.nvm\""
    echo "   [ -s \"\$NVM_DIR/nvm.sh\" ] && \\. \"\$NVM_DIR/nvm.sh\""
    echo "   [ -s \"\$NVM_DIR/bash_completion\" ] && \\. \"\$NVM_DIR/bash_completion\""
    echo ""
    log "Useful commands:"
    echo "  - nvm list                    # List installed Node.js versions"
    echo "  - nvm install <version>       # Install a specific Node.js version"
    echo "  - nvm use <version>           # Switch to a specific Node.js version"
    echo "  - nvm alias default <version> # Set default Node.js version"
    echo "  - node --version              # Check current Node.js version"
    echo "  - npm --version               # Check npm version"
    echo ""
}

# Main installation function
main() {
    echo "========================================"
    echo "NVM and Node.js Setup Script"
    echo "========================================"
    echo
    
    log "Starting NVM and Node.js installation process..."
    
    # Check if nvm is already installed
    if check_nvm_installed; then
        log_success "NVM is already installed"
        
        # Try to source it
        if source_nvm; then
            log_success "NVM sourced successfully"
        else
            log_warning "NVM directory exists but could not be sourced"
            log_warning "This might be normal if running in a non-interactive shell"
        fi
    else
        log "NVM is not installed. Installing NVM..."
        install_nvm
    fi
    
    # Source nvm for the rest of the script
    if ! source_nvm; then
        error_exit "Failed to source NVM. Cannot proceed with Node.js installation"
    fi
    
    # Check if Node.js version is already installed
    if check_node_installed; then
        log_success "Node.js $NODE_VERSION is already installed"
        
        # Set as default if not already
        CURRENT_DEFAULT=$(nvm alias default 2>/dev/null | awk '{print $3}' || echo "")
        if [ "$CURRENT_DEFAULT" != "$NODE_VERSION" ]; then
            log "Setting Node.js $NODE_VERSION as default..."
            nvm alias default "$NODE_VERSION" || log_warning "Failed to set default version"
        else
            log_success "Node.js $NODE_VERSION is already set as default"
        fi
        
        # Use the version in current session
        nvm use "$NODE_VERSION" || log_warning "Failed to switch to Node.js $NODE_VERSION"
    else
        log "Node.js $NODE_VERSION is not installed. Installing..."
        install_node
    fi
    
    # Verify installation
    verify_installation
    
    # Show post-installation instructions
    show_post_install_instructions
    
    log_success "Setup script completed successfully!"
}

# Run main function
main "$@"

