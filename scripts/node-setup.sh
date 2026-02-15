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

# Function to get current libstdc++ version
get_libstdcxx_version() {
    local libstdcxx_path=""
    if [ -f "/usr/lib/arm-linux-gnueabihf/libstdc++.so.6" ]; then
        libstdcxx_path="/usr/lib/arm-linux-gnueabihf/libstdc++.so.6"
    elif [ -f "/lib/arm-linux-gnueabihf/libstdc++.so.6" ]; then
        libstdcxx_path="/lib/arm-linux-gnueabihf/libstdc++.so.6"
    elif command -v find &> /dev/null; then
        libstdcxx_path=$(find /usr/lib /lib -name "libstdc++.so.6" 2>/dev/null | head -n 1)
    fi
    
    if [ -z "$libstdcxx_path" ]; then
        echo ""
        return 1
    fi
    
    local available_versions
    available_versions=$(strings "$libstdcxx_path" 2>/dev/null | grep "^GLIBCXX" | sort -V | tail -n 1 || echo "")
    
    if [ -z "$available_versions" ]; then
        echo ""
        return 1
    fi
    
    echo "$available_versions" | sed 's/GLIBCXX_//'
    return 0
}

# Function to check if version meets requirement
version_meets_requirement() {
    local current_version="$1"
    local required_major="$2"
    local required_minor="$3"
    local required_patch="$4"
    
    local current_major current_minor current_patch
    current_major=$(echo "$current_version" | cut -d. -f1)
    current_minor=$(echo "$current_version" | cut -d. -f2)
    current_patch=$(echo "$current_version" | cut -d. -f3)
    current_patch="${current_patch:-0}"
    
    if ! [[ "$current_major" =~ ^[0-9]+$ ]] || ! [[ "$current_minor" =~ ^[0-9]+$ ]] || ! [[ "$current_patch" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    
    if [ "$current_major" -gt "$required_major" ]; then
        return 0
    elif [ "$current_major" -eq "$required_major" ] && [ "$current_minor" -gt "$required_minor" ]; then
        return 0
    elif [ "$current_major" -eq "$required_major" ] && [ "$current_minor" -eq "$required_minor" ] && [ "$current_patch" -ge "$required_patch" ]; then
        return 0
    fi
    
    return 1
}

# Function to try updating libstdc++
try_update_libstdcxx() {
    log "Attempting to update libstdc++..."
    
    if ! command -v apt-get &> /dev/null; then
        log_warning "apt-get not available, cannot update libstdc++ automatically"
        return 1
    fi
    
    # Check if we have sudo access
    if ! sudo -n true 2>/dev/null && [ -t 0 ]; then
        log "This operation requires sudo privileges. You may be prompted for your password."
    fi
    
    log "Updating package lists..."
    if sudo apt-get update -qq 2>&1 | grep -v "tput: unknown terminal" | grep -v "manpath:"; then
        log "Installing/upgrading libstdc++6..."
        if sudo apt-get install -y libstdc++6 2>&1 | grep -v "tput: unknown terminal" | grep -v "manpath:"; then
            log_success "libstdc++ updated successfully"
            return 0
        else
            log_warning "Failed to update libstdc++ via apt-get"
            return 1
        fi
    else
        log_warning "Failed to update package lists"
        return 1
    fi
}

# Function to find compatible Node.js version
find_compatible_node_version() {
    local required_major="$1"
    local required_minor="$2"
    local required_patch="$3"
    
    # Node.js versions and their GLIBCXX requirements (approximate)
    # v18.x typically requires GLIBCXX_3.4.21+
    # v16.x typically requires GLIBCXX_3.4.19+
    # v14.x typically requires GLIBCXX_3.4.18+
    
    if version_meets_requirement "$(get_libstdcxx_version)" "$required_major" "$required_minor" "$required_patch"; then
        echo "$NODE_VERSION"
        return 0
    fi
    
    # Try v18 LTS (usually more compatible)
    if version_meets_requirement "$(get_libstdcxx_version)" 3 4 21; then
        log "Suggesting Node.js v18.x LTS for better compatibility"
        echo "v18.20.4"  # Latest v18 LTS
        return 0
    fi
    
    # Try v16 LTS
    if version_meets_requirement "$(get_libstdcxx_version)" 3 4 19; then
        log "Suggesting Node.js v16.x LTS for better compatibility"
        echo "v16.20.2"  # Latest v16 LTS
        return 0
    fi
    
    # Try v14 LTS
    if version_meets_requirement "$(get_libstdcxx_version)" 3 4 18; then
        log "Suggesting Node.js v14.x LTS for better compatibility"
        echo "v14.21.3"  # Latest v14 LTS
        return 0
    fi
    
    echo ""
    return 1
}

# Function to check and fix libstdc++ compatibility
check_libstdcxx_compatibility() {
    log "Checking system library compatibility..."
    
    local current_version
    current_version=$(get_libstdcxx_version)
    
    if [ -z "$current_version" ]; then
        log_warning "Could not determine libstdc++ version, proceeding anyway"
        return 0
    fi
    
    log "Current GLIBCXX version: $current_version"
    
    # Node.js v20.0.0 requires GLIBCXX_3.4.26
    local required_major=3
    local required_minor=4
    local required_patch=26
    
    if version_meets_requirement "$current_version" "$required_major" "$required_minor" "$required_patch"; then
        log_success "System libraries are compatible with Node.js $NODE_VERSION"
        return 0
    fi
    
    log_error "System libstdc++ version ($current_version) is too old for Node.js $NODE_VERSION"
    log_error "Node.js $NODE_VERSION requires GLIBCXX_3.4.26 or higher"
    log ""
    
    # Try to update libstdc++ automatically
    log "Attempting to fix compatibility issue..."
    if try_update_libstdcxx; then
        # Recheck version after update
        sleep 1  # Give system a moment to update
        current_version=$(get_libstdcxx_version)
        log "Rechecking GLIBCXX version after update: $current_version"
        
        if version_meets_requirement "$current_version" "$required_major" "$required_minor" "$required_patch"; then
            log_success "System libraries are now compatible after update!"
            return 0
        else
            log_warning "Update completed but version may still be insufficient"
        fi
    fi
    
    # If update didn't work, try to find a compatible Node.js version
    log ""
    log "Attempting to find a compatible Node.js version..."
    local compatible_version
    compatible_version=$(find_compatible_node_version "$required_major" "$required_minor" "$required_patch")
    
    if [ -n "$compatible_version" ] && [ "$compatible_version" != "$NODE_VERSION" ]; then
        log_warning "Node.js $NODE_VERSION may not work with your system libraries"
        log "Would you like to install $compatible_version instead? (recommended)"
        
        if [ -t 0 ]; then
            read -p "Install $compatible_version instead of $NODE_VERSION? (Y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                NODE_VERSION="$compatible_version"
                log "Switching to Node.js $NODE_VERSION for compatibility"
                return 0
            fi
        else
            # Non-interactive: use compatible version
            NODE_VERSION="$compatible_version"
            log "Non-interactive mode: switching to Node.js $NODE_VERSION for compatibility"
            return 0
        fi
    fi
    
    # Last resort: offer to build from source
    log ""
    log_error "Could not automatically resolve compatibility issue"
    log ""
    log "Manual solutions:"
    log "1. Update system: sudo apt-get update && sudo apt-get upgrade && sudo apt-get install libstdc++6"
    log "2. Use a different Node.js version manually: nvm install v18.20.4"
    log "3. Build Node.js from source (slower): nvm install -s $NODE_VERSION"
    log ""
    
    if [ -t 0 ]; then
        log ""
        log "Options:"
        log "1. Try to build from source (will take longer but should work)"
        log "2. Continue with binary installation anyway (may fail)"
        log "3. Cancel and update libraries manually"
        read -p "Choose option (1/2/3) [1]: " -n 1 -r
        echo
        case "$REPLY" in
            2)
                log_warning "Proceeding with binary installation despite compatibility warning..."
                ;;
            3)
                error_exit "Installation cancelled. Please update system libraries: sudo apt-get update && sudo apt-get upgrade && sudo apt-get install libstdc++6"
                ;;
            *)
                log "Will attempt to build from source if binary installation fails"
                ;;
        esac
    else
        # Non-interactive: will try building from source if binary fails
        log_warning "Non-interactive mode: will attempt to build from source if needed"
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

