#!/bin/bash

# Docker and Docker Compose installation for macOS (Docker Desktop via Homebrew).
# Intended for interactive or SSH sessions on Mac mini / macOS hosts.
#
# Usage: ./docker-setup-macos.sh [user1] [user2] [user3] ...
# If no usernames are provided, current user will be added to the docker group
# when that step runs (see main: same conditions as docker-setup.sh for Ubuntu).
# Examples:
#   ./docker-setup-macos.sh
#   ./docker-setup-macos.sh alice bob
#   sudo ./docker-setup-macos.sh root github deploy   # uses SUDO_USER for Homebrew when needed

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# User that owns Homebrew / should run brew (never root for brew itself).
brew_invoking_user() {
    if [[ $EUID -eq 0 ]]; then
        if [[ -n "${SUDO_USER:-}" ]]; then
            printf '%s' "$SUDO_USER"
        else
            print_error "Homebrew cannot run as root. Run as a normal admin user, or use sudo from a login shell so SUDO_USER is set (e.g. ssh user@host then sudo ./docker-setup-macos.sh ...)."
            exit 1
        fi
    else
        printf '%s' "$USER"
    fi
}

run_brew() {
    local bu
    bu="$(brew_invoking_user)"
    if [[ $EUID -eq 0 ]]; then
        local brexe=""
        if [[ -x /opt/homebrew/bin/brew ]]; then
            brexe=/opt/homebrew/bin/brew
        elif [[ -x /usr/local/bin/brew ]]; then
            brexe=/usr/local/bin/brew
        else
            brexe=$(sudo -u "$bu" -H sh -c 'command -v brew' 2>/dev/null || true)
        fi
        if [[ -z "$brexe" ]]; then
            print_error "Could not locate brew for user $bu"
            exit 1
        fi
        sudo -u "$bu" -H "$brexe" "$@"
    else
        ensure_brew_in_path || true
        brew "$@"
    fi
}

ensure_brew_in_path() {
    if command -v brew &>/dev/null; then
        return 0
    fi
    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        return 0
    fi
    if [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
        return 0
    fi
    return 1
}

check_existing_docker() {
    if command -v docker &>/dev/null; then
        print_warning "Docker is already installed: $(docker --version)"
        read -p "Do you want to continue and potentially reinstall/update? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Skipping Docker installation. Will only add users to docker group if specified."
            return 1
        fi
    fi
    return 0
}

check_macos() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        print_error "This script is for macOS only. Detected: $(uname -s)"
        exit 1
    fi
    local ver
    ver="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
    print_status "Detected macOS version: $ver"
}

ensure_homebrew() {
    if ensure_brew_in_path; then
        print_success "Homebrew found: $(command -v brew)"
        return 0
    fi
    print_error "Homebrew is not installed or not in PATH for this user."
    print_status "Install from https://brew.sh — for Apple Silicon, typical PATH setup is:"
    print_status '  eval "$(/opt/homebrew/bin/brew shellenv)"'
    exit 1
}

ensure_xcode_cli_tools() {
    if xcode-select -p &>/dev/null; then
        return 0
    fi
    print_warning "Xcode Command Line Tools are not installed (required for Homebrew)."
    print_status "Attempting: xcode-select --install (may require a GUI session)"
    xcode-select --install 2>/dev/null || true
    print_error "Finish installing Command Line Tools, confirm with xcode-select -p, then re-run this script."
    exit 1
}

update_system() {
    print_status "Updating Homebrew metadata (brew update)..."
    run_brew update
    print_success "Homebrew metadata updated"
}

install_docker_desktop() {
    print_status "Installing Docker Desktop (includes Docker Compose plugin)..."
    run_brew install --cask docker
    print_success "Docker Desktop cask installed"
}

start_docker_service() {
    print_status "Starting Docker Desktop (daemon)..."
    local bu
    bu="$(brew_invoking_user)"
    if [[ $EUID -eq 0 ]]; then
        sudo -u "$bu" -H bash -c 'open -a Docker' || true
    else
        open -a Docker || true
    fi

    print_status "Waiting for Docker engine to accept connections (up to 180s)..."
    local wait_time=0
    local max_wait=180
    while [[ $wait_time -lt $max_wait ]]; do
        if docker info &>/dev/null; then
            print_success "Docker engine is running"
            return 0
        fi
        if [[ $((wait_time % 15)) -eq 0 ]] && [[ $wait_time -gt 0 ]]; then
            print_status "Still waiting for Docker... ($((max_wait - wait_time))s left). On SSH-only hosts you may need a logged-in GUI session once to accept Docker Desktop terms."
        fi
        sleep 3
        wait_time=$((wait_time + 3))
    done
    print_warning "Docker did not become ready within ${max_wait}s."
    print_status "Try: log in at the console, open Docker from Applications, accept the license, then re-run verification with: docker info"
    return 0
}

# Ensure local group 'docker' exists (Open Directory), then add users — best-effort parity with Linux;
# Docker Desktop socket permissions may still differ from Linux docker group behavior.
ensure_docker_group_exists() {
    if dseditgroup -o read docker &>/dev/null; then
        return 0
    fi
    print_status "Creating local group 'docker' for user membership (macOS)..."
    sudo dseditgroup -o create docker
}

