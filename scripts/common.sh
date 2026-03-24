#!/usr/bin/env bash

set -euo pipefail

SCRIPTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPTS_DIR}/.." && pwd)"

log() {
    printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

require_command() {
    local cmd="${1:?missing command name}"
    local help_text="${2:-Install it and retry.}"

    if ! command -v "$cmd" >/dev/null 2>&1; then
        fail "Required command '$cmd' was not found. $help_text"
    fi
}

compose() {
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        docker compose -f "${PROJECT_ROOT}/docker-compose.yml" "$@"
        return
    fi

    if command -v docker-compose >/dev/null 2>&1; then
        docker-compose -f "${PROJECT_ROOT}/docker-compose.yml" "$@"
        return
    fi

    fail "Docker Compose is required. Install Docker Desktop or docker-compose and retry."
}

enable_flutter_windows() {
    flutter config --enable-windows-desktop >/dev/null
}

ensure_windows_device_available() {
    if ! flutter devices | grep -qi 'windows'; then
        fail "Flutter Windows desktop support is unavailable. Install the Windows desktop toolchain and rerun 'flutter doctor -v'."
    fi
}

wait_for_http_ok() {
    local url="${1:?missing url}"
    local name="${2:-service}"
    local attempts="${3:-30}"
    local delay_secs="${4:-2}"

    for ((i = 1; i <= attempts; i++)); do
        if curl --silent --show-error --fail "$url" >/dev/null 2>&1; then
            return 0
        fi
        sleep "$delay_secs"
    done

    fail "${name} did not become ready at ${url}"
}

wait_for_http_listener() {
    local url="${1:?missing url}"
    local name="${2:-service}"
    local attempts="${3:-30}"
    local delay_secs="${4:-2}"

    for ((i = 1; i <= attempts; i++)); do
        local status
        status="$(curl --silent --output /dev/null --write-out '%{http_code}' "$url" || true)"
        if [[ -n "$status" && "$status" != "000" ]]; then
            return 0
        fi
        sleep "$delay_secs"
    done

    fail "${name} did not start listening at ${url}"
}

wait_for_redis_container() {
    local attempts="${1:-30}"
    local delay_secs="${2:-2}"

    for ((i = 1; i <= attempts; i++)); do
        if compose exec -T redis redis-cli ping >/dev/null 2>&1; then
            return 0
        fi
        sleep "$delay_secs"
    done

    fail "Redis did not become ready inside Docker."
}

ensure_server_prerequisites() {
    require_command cargo "Install Rust/Cargo and retry."
    require_command rustup "Install rustup and retry."
    require_command docker "Install Docker Desktop and retry."
    require_command cloudflared "Install the Cloudflare Tunnel CLI and retry."
    require_command curl "Install curl and retry."
}

start_local_infra() {
    log "Starting Redis"
    compose up -d redis
    wait_for_redis_container

    log "Starting Caddy"
    DOMAIN=localhost UPSTREAM=http://host.docker.internal:8080 compose up -d --no-deps caddy
    wait_for_http_listener "http://127.0.0.1" "Caddy"
}

start_cloudflare_quick_tunnel() {
    local local_url="${1:?missing local url}"

    CLOUDFLARED_LOG="$(mktemp "${TMPDIR:-/tmp}/re-link-cloudflared.XXXXXX.log")"
    cloudflared tunnel --no-autoupdate --url "$local_url" --no-tls-verify --http-host-header localhost >"$CLOUDFLARED_LOG" 2>&1 &
    CLOUDFLARED_PID=$!

    for ((i = 1; i <= 60; i++)); do
        if ! kill -0 "$CLOUDFLARED_PID" >/dev/null 2>&1; then
            cat "$CLOUDFLARED_LOG" >&2 || true
            fail "cloudflared exited before publishing a tunnel URL."
        fi

        CLOUDFLARE_TUNNEL_URL="$(grep -Eo 'https://[-a-z0-9.]+\.trycloudflare\.com' "$CLOUDFLARED_LOG" | tail -n 1 || true)"
        if [[ -n "${CLOUDFLARE_TUNNEL_URL:-}" ]]; then
            export CLOUDFLARE_TUNNEL_URL
            return 0
        fi

        sleep 2
    done

    cat "$CLOUDFLARED_LOG" >&2 || true
    fail "Timed out waiting for Cloudflare quick tunnel URL."
}

cleanup_cloudflare_quick_tunnel() {
    if [[ -n "${CLOUDFLARED_PID:-}" ]] && kill -0 "$CLOUDFLARED_PID" >/dev/null 2>&1; then
        kill "$CLOUDFLARED_PID" >/dev/null 2>&1 || true
        wait "$CLOUDFLARED_PID" >/dev/null 2>&1 || true
    fi

    if [[ -n "${CLOUDFLARED_LOG:-}" && -f "${CLOUDFLARED_LOG:-}" ]]; then
        rm -f "$CLOUDFLARED_LOG"
    fi
}

resolve_public_signaling_url() {
    if [[ -n "${SIGNALING_PUBLIC_URL:-}" ]]; then
        RESOLVED_SIGNALING_PUBLIC_URL="$SIGNALING_PUBLIC_URL"
        return 0
    fi

    if [[ -n "${CLOUDFLARE_TUNNEL_URL:-}" ]]; then
        RESOLVED_SIGNALING_PUBLIC_URL="$CLOUDFLARE_TUNNEL_URL"
        return 0
    fi

    log "Starting Cloudflare quick tunnel"
    start_cloudflare_quick_tunnel "https://localhost:443"
    RESOLVED_SIGNALING_PUBLIC_URL="$CLOUDFLARE_TUNNEL_URL"
}