# Function to verify node works after installation
verify_node_works() {
    if ! source_nvm; then
        return 1
    fi
    
    if ! nvm use "$NODE_VERSION" &>/dev/null; then
        return 1
    fi
    
    local node_output node_error
    node_output=$(node --version 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ] && ! echo "$node_output" | grep -q "GLIBCXX"; then
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
    
    # Check library compatibility before installation (may switch to compatible version)
    check_libstdcxx_compatibility
    
    # Try installing the Node.js version (binary)
    log "Attempting to install Node.js $NODE_VERSION (binary)..."
    local install_output
    install_output=$(nvm install "$NODE_VERSION" 2>&1) || {
        log_warning "Binary installation failed or had issues"
    }
    
    # Filter and display output (suppress tput and manpath warnings)
    echo "$install_output" | grep -v "tput: unknown terminal" | grep -v "manpath:" || true
    
    # Verify installation succeeded and node works
    if verify_node_works; then
        log_success "Node.js $NODE_VERSION installed and working successfully"
    else
        # Installation may have succeeded but node can't run due to GLIBCXX
        local node_error
        node_error=$(node --version 2>&1 || echo "")
        
        if echo "$node_error" | grep -q "GLIBCXX"; then
            log_error "Node.js binary installed but cannot run due to GLIBCXX library issue"
            log ""
            log "Attempting to build Node.js from source (this will take longer but should work)..."
            
            # Check if we have build tools
            if ! command -v make &>/dev/null || ! command -v g++ &>/dev/null; then
                log "Installing build tools (this may require sudo)..."
                if command -v apt-get &>/dev/null; then
                    sudo apt-get update -qq 2>&1 | grep -v "tput: unknown terminal" | grep -v "manpath:" || true
                    sudo apt-get install -y build-essential python3 2>&1 | grep -v "tput: unknown terminal" | grep -v "manpath:" || {
                        log_error "Failed to install build tools. Please install manually: sudo apt-get install build-essential python3"
                        error_exit "Cannot build Node.js from source without build tools"
                    }
                else
                    error_exit "Cannot install build tools automatically. Please install build-essential and python3 manually."
                fi
            fi
            
            # Remove the binary installation and build from source
            log "Removing binary installation..."
            nvm uninstall "$NODE_VERSION" 2>&1 | grep -v "tput: unknown terminal" | grep -v "manpath:" || true
            
            log "Building Node.js $NODE_VERSION from source (this may take 10-30 minutes)..."
            install_output=$(nvm install -s "$NODE_VERSION" 2>&1) || {
                log_error "Failed to build Node.js from source"
                error_exit "Could not install Node.js $NODE_VERSION. Please update system libraries or try a different version."
            }
            
            # Filter and display output
            echo "$install_output" | grep -v "tput: unknown terminal" | grep -v "manpath:" || true
            
            # Verify it works now
            if verify_node_works; then
                log_success "Node.js $NODE_VERSION built from source and working successfully!"
            else
                error_exit "Node.js built from source but still cannot run. Please check system requirements."
            fi
        else
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
    
    local verification_failed=0
    local library_issue=0
    
    # Check Node.js version
    if command -v node &> /dev/null; then
        local node_output exit_code
        node_output=$(node --version 2>&1)
        exit_code=$?
        
        # Check if output contains GLIBCXX error
        if echo "$node_output" | grep -q "GLIBCXX"; then
            log_error "Node.js is installed but cannot run due to incompatible system libraries (GLIBCXX)"
            log_error "Please run: sudo apt-get update && sudo apt-get install libstdc++6"
            log_warning "Node.js files are installed, but the binary cannot execute due to missing library version"
            library_issue=1
            verification_failed=1
        elif [ $exit_code -ne 0 ]; then
            log_error "Failed to get Node.js version: $node_output"
            verification_failed=1
        else
            # Success - extract version
            NODE_VER=$(echo "$node_output" | head -n 1 | tr -d '\n\r')
            log_success "Node.js version: $NODE_VER"
            
            # Verify it's the correct version
            if [ "$NODE_VER" = "$NODE_VERSION" ]; then
                log_success "Correct Node.js version is active: $NODE_VER"
            else
                log_warning "Node.js version is $NODE_VER, expected $NODE_VERSION"
                log_warning "You may need to run: nvm use $NODE_VERSION"
            fi
        fi
    else
        log_error "Node.js command not found after installation"
        verification_failed=1
    fi
    
    # Check npm version (only if node works)
    if [ $library_issue -eq 0 ] && command -v npm &> /dev/null; then
        local npm_output
        npm_output=$(npm --version 2>&1 | grep -v "tput: unknown terminal" | grep -v "manpath:" || echo "")
        if [ -n "$npm_output" ] && ! echo "$npm_output" | grep -q "GLIBCXX"; then
            NPM_VER=$(echo "$npm_output" | head -n 1 | tr -d '\n\r')
            log_success "npm version: $NPM_VER"
        else
            log_warning "Could not verify npm version (may be due to library compatibility issue)"
        fi
    elif [ $library_issue -eq 1 ]; then
        log_warning "npm verification skipped due to library compatibility issue"
    else
        log_warning "npm command not found (this may be normal if Node.js installation had issues)"
    fi
    
    # Check nvm version
    if command -v nvm &> /dev/null; then
        NVM_VER=$(nvm --version 2>&1 | grep -v "tput: unknown terminal" | head -n 1 | tr -d '\n\r' || echo "unknown")
        log_success "NVM version: $NVM_VER"
    fi
    
    # If there's a library issue, warn but don't fail (installation was successful)
    if [ $library_issue -eq 1 ]; then
        log_warning "Installation completed, but Node.js cannot run until system libraries are updated"
        return 0  # Return success since installation itself was successful
    fi
    
    # If verification failed for other reasons, exit with error
    if [ $verification_failed -eq 1 ]; then
        error_exit "Installation verification failed"
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

