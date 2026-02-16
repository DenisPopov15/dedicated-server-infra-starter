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
# NODE_VERSION="v20.0.0"
NODE_VERSION="v18.0.0"

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
    
    if [ -z "$libstdcxx_path" ] || [ ! -f "$libstdcxx_path" ]; then
        echo ""
        return 1
    fi
    
    # Extract GLIBCXX versions - use a simpler approach with sort
    # Use timeout to prevent hanging on large files
    local glibcxx_versions
    local strings_cmd="strings \"$libstdcxx_path\" 2>/dev/null"
    
    if command -v timeout &> /dev/null; then
        glibcxx_versions=$(eval "timeout 5 $strings_cmd" | grep -E "^GLIBCXX_[0-9]+\.[0-9]+(\.[0-9]+)?$" | sed 's/^GLIBCXX_//' | head -n 50)
    else
        # Without timeout, just run it (might be slow but won't hang forever)
        glibcxx_versions=$(eval "$strings_cmd" | grep -E "^GLIBCXX_[0-9]+\.[0-9]+(\.[0-9]+)?$" | sed 's/^GLIBCXX_//' | head -n 50)
    fi
    
    if [ -z "$glibcxx_versions" ]; then
        echo ""
        return 1
    fi
    
    # Normalize all versions to 3 components for proper comparison
    # "3.4" becomes "3.4.0", "3.4.26" stays "3.4.26"
    local normalized_list=""
    while IFS= read -r version; do
        local major minor patch
        major=$(echo "$version" | cut -d. -f1)
        minor=$(echo "$version" | cut -d. -f2)
        patch=$(echo "$version" | cut -d. -f3)
        patch="${patch:-0}"
        normalized_list="${normalized_list}${major}.${minor}.${patch}"$'\n'
    done <<< "$glibcxx_versions"
    
    # Sort and get the highest normalized version
    local max_normalized
    max_normalized=$(echo "$normalized_list" | sort -V 2>/dev/null | tail -n 1)
    
    if [ -z "$max_normalized" ]; then
        echo ""
        return 1
    fi
    
    # Find the original version that matches this normalized maximum
    # Prefer versions with patch numbers if they exist
    local max_version=""
    local max_major max_minor max_patch
    max_major=$(echo "$max_normalized" | cut -d. -f1)
    max_minor=$(echo "$max_normalized" | cut -d. -f2)
    max_patch=$(echo "$max_normalized" | cut -d. -f3)
    
    # Look for the original version - prefer one with patch number if available
    while IFS= read -r version; do
        local v_major v_minor v_patch
        v_major=$(echo "$version" | cut -d. -f1)
        v_minor=$(echo "$version" | cut -d. -f2)
        v_patch=$(echo "$version" | cut -d. -f3)
        
        if [ "$v_major" = "$max_major" ] && [ "$v_minor" = "$max_minor" ]; then
            # If this version has a patch number and it matches, use it
            if [ -n "$v_patch" ] && [ "$v_patch" = "$max_patch" ]; then
                max_version="$version"
                break
            elif [ -z "$max_version" ]; then
                # Store first matching version as fallback
                max_version="$version"
            fi
        fi
    done <<< "$glibcxx_versions"
    
    # If we found a version with patch number matching max_patch, use it
    # Otherwise use what we found
    if [ -z "$max_version" ]; then
        # Fallback: construct from normalized if no match found
        if [ "$max_patch" = "0" ]; then
            max_version="${max_major}.${max_minor}"
        else
            max_version="$max_normalized"
        fi
    fi
    
    # Validate the result
    if [ -z "$max_version" ] || ! echo "$max_version" | grep -qE "^[0-9]+\.[0-9]+(\.[0-9]+)?$"; then
        echo ""
        return 1
    fi
    
    echo "$max_version"
    return 0
}