add_users_to_docker_group() {
    local users=("$@")

    if [[ ${#users[@]} -eq 0 ]]; then
        if [[ $EUID -eq 0 ]]; then
            if id "github" &>/dev/null; then
                print_status "Detected GitHub Actions runner user 'github', adding to docker group automatically"
                users=("github")
            else
                print_error "When running as root, you must specify at least one username as an argument."
                print_status "Usage: $0 [user1] [user2] [user3] ..."
                print_status "Example: $0 alice bob github"
                exit 1
            fi
        else
            users=("$USER")
        fi
    fi

    ensure_docker_group_exists

    print_status "Adding users to docker group..."
    local added_users=()
    local failed_users=()

    for username in "${users[@]}"; do
        if id "$username" &>/dev/null; then
            print_status "Adding user '$username' to docker group..."
            if sudo dseditgroup -o edit -a "$username" -t user docker; then
                added_users+=("$username")
                print_success "User '$username' added to docker group"
            else
                failed_users+=("$username")
                print_error "Failed to add user '$username' to docker group"
            fi
        else
            print_warning "User '$username' does not exist on this system, skipping..."
            failed_users+=("$username")
        fi
    done

    if [[ ${#added_users[@]} -gt 0 ]]; then
        echo
        print_success "Successfully added ${#added_users[@]} user(s) to docker group:"
        printf '  - %s\n' "${added_users[@]}"
        print_warning "On macOS, Docker Desktop may still require a GUI login for each user or shared socket setup; re-login is recommended after group changes."

        if [[ " ${added_users[@]} " =~ " github " ]]; then
            restart_github_runner
        fi
    fi

    if [[ ${#failed_users[@]} -gt 0 ]]; then
        echo
        print_warning "Failed to add ${#failed_users[@]} user(s):"
        printf '  - %s\n' "${failed_users[@]}"
    fi
}

restart_github_runner() {
    print_status "Checking for GitHub Actions runner LaunchDaemon..."

    local found=false
    while IFS= read -r -d '' plist; do
        found=true
        local label
        label="$(/usr/libexec/PlistBuddy -c 'Print :Label' "$plist" 2>/dev/null || true)"
        [[ -z "$label" ]] && continue
        print_status "Restarting LaunchDaemon: $label"
        if sudo launchctl kickstart -k "system/${label}" 2>/dev/null; then
            print_success "Runner service kickstarted: $label"
        else
            print_warning "Could not kickstart $label; try: sudo launchctl kickstart -k system/$label"
        fi
    done < <(sudo find /Library/LaunchDaemons -maxdepth 1 -name 'com.github.actions.runner*.plist' -print0 2>/dev/null || true)

    if [[ "$found" = false ]]; then
        print_status "No com.github.actions.runner LaunchDaemon plist found under /Library/LaunchDaemons, skipping restart"
    fi
}

verify_installation() {
    print_status "Verifying Docker installation..."

    if ! command -v docker &>/dev/null; then
        print_error "docker CLI not found in PATH after install."
        return 1
    fi

    local docker_version
    docker_version=$(docker --version)
    print_success "Docker version: $docker_version"

    local compose_version
    compose_version=$(docker compose version)
    print_success "Docker Compose version: $compose_version"

    if [[ $EUID -ne 0 ]]; then
        print_status "Testing Docker with hello-world container..."
        if docker run --rm hello-world >/dev/null 2>&1; then
            print_success "Docker test completed successfully"
        else
            print_warning "Docker test failed, but installation may still be complete once the engine is fully up"
        fi
    else
        print_status "Skipping Docker test (running as root); test as a normal user: docker run hello-world"
    fi
}

show_post_install_instructions() {
    echo
    print_success "Docker and Docker Compose setup step completed!"
    echo
    print_status "Post-installation steps:"
    echo "1. Re-login or reboot if you changed group membership"
    echo "2. Test Docker: docker run hello-world"
    echo "3. Test Docker Compose: docker compose --help"
    echo
    print_status "Useful commands:"
    echo "- docker --version"
    echo "- docker compose version"
    echo "- docker ps"
    echo "- open -a Docker          # Start Docker Desktop if the engine is stopped"
    echo
}

main() {
    echo "========================================"
    echo "Docker Installation Script for macOS (Docker Desktop)"
    echo "========================================"
    echo

    check_macos
    ensure_xcode_cli_tools
    ensure_homebrew

    local skip_install=false
    if ! check_existing_docker; then
        skip_install=true
    fi

    print_status "Starting Docker installation process..."

    if [[ "$skip_install" = false ]]; then
        update_system
        install_docker_desktop
        start_docker_service
        verify_installation
    else
        print_status "Skipping Docker installation steps..."
    fi

    if [[ $# -gt 0 ]] || [[ "$skip_install" = true ]]; then
        add_users_to_docker_group "$@"
    fi

    show_post_install_instructions
    print_success "Installation script completed successfully!"
}

main "$@"
