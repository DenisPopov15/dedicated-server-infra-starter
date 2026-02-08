#!/bin/bash

# NVM and Node.js Setup Script
# This script installs NVM (Node Version Manager) and Node.js v20.0.0 (with npm)
# Designed for Raspberry Pi and other Linux systems
# Usage: ./node-setup.sh

set -euo pipefail  # Exit on error, undefined vars, pipe failures

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
    if [ -s "$HOME/.nvm/nvm.sh" ]; then
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
        return 0
    elif [ -n "${NVM_DIR:-}" ] && [ -s "$NVM_DIR/nvm.sh" ]; then
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
        return 0
    fi
    
    return 1
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
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    elif command -v wget &> /dev/null; then
        wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
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
    
    # Install the specific Node.js version
    if nvm install "$NODE_VERSION"; then
        log_success "Node.js $NODE_VERSION installed successfully"
    else
        error_exit "Failed to install Node.js $NODE_VERSION"
    fi
    
    # Set as default version
    log "Setting Node.js $NODE_VERSION as default..."
    if nvm alias default "$NODE_VERSION"; then
        log_success "Node.js $NODE_VERSION set as default"
    else
        log_warning "Failed to set Node.js $NODE_VERSION as default, but installation succeeded"
    fi
    
    # Use the version in current session
    nvm use "$NODE_VERSION" || log_warning "Failed to switch to Node.js $NODE_VERSION in current session"
}

# Function to verify installation
verify_installation() {
    log "Verifying installation..."
    
    if ! source_nvm; then
        error_exit "Failed to source NVM for verification"
    fi
    
    # Check Node.js version
    if command -v node &> /dev/null; then
        NODE_VER=$(node --version)
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
        NPM_VER=$(npm --version)
        log_success "npm version: $NPM_VER"
    else
        error_exit "npm command not found after installation"
    fi
    
    # Check nvm version
    if command -v nvm &> /dev/null; then
        NVM_VER=$(nvm --version)
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