# Function to check if version meets requirement
version_meets_requirement() {
    local current_version="$1"
    local required_major="$2"
    local required_minor="$3"
    local required_patch="$4"
    
    # Return false if version is empty or invalid
    if [ -z "$current_version" ]; then
        return 1
    fi
    
    # Trim whitespace
    current_version=$(echo "$current_version" | tr -d '[:space:]')
    
    # Validate format
    if ! echo "$current_version" | grep -qE "^[0-9]+\.[0-9]+(\.[0-9]+)?$"; then
        return 1
    fi
    
    local current_major current_minor current_patch
    current_major=$(echo "$current_version" | cut -d. -f1 | tr -d '[:space:]')
    current_minor=$(echo "$current_version" | cut -d. -f2 | tr -d '[:space:]')
    current_patch=$(echo "$current_version" | cut -d. -f3 | tr -d '[:space:]')
    current_patch="${current_patch:-0}"
    
    # Validate all components are numeric and not empty before doing arithmetic
    if [ -z "$current_major" ] || [ -z "$current_minor" ] || [ -z "$current_patch" ]; then
        return 1
    fi
    
    if ! [[ "$current_major" =~ ^[0-9]+$ ]] || ! [[ "$current_minor" =~ ^[0-9]+$ ]] || ! [[ "$current_patch" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    
    # Validate required values are also numeric
    if ! [[ "$required_major" =~ ^[0-9]+$ ]] || ! [[ "$required_minor" =~ ^[0-9]+$ ]] || ! [[ "$required_patch" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    
    # Now safe to do integer comparisons
    if [ "$current_major" -gt "$required_major" ] 2>/dev/null; then
        return 0
    elif [ "$current_major" -eq "$required_major" ] 2>/dev/null && [ "$current_minor" -gt "$required_minor" ] 2>/dev/null; then
        return 0
    elif [ "$current_major" -eq "$required_major" ] 2>/dev/null && [ "$current_minor" -eq "$required_minor" ] 2>/dev/null && [ "$current_patch" -ge "$required_patch" ] 2>/dev/null; then
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
    local update_output update_exit
    update_output=$(sudo apt-get update -qq 2>&1)
    update_exit=$?
    
    # Filter out tput and manpath warnings but preserve exit code
    echo "$update_output" | grep -v "tput: unknown terminal" | grep -v "manpath:" || true
    
    if [ $update_exit -ne 0 ]; then
        log_warning "Failed to update package lists (exit code: $update_exit)"
        return 1
    fi
    
    log "Installing/upgrading libstdc++6..."
    local install_output install_exit
    install_output=$(sudo apt-get install -y libstdc++6 2>&1)
    install_exit=$?
    
    # Filter out tput and manpath warnings but preserve exit code
    echo "$install_output" | grep -v "tput: unknown terminal" | grep -v "manpath:" || true
    
    if [ $install_exit -eq 0 ]; then
        log_success "libstdc++ updated successfully"
        return 0
    else
        log_warning "Failed to update libstdc++ via apt-get (exit code: $install_exit)"
        return 1
    fi
}

# Function to find compatible Node.js version
find_compatible_node_version() {
    local required_major="$1"
    local required_minor="$2"
    local required_patch="$3"
    
    # Validate required parameters are numeric
    if ! [[ "$required_major" =~ ^[0-9]+$ ]] || ! [[ "$required_minor" =~ ^[0-9]+$ ]] || ! [[ "$required_patch" =~ ^[0-9]+$ ]]; then
        echo ""
        return 1
    fi
    
    # Get version once to avoid multiple calls
    local current_version
    current_version=$(get_libstdcxx_version)
    
    # If we can't determine version, can't make recommendations
    if [ -z "$current_version" ]; then
        echo ""
        return 1
    fi
    
    # Validate current_version format before using it
    if ! echo "$current_version" | grep -qE "^[0-9]+\.[0-9]+(\.[0-9]+)?$"; then
        echo ""
        return 1
    fi
    
    # Node.js versions and their GLIBCXX requirements (approximate)
    # v18.x typically requires GLIBCXX_3.4.21+
    # v16.x typically requires GLIBCXX_3.4.19+
    # v14.x typically requires GLIBCXX_3.4.18+
    
    if version_meets_requirement "$current_version" "$required_major" "$required_minor" "$required_patch"; then
        echo "$NODE_VERSION"
        return 0
    fi
    
    # Try v18 LTS (usually more compatible)
    if version_meets_requirement "$current_version" 3 4 21; then
        log "Suggesting Node.js v18.x LTS for better compatibility"
        echo "v18.20.4"  # Latest v18 LTS
        return 0
    fi
    
    # Try v16 LTS
    if version_meets_requirement "$current_version" 3 4 19; then
        log "Suggesting Node.js v16.x LTS for better compatibility"
        echo "v16.20.2"  # Latest v16 LTS
        return 0
    fi
    
    # Try v14 LTS
    if version_meets_requirement "$current_version" 3 4 18; then
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
    
    # Validate the version looks correct (should be like 3.4.26)
    if ! echo "$current_version" | grep -qE "^[0-9]+\.[0-9]+(\.[0-9]+)?$"; then
        log_warning "Invalid libstdc++ version format detected: '$current_version', proceeding anyway"
        return 0
    fi
    
    # Additional sanity check - version should be reasonable
    if [ "$current_version" = "DEBUG_MESSAGE_LENGTH" ] || [ ${#current_version} -gt 20 ] || [ ${#current_version} -lt 3 ]; then
        log_warning "Suspicious libstdc++ version detected: '$current_version', proceeding anyway"
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
    
    # First, check if Node.js actually works (quick check)
    if verify_node_works; then
        # Node.js works, get version and verify
        local node_output
        node_output=$(node --version 2>&1)
        NODE_VER=$(echo "$node_output" | head -n 1 | tr -d '\n\r')
        log_success "Node.js version: $NODE_VER"
        
        # Verify it's the correct version
        if [ "$NODE_VER" = "$NODE_VERSION" ]; then
            log_success "Correct Node.js version is active: $NODE_VER"
        else
            log_warning "Node.js version is $NODE_VER, expected $NODE_VERSION"
            log_warning "You may need to run: nvm use $NODE_VERSION"
        fi
    else
        # Node.js doesn't work, check why
        local verification_failed=0
        local library_issue=0
        
        if command -v node &> /dev/null; then
            local node_output exit_code
            node_output=$(node --version 2>&1)
            exit_code=$?
            
            # Check if output contains GLIBCXX error
            if echo "$node_output" | grep -q "GLIBCXX"; then
                log_error "Node.js is installed but cannot run due to incompatible system libraries (GLIBCXX)"
                library_issue=1
                verification_failed=1
            elif [ $exit_code -ne 0 ]; then
                log_error "Failed to get Node.js version: $node_output"
                verification_failed=1
            fi
        else
            log_error "Node.js command not found after installation"
            verification_failed=1
        fi
        
        # If there's a library issue, this is a real problem (should have been fixed earlier)
        if [ $library_issue -eq 1 ]; then
            log_error "Node.js cannot run due to GLIBCXX library issue"
            log_error "This should have been fixed during installation. Please run manually:"
            log_error "  sudo apt-get update && sudo apt-get upgrade && sudo apt-get install libstdc++6"
            log_error "Or rebuild from source: nvm uninstall $NODE_VERSION && nvm install -s $NODE_VERSION"
            error_exit "Node.js installation verification failed - Node.js cannot run due to library compatibility issues"
        fi
        
        # If verification failed for other reasons, exit with error
        if [ $verification_failed -eq 1 ]; then
            error_exit "Installation verification failed"
        fi
    fi
    
    # Check npm version (only if node works)
    if verify_node_works && command -v npm &> /dev/null; then
        local npm_output
        npm_output=$(npm --version 2>&1 | grep -v "tput: unknown terminal" | grep -v "manpath:" || echo "")
        if [ -n "$npm_output" ] && ! echo "$npm_output" | grep -q "GLIBCXX"; then
            NPM_VER=$(echo "$npm_output" | head -n 1 | tr -d '\n\r')
        log_success "npm version: $NPM_VER"
        else
            log_warning "Could not verify npm version (may be due to library compatibility issue)"
        fi
    else
        log_warning "npm verification skipped (Node.js may not be working or npm not found)"
    fi
    
    # Check nvm version
    if command -v nvm &> /dev/null; then
        NVM_VER=$(nvm --version 2>&1 | grep -v "tput: unknown terminal" | head -n 1 | tr -d '\n\r' || echo "unknown")
        log_success "NVM version: $NVM_VER"
    fi
}

# Function to configure NVM in shell profiles
configure_nvm_in_shell() {
    log "Configuring NVM in shell profiles..."
    
    # Detect if running as root and warn
    local current_user=$(whoami)
    local target_home="$HOME"
    
    # Function to install NVM for a specific user (when running as root)
    install_nvm_for_user() {
        local target_user="$1"
        local target_home=$(eval echo ~$target_user 2>/dev/null)
        
        if [ -z "$target_home" ] || [ "$target_home" = "~$target_user" ]; then
            log_warning "Cannot determine home directory for user $target_user"
            return 1
        fi
        
        if [ ! -d "$target_home" ]; then
            log_warning "Home directory $target_home does not exist for user $target_user"
            return 1
        fi
        
        # Check if NVM is already installed for this user
        if [ -d "$target_home/.nvm" ] && [ -f "$target_home/.nvm/nvm.sh" ]; then
            log "NVM already installed for user $target_user"
            return 0
        fi
        
        log "Installing NVM for user: $target_user (home: $target_home)"
        
        # Install NVM as the target user
        if command -v curl &> /dev/null; then
            if su - "$target_user" -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash" 2>&1 | grep -v "tput: unknown terminal" | grep -v "manpath:"; then
                log_success "NVM installed for user $target_user"
                # Set ownership just in case
                chown -R "$target_user:$target_user" "$target_home/.nvm" 2>/dev/null || true
                return 0
            else
                log_warning "Failed to install NVM for user $target_user"
                return 1
            fi
        elif command -v wget &> /dev/null; then
            if su - "$target_user" -c "wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash" 2>&1 | grep -v "tput: unknown terminal" | grep -v "manpath:"; then
                log_success "NVM installed for user $target_user"
                chown -R "$target_user:$target_user" "$target_home/.nvm" 2>/dev/null || true
                return 0
            else
                log_warning "Failed to install NVM for user $target_user"
                return 1
            fi
        else
            log_warning "Neither curl nor wget available to install NVM for user $target_user"
            return 1
        fi
    }
    
    # Function to configure NVM for a specific user
    configure_for_user() {
        local target_user="$1"
        local target_home=$(eval echo ~$target_user 2>/dev/null)
        
        if [ -z "$target_home" ] || [ "$target_home" = "~$target_user" ]; then
            log_warning "Cannot determine home directory for user $target_user"
            return 1
        fi
        
        if [ ! -d "$target_home" ]; then
            log_warning "Home directory $target_home does not exist for user $target_user"
            return 1
        fi
        
        log "Configuring NVM for user: $target_user (home: $target_home)"
        
        # Check if NVM is installed for this user
        local user_nvm_dir="$target_home/.nvm"
        if [ ! -d "$user_nvm_dir" ] || [ ! -f "$user_nvm_dir/nvm.sh" ]; then
            log_warning "NVM is not installed in $user_nvm_dir for user $target_user"
            log_warning "The profile will be configured, but NVM needs to be installed for this user"
            log "To install NVM for $target_user, run this script as that user (without sudo)"
            log "Or install NVM manually: curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"
        else
            log_success "NVM found in $user_nvm_dir for user $target_user"
        fi
        
        local user_nvm_config="export NVM_DIR=\"\$HOME/.nvm\"
[ -s \"\$NVM_DIR/nvm.sh\" ] && \\. \"\$NVM_DIR/nvm.sh\"
[ -s \"\$NVM_DIR/bash_completion\" ] && \\. \"\$NVM_DIR/bash_completion\""
        
        # Configure .bash_profile (most important for SSH)
        local bash_profile="$target_home/.bash_profile"
        if [ ! -f "$bash_profile" ] || ! grep -qE "(NVM_DIR|nvm\.sh)" "$bash_profile" 2>/dev/null; then
            {
                if [ -f "$bash_profile" ] && [ -s "$bash_profile" ]; then
                    echo ""
                fi
                echo "# NVM configuration - Added by node-setup.sh"
                echo "$user_nvm_config"
            } >> "$bash_profile" 2>/dev/null && log_success "Configured ~/.bash_profile for $target_user" || log_warning "Failed to configure ~/.bash_profile for $target_user"
        fi
        
        # Also configure .bashrc
        local bashrc="$target_home/.bashrc"
        if [ ! -f "$bashrc" ] || ! grep -qE "(NVM_DIR|nvm\.sh)" "$bashrc" 2>/dev/null; then
            {
                if [ -f "$bashrc" ] && [ -s "$bashrc" ]; then
                    echo ""
                fi
                echo "# NVM configuration - Added by node-setup.sh"
                echo "$user_nvm_config"
            } >> "$bashrc" 2>/dev/null && log_success "Configured ~/.bashrc for $target_user" || log_warning "Failed to configure ~/.bashrc for $target_user"
        fi
        
        # Set proper ownership if running as root
        if [ "$current_user" = "root" ]; then
            chown "$target_user:$target_user" "$bash_profile" "$bashrc" 2>/dev/null || true
        fi
    }
    
    if [ "$current_user" = "root" ]; then
        log_warning "Script is running as root. NVM will be configured for root user."
        
        # Try to detect and configure for common non-root users
        local common_users="pi ubuntu debian admin"
        local found_users=""
        for user in $common_users; do
            if id "$user" &>/dev/null; then
                found_users="${found_users}${user} "
                log "Found user: $user"
            fi
        done
        
        if [ -n "$found_users" ]; then
            if [ -t 0 ]; then
                log "Would you like to install and configure NVM for these users as well? (y/N)"
                read -t 10 -p "Install for users: $found_users? (y/N) " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    for user in $found_users; do
                        install_nvm_for_user "$user"
                        configure_for_user "$user"
                    done
                fi
            else
                # Non-interactive: auto-install and configure for common users (especially pi on Raspberry Pi)
                log "Non-interactive mode: Auto-installing and configuring NVM for detected users..."
                for user in $found_users; do
                    install_nvm_for_user "$user"
                    configure_for_user "$user"
                done
            fi
        fi
    fi
    
    local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
    local nvm_config=""
    nvm_config="export NVM_DIR=\"\$HOME/.nvm\"
[ -s \"\$NVM_DIR/nvm.sh\" ] && \\. \"\$NVM_DIR/nvm.sh\"
[ -s \"\$NVM_DIR/bash_completion\" ] && \\. \"\$NVM_DIR/bash_completion\""
    
    local configured=0
    local files_configured=""
    
    # Function to check if NVM is already configured in a file
    is_nvm_configured() {
        local file="$1"
        if [ -f "$file" ]; then
            # Check for NVM_DIR export or nvm.sh sourcing
            if grep -qE "(NVM_DIR|nvm\.sh)" "$file" 2>/dev/null; then
                return 0
            fi
        fi
        return 1
    }
    
    # Function to add NVM config to a file
    add_nvm_config() {
        local file="$1"
        local file_display="$2"
        local force="${3:-0}"  # Optional force parameter
        
        # Check if already configured (unless forcing)
        if [ $force -eq 0 ] && is_nvm_configured "$file"; then
            log "NVM already configured in $file_display"
            return 0
        fi
        
        log "Adding NVM configuration to $file_display..."
        
        # Create directory if needed
        local file_dir=$(dirname "$file")
        if [ ! -d "$file_dir" ]; then
            mkdir -p "$file_dir" 2>/dev/null || {
                log_warning "Cannot create directory for $file_display"
                return 1
            }
        fi
        
        # Append or create file
        {
            if [ -f "$file" ] && [ -s "$file" ]; then
                echo ""
            fi
            echo "# NVM configuration - Added by node-setup.sh"
            echo "$nvm_config"
        } >> "$file" 2>/dev/null
        
        local exit_code=$?
        if [ $exit_code -eq 0 ]; then
            # Verify it was written
            if [ -f "$file" ] && grep -q "NVM_DIR" "$file" 2>/dev/null; then
                configured=1
                files_configured="${files_configured}${file_display} "
                log_success "NVM configured in $file_display"
                return 0
            else
                log_warning "Configuration written but could not verify in $file_display"
                return 1
            fi
        else
            log_warning "Failed to write NVM configuration to $file_display (exit code: $exit_code)"
            return 1
        fi
    }
    
    # Configure .bashrc (most common for interactive shells)
    add_nvm_config "$HOME/.bashrc" "~/.bashrc"
    
    # Configure .bash_profile (used for login shells, especially SSH)
    # Also ensure it sources .bashrc if it exists
    if [ -f "$HOME/.bash_profile" ]; then
        # Check if .bash_profile sources .bashrc
        if ! grep -qE "\.bashrc|source.*bashrc" "$HOME/.bash_profile" 2>/dev/null && [ -f "$HOME/.bashrc" ]; then
            log "Ensuring ~/.bash_profile sources ~/.bashrc..."
            {
                echo ""
                echo "# Source .bashrc if it exists"
                echo "if [ -f ~/.bashrc ]; then"
                echo "    . ~/.bashrc"
                echo "fi"
            } >> "$HOME/.bash_profile"
        fi
    fi
    add_nvm_config "$HOME/.bash_profile" "~/.bash_profile"
    
    # Configure .zshrc (if zsh is used)
    add_nvm_config "$HOME/.zshrc" "~/.zshrc"
    
    # Configure .profile as a fallback (for sh and other shells)
    # Also ensure it sources .bashrc if it exists
    if [ -f "$HOME/.profile" ]; then
        # Check if .profile sources .bashrc
        if ! grep -qE "\.bashrc|source.*bashrc" "$HOME/.profile" 2>/dev/null && [ -f "$HOME/.bashrc" ]; then
            log "Ensuring ~/.profile sources ~/.bashrc..."
            {
                echo ""
                echo "# Source .bashrc if it exists"
                echo "if [ -f ~/.bashrc ]; then"
                echo "    . ~/.bashrc"
                echo "fi"
            } >> "$HOME/.profile"
        fi
    fi
    add_nvm_config "$HOME/.profile" "~/.profile"
    
    # Final verification - check all profile files
    log "Verifying NVM configuration..."
    local verified_files=""
    for profile_file in "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        local file_display="~/.$(basename "$profile_file")"
        if [ -f "$profile_file" ] && grep -qE "(NVM_DIR|nvm\.sh)" "$profile_file" 2>/dev/null; then
            verified_files="${verified_files}${file_display} "
        fi
    done
    
    if [ -n "$verified_files" ]; then
        log_success "NVM configuration verified in: $verified_files"
        log "NVM will be available in new terminal sessions"
        log ""
        log "To use NVM in your current session, run one of:"
        log "  source ~/.bash_profile  # For login shells (SSH)"
        log "  source ~/.bashrc         # For interactive shells"
    else
        log_error "NVM configuration was not found in any profile file!"
        log "Attempting to force-add to ~/.bash_profile and ~/.bashrc..."
        add_nvm_config "$HOME/.bash_profile" "~/.bash_profile" 1
        add_nvm_config "$HOME/.bashrc" "~/.bashrc" 1
        
        # Final check
        if [ -f "$HOME/.bash_profile" ] && grep -q "NVM_DIR" "$HOME/.bash_profile" 2>/dev/null; then
            log_success "NVM configuration added to ~/.bash_profile"
        else
            log_error "Failed to add NVM configuration. Please add manually:"
            echo ""
            echo "Add these lines to ~/.bash_profile:"
            echo "$nvm_config"
            echo ""
        fi
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
    echo "3. NVM has been automatically configured in your shell profile(s)"
    echo ""
    log "Useful commands:"
    echo "  - nvm list                    # List installed Node.js versions"
    echo "  - nvm install <version>       # Install a specific Node.js version"
    echo "  - nvm use <version>           # Switch to a specific Node.js version"
    echo "  - nvm alias default <version> # Set default Node.js version"
    echo "  - node --version              # Check current Node.js version"
    echo "  - npm --version               # Check npm version"
    echo ""
    log "Note: If NVM is not available in your current session, start a new terminal or run:"
    echo "  source ~/.bashrc  # or source ~/.zshrc"
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
        
        # Check if Node.js actually works (not just installed)
        local node_works=0
        if verify_node_works; then
            node_works=1
            log_success "Node.js $NODE_VERSION is installed and working"
        else
            local node_error
            node_error=$(node --version 2>&1 || echo "")
            if echo "$node_error" | grep -q "GLIBCXX"; then
                log_error "Node.js $NODE_VERSION is installed but cannot run due to GLIBCXX library issue"
                log "Attempting to fix the issue..."
                
                local fix_attempted=1
                local fix_succeeded=0
                
                # Try updating libraries first
                if try_update_libstdcxx; then
                    sleep 2  # Give system time to update libraries
                    # Re-source nvm and try again
                    source_nvm
                    nvm use "$NODE_VERSION" &>/dev/null || true
                    if verify_node_works; then
                        log_success "Node.js now works after library update!"
                        node_works=1
                        fix_succeeded=1
                    else
                        log "Library update didn't help, trying to rebuild from source..."
                    fi
                fi
                
                # If library update didn't work, rebuild from source
                if [ $node_works -eq 0 ]; then
                    # Need to rebuild from source
                    if ! command -v make &>/dev/null || ! command -v g++ &>/dev/null; then
                        log "Installing build tools..."
                        if command -v apt-get &>/dev/null; then
                            if sudo apt-get update -qq 2>&1 | grep -v "tput: unknown terminal" | grep -v "manpath:" && \
                               sudo apt-get install -y build-essential python3 2>&1 | grep -v "tput: unknown terminal" | grep -v "manpath:"; then
                                log_success "Build tools installed"
                            else
                                log_error "Failed to install build tools"
                                error_exit "Cannot rebuild Node.js without build tools. Please install manually: sudo apt-get install build-essential python3"
                            fi
                        else
                            error_exit "Cannot install build tools automatically. Please install build-essential and python3 manually."
                        fi
                    fi
                    
                    log "Removing broken binary installation..."
                    nvm uninstall "$NODE_VERSION" 2>&1 | grep -v "tput: unknown terminal" | grep -v "manpath:" || true
                    
                    log "Building Node.js $NODE_VERSION from source (this may take 10-30 minutes)..."
                    if nvm install -s "$NODE_VERSION" 2>&1 | grep -v "tput: unknown terminal" | grep -v "manpath:"; then
                        # Re-source and verify
                        source_nvm
                        nvm use "$NODE_VERSION" &>/dev/null || true
                        if verify_node_works; then
                            log_success "Node.js rebuilt from source and now works!"
                            node_works=1
                            fix_succeeded=1
                        else
                            log_error "Node.js rebuilt but still cannot run"
                            local rebuild_error
                            rebuild_error=$(node --version 2>&1 || echo "")
                            log_error "Error: $rebuild_error"
                        fi
                    else
                        log_error "Failed to rebuild Node.js from source"
                    fi
                fi
                
                # If we tried to fix but it still doesn't work, exit with error
                if [ $node_works -eq 0 ]; then
                    error_exit "Node.js $NODE_VERSION is installed but cannot run due to GLIBCXX library issue. Automatic fix attempts failed. Please update system libraries manually: sudo apt-get update && sudo apt-get upgrade && sudo apt-get install libstdc++6"
                fi
            else
                log_warning "Node.js is installed but verification failed: $node_error"
                # Don't exit here, let verify_installation handle it
            fi
        fi
    else
        log "Node.js $NODE_VERSION is not installed. Installing..."
        install_node
    fi
    
    # Verify installation
    verify_installation
    
    # Configure NVM in shell profiles
    configure_nvm_in_shell
    
    # Show post-installation instructions
    show_post_install_instructions
    
    log_success "Setup script completed successfully!"
}

# Run main function
main "$@"

