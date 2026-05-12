#!/bin/bash

# Docker and Docker Compose installation for macOS (Docker Desktop via Homebrew).
# Intended for Mac mini / macOS hosts, including non-interactive runners (CI, IDE, Node).
# No read(1) or password prompts: prepare /usr/local paths via root, or passwordless
# sudo (sudo -n), or exit with one-shot commands to run separately.
# If Docker is already installed: continues with brew (idempotent) unless you set
#   DOCKER_SETUP_MACOS_SKIP_IF_INSTALLED=1
#
# Usage: ./docker-setup-macos.sh [user1] [user2] [user3] ...
# Docker group step (see main): non-root with no args → current user ($USER).
# Root with no args → SUDO_USER if set and not root; else user "github" if it exists; else error.
# Examples:
#   ./docker-setup-macos.sh
#   sudo ./docker-setup-macos.sh openclawagent   # explicit user(s) for docker group
#   sudo ./docker-setup-macos.sh                 # adds SUDO_USER (e.g. openclawagent) when you used sudo from that account
#   DOCKER_SETUP_MACOS_SKIP_IF_INSTALLED=1 ./docker-setup-macos.sh   # group steps only if docker exists
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
    if ! command -v docker &>/dev/null; then
        return 0
    fi
    print_warning "Docker is already installed: $(docker --version)"
    if [[ "${DOCKER_SETUP_MACOS_SKIP_IF_INSTALLED:-}" == "1" ]]; then
        print_status "DOCKER_SETUP_MACOS_SKIP_IF_INSTALLED=1: skipping Homebrew Docker install."
        return 1
    fi
    print_status "Continuing with brew install --cask docker (idempotent update). Set DOCKER_SETUP_MACOS_SKIP_IF_INSTALLED=1 to skip."
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

# The docker-desktop cask links binaries into /usr/local/bin and
# /usr/local/cli-plugins/docker-compose. Homebrew runs sudo to mkdir those parents
# when they are missing or not writable by the brew user, which fails without a TTY
# (e.g. password prompt: "sudo: a terminal is required").
ensure_usr_local_paths_for_docker_cask() {
    local bu grp
    bu="$(brew_invoking_user)"
    grp="$(id -gn "$bu" 2>/dev/null || echo staff)"
    local targets=(/usr/local/bin /usr/local/cli-plugins)
    local needs_fix=false

    for d in "${targets[@]}"; do
        if [[ ! -d "$d" ]]; then
            needs_fix=true
            break
        fi
        if [[ $EUID -eq 0 ]]; then
            if ! sudo -u "$bu" test -w "$d" 2>/dev/null; then
                needs_fix=true
                break
            fi
        else
            if [[ "$(id -un)" != "$bu" ]]; then
                print_error "brew user ($bu) does not match current user ($(id -un)); cannot prepare /usr/local paths."
                exit 1
            fi
            if ! [[ -w "$d" ]]; then
                needs_fix=true
                break
            fi
        fi
    done

    if [[ "$needs_fix" != true ]]; then
        return 0
    fi

    if [[ $EUID -eq 0 ]]; then
        print_status "Creating /usr/local/bin and /usr/local/cli-plugins (owned by $bu) for Docker Desktop cask..."
        mkdir -p "${targets[@]}"
        chown -R "${bu}:${grp}" "${targets[@]}"
        return 0
    fi

    if sudo -n true 2>/dev/null; then
        print_status "Creating /usr/local paths for Docker Desktop (passwordless sudo)..."
        sudo -n mkdir -p "${targets[@]}"
        sudo -n chown -R "${bu}:${grp}" "${targets[@]}"
        return 0
    fi

    print_error "Cannot create or chown /usr/local/bin and /usr/local/cli-plugins without non-interactive sudo (this script never prompts for a password)."
    print_status "Run the following once on the host (any method that provides a TTY for sudo), then re-run:"
    echo "  sudo mkdir -p /usr/local/bin /usr/local/cli-plugins"
    echo "  sudo chown -R \"${bu}:${grp}\" /usr/local/bin /usr/local/cli-plugins"
    exit 1
}

