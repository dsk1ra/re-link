#!/usr/bin/env bash
#
# Start all Re:Link services via Docker Compose with a Cloudflare quick tunnel.
# The tunnel gives the stack a public HTTPS URL without any DNS or cert setup.
#
# Usage:
#   ./scripts/server/tunnel.sh              # foreground (Ctrl+C stops everything)
#   ./scripts/server/tunnel.sh -d           # detached   (show URL, return prompt)
#
# To stop a detached stack:
#   docker compose down

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common.sh
source "${SCRIPT_DIR}/../common.sh"

require_command cloudflared "Install the Cloudflare Tunnel CLI and retry."
require_command docker "Install Docker Desktop and retry."
require_command curl "Install curl and retry."

cleanup() {
    cleanup_cloudflare_quick_tunnel
    cleanup_tunnel_url_file
}
trap cleanup EXIT INT TERM

log "Starting Caddy + Redis..."
compose up -d redis caddy
wait_for_redis_container
wait_for_http_listener "http://127.0.0.1" "Caddy"

resolve_public_signaling_url
display_public_url "$RESOLVED_SIGNALING_PUBLIC_URL"

log "Starting signaling server..."
export PUBLIC_BASE_URL="$RESOLVED_SIGNALING_PUBLIC_URL"
compose up "$@" --no-deps server
