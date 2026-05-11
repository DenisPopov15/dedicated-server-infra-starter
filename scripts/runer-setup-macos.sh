#!/bin/bash

# GitHub Actions Runner setup for macOS (per-user LaunchAgent via runner svc.sh; must not run svc.sh as root).
# Same usage and flow as runer-setup.sh (Linux), adapted for Darwin.
#
# Usage:
#   Local:  ./runer-setup-macos.sh <orgName> <token> <labels> [runnerUser]
#   Remote: curl -s <script-url> | sudo bash -s <orgName> <token> <labels> [runnerUser]
#
# Examples:
#   sudo ./runer-setup-macos.sh my-org ghp_xxxxxxxxxxxx deployment,development
#   sudo ./runer-setup-macos.sh my-org ghp_xxxxxxxxxxxx deployment,development alice
#   curl -s https://example.com/runer-setup-macos.sh | sudo bash -s -- my-org ghp_xxxxxxxxxxxx deployment,development
#   curl -s https://example.com/runer-setup-macos.sh | sudo bash -s -- my-org TOKEN labels alice
#
# runnerUser defaults to github (same default as runer-setup.sh). On macOS use the account that has a
# GUI login if you rely on the stock LaunchAgent + svc.sh start.
#
# Prerequisites:
#   - Must run as root (use sudo)
#   - Host must have internet access
#   - Token must allow runner registration (org/repo/enterprise per GitHub docs)

set -euo pipefail

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >&2
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

if [ "$(uname -s)" != "Darwin" ]; then
    error_exit "This script is for macOS only. Detected: $(uname -s)"
fi

if [ $# -ne 3 ] && [ $# -ne 4 ]; then
    error_exit "Usage: $0 <orgName> <token> <labels> [runnerUser]
    Example: $0 my-org ghp_xxxxxxxxxxxx deployment,development
    Example: $0 my-org ghp_xxxxxxxxxxxx deployment,development alice"
fi

ORG_NAME="$1"
TOKEN="$2"
LABELS="$3"
RUNNER_USER="${4:-github}"
RUNNER_VERSION="2.321.0"
RUNNER_HOME="/Users/${RUNNER_USER}"

ARCH=$(uname -m)
case ${ARCH} in
    x86_64)
        RUNNER_OS_ARCH="osx-x64"
        ;;
    arm64)
        RUNNER_OS_ARCH="osx-arm64"
        ;;
    *)
        error_exit "Unsupported architecture for macOS runner: ${ARCH}"
        ;;
esac

RUNNER_FILE="actions-runner-${RUNNER_OS_ARCH}-${RUNNER_VERSION}.tar.gz"
RUNNER_DOWNLOAD_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${RUNNER_FILE}"

log "Starting GitHub Actions Runner setup (macOS)..."
log "Organization: ${ORG_NAME}"
log "Labels: ${LABELS}"
log "Runner user: ${RUNNER_USER} (4th arg [runnerUser]; default: github)"
log "Detected architecture: ${ARCH} (using ${RUNNER_OS_ARCH})"

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    error_exit "This script must be run as root (e.g. sudo ./runer-setup-macos.sh ...)"
fi

create_runner_user_macos() {
    if id "${RUNNER_USER}" &>/dev/null; then
        log "User ${RUNNER_USER} already exists"
        return 0
    fi

    local pw
    pw="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32)"
    if [ ${#pw} -lt 12 ]; then
        pw="${pw}Aa1Bb2Cc3"
    fi

    log "Creating runner user: ${RUNNER_USER} (home ${RUNNER_HOME})"
    if ! sysadminctl -addUser "${RUNNER_USER}" \
        -fullName "GitHub Actions Runner" \
        -password "${pw}" \
        -hint "" \
        -shell /bin/bash \
        -home "${RUNNER_HOME}" 2>&1; then
        error_exit "sysadminctl failed to create user ${RUNNER_USER}. Ensure this host allows local user creation (not a directory-bound user conflict)."
    fi

    log "User ${RUNNER_USER} created successfully (password is random and not logged)"
}

# sysadminctl only records NFSHomeDirectory; it often does not create the folder ("assigned (not created!)").
ensure_runner_home() {
    if [ ! -d "${RUNNER_HOME}" ]; then
        log "Creating home directory ${RUNNER_HOME}"
        mkdir -p "${RUNNER_HOME}"
    fi
    chown "${RUNNER_USER}:staff" "${RUNNER_HOME}"
    chmod 755 "${RUNNER_HOME}"
}

create_runner_user_macos
ensure_runner_home

log "Setting up runner in ${RUNNER_HOME}/actions-runner"
sudo -u "${RUNNER_USER}" bash << EOF
set -euo pipefail
cd "${RUNNER_HOME}"

if [ ! -d "actions-runner" ]; then
    mkdir actions-runner
fi
cd actions-runner

if [ ! -f "${RUNNER_FILE}" ]; then
    echo "Downloading GitHub Actions Runner v${RUNNER_VERSION} for ${RUNNER_OS_ARCH}..."
    curl -fsSL -o "${RUNNER_FILE}" -L "${RUNNER_DOWNLOAD_URL}" || exit 1
    echo "Download completed successfully"
else
    echo "Runner package already exists, skipping download"
fi

if [ ! -f "config.sh" ]; then
    echo "Extracting runner..."
    tar xzf "./${RUNNER_FILE}" || exit 1
    echo "Extraction completed successfully"
else
    echo "Runner already extracted, skipping extraction"
fi

if [ -f ".runner" ]; then
    echo "Runner is already configured (.runner exists); skipping ./config.sh"
    echo "To re-register: ./config.sh remove --token <token>, then re-run with a new registration token."
else
    echo "Configuring runner..."
    ./config.sh --url https://github.com/${ORG_NAME} --token ${TOKEN} --labels ${LABELS} --unattended || exit 1
fi
EOF

if [ $? -ne 0 ]; then
    error_exit "Failed to setup runner as user ${RUNNER_USER}"
fi

# darwin.svc.sh.template: "Must not run with sudo" if uid 0 — install is under ~/Library/LaunchAgents for RUNNER_USER.
run_svc_as_runner() {
    local svc_cmd="$1"
    sudo -u "${RUNNER_USER}" -H bash -lc "cd '${RUNNER_HOME}/actions-runner' && ./svc.sh ${svc_cmd}"
}

log "Ensuring ${RUNNER_HOME}/actions-runner is owned by ${RUNNER_USER}"
chown -R "${RUNNER_USER}:staff" "${RUNNER_HOME}/actions-runner"

log "Installing runner service (LaunchAgent for user ${RUNNER_USER})..."
run_svc_as_runner install || error_exit "Failed to install runner service"

log "Starting runner service..."
run_svc_as_runner start || error_exit "Failed to start runner service"

log "GitHub Actions Runner setup completed successfully!"
log "Service status:"
run_svc_as_runner status || true