install_docker_desktop() {
    ensure_usr_local_paths_for_docker_cask
    print_status "Installing Docker Desktop (includes Docker Compose plugin)..."
    run_brew install --cask docker
    print_success "Docker Desktop cask installed"
}

# Probe the Docker engine as the user who owns the Docker Desktop session.
# On macOS, Docker Desktop's socket (~/.docker/run/docker.sock) and CLI context
# (desktop-linux) are per-user; when the script runs via sudo, probe as that user,
# not as root. Non-interactive `sudo -u user -H` does not load .zprofile/.bash_profile, so PATH
# is often just /usr/bin:/bin:... and omits Homebrew. The GUI Terminal finds
# `docker` in /opt/homebrew/bin or /usr/local/bin; the probe must match that.
docker_macos_probe_path() {
    printf '%s' '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'
}

docker_engine_ready() {
    local bu="$1"
    local pp
    pp="$(docker_macos_probe_path)"
    if [[ $EUID -eq 0 ]]; then
        sudo -u "$bu" -H env PATH="$pp" docker info &>/dev/null
    else
        PATH="$pp:${PATH:-}" docker info &>/dev/null
    fi
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

    print_status "Waiting for Docker engine to accept connections (up to 180s) — probing as user '$bu' (PATH includes Homebrew bin dirs)..."
    local wait_time=0
    local max_wait=180
    local warned_no_cli=false
    while [[ $wait_time -lt $max_wait ]]; do
        local pp
        pp="$(docker_macos_probe_path)"
        if [[ "$warned_no_cli" = false ]] && [[ $wait_time -ge 15 ]]; then
            local ok_cli=false
            if [[ $EUID -eq 0 ]]; then
                if sudo -u "$bu" -H env PATH="$pp" command -v docker &>/dev/null; then
                    ok_cli=true
                fi
            else
                if PATH="$pp:${PATH:-}" command -v docker &>/dev/null; then
                    ok_cli=true
                fi
            fi
            if [[ "$ok_cli" = false ]]; then
                print_warning "docker CLI not found with probe PATH (Homebrew bin dirs first). A GUI Terminal may still find docker via your shell profile."
            fi
            warned_no_cli=true
        fi
        if docker_engine_ready "$bu"; then
            print_success "Docker engine is running (as user '$bu')"
            return 0
        fi
        if [[ $((wait_time % 15)) -eq 0 ]] && [[ $wait_time -gt 0 ]]; then
            print_status "Still waiting for Docker... ($((max_wait - wait_time))s left). On SSH-only hosts you may need a logged-in GUI session once to accept Docker Desktop terms."
        fi
        sleep 3
        wait_time=$((wait_time + 3))
    done
    print_warning "Docker did not become ready within ${max_wait}s (probing as user '$bu')."
    print_status "Sanity-check the daemon manually (same PATH as this script's probe):"
    echo "  sudo -u $bu -H env PATH=\"$(docker_macos_probe_path)\" docker info"
    print_status "If Docker Desktop is running in the GUI but root still cannot reach it, enable"
    print_status "  Docker Desktop → Settings → Advanced → 'Allow the default Docker socket to be used'"
    print_status "so /var/run/docker.sock is symlinked for system-wide access."
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
            if [[ -n "${SUDO_USER:-}" ]] && [[ "$SUDO_USER" != root ]] && id "$SUDO_USER" &>/dev/null; then
                print_status "No usernames given: adding invoking user '$SUDO_USER' to docker group (from SUDO_USER)."
                users=("$SUDO_USER")
            elif id "github" &>/dev/null; then
                print_status "No SUDO_USER fallback: detected user 'github', adding to docker group (GitHub Actions runner)."
                users=("github")
            else
                print_error "When running as root, pass at least one username, or run via sudo from a normal account so SUDO_USER is set."
                print_status "Usage: $0 [user1] [user2] [user3] ..."
                print_status "Example: $0 openclawagent"
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
