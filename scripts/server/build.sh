#!/usr/bin/env bash
#
# Build the Re:Link signaling server.
#
# Usage:
#   ./scripts/server/build.sh              # debug build
#   ./scripts/server/build.sh --release    # release build with checks
#   ./scripts/server/build.sh --docker     # build Docker image

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common.sh
source "${SCRIPT_DIR}/../common.sh"

MODE="${1:-}"

case "$MODE" in
    --release)
        require_command cargo "Install Rust/Cargo and retry."
        run_server_rust_checks
        run_shared_rust_checks
        log "Building server (release)"
        (cd "${PROJECT_ROOT}/server/rust" && cargo build --release)
        log "Binary: server/rust/target/release/signaling-server"
        ;;
    --docker)
        require_command docker "Install Docker and retry."
        log "Building Docker image"
        compose build server
        log "Docker image built successfully"
        ;;
    *)
        require_command cargo "Install Rust/Cargo and retry."
        log "Building server (debug)"
        (cd "${PROJECT_ROOT}/server/rust" && cargo build)
        log "Binary: server/rust/target/debug/signaling-server"
        ;;
esac
