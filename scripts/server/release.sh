#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common.sh
source "${SCRIPT_DIR}/../common.sh"

ensure_server_prerequisites
trap cleanup_cloudflare_quick_tunnel EXIT INT TERM
start_local_infra
resolve_public_signaling_url

export SIGNALING_ADDR="${SIGNALING_ADDR:-0.0.0.0}"
export SIGNALING_PORT="${SIGNALING_PORT:-8080}"
export SIGNALING_PUBLIC_URL="$RESOLVED_SIGNALING_PUBLIC_URL"
export SIGNALING_REDIS_URL="${SIGNALING_REDIS_URL:-redis://127.0.0.1:6379/0}"
export SIGNALING_REDIS_REQUIRE_TLS="${SIGNALING_REDIS_REQUIRE_TLS:-false}"
export SIGNALING_REDIS_KEY_PREFIX="${SIGNALING_REDIS_KEY_PREFIX:-sig}"
export SIGNALING_SESSION_TTL_SECS="${SIGNALING_SESSION_TTL_SECS:-300}"
export SIGNALING_MAILBOX_TTL_SECS="${SIGNALING_MAILBOX_TTL_SECS:-300}"
export SIGNALING_HEARTBEAT_SECS="${SIGNALING_HEARTBEAT_SECS:-30}"
export SIGNALING_JOINED_FLAG_TTL_SECS="${SIGNALING_JOINED_FLAG_TTL_SECS:-60}"
export SIGNALING_RENDEZVOUS_TTL_SECS="${SIGNALING_RENDEZVOUS_TTL_SECS:-30}"
export SIGNALING_REDIS_ENCRYPT="${SIGNALING_REDIS_ENCRYPT:-false}"
export RUST_LOG="${RUST_LOG:-info}"

log "Signaling public URL: ${SIGNALING_PUBLIC_URL}"
log "Running the signaling server in release mode"

cd "${PROJECT_ROOT}/server/rust"
cargo run --release --manifest-path crates/signaling/Cargo.toml
