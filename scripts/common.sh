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

detect_flutter_platform() {
    case "$(uname -s)" in
        Linux*)                   echo "linux"   ;;
        Darwin*)                  echo "macos"   ;;
        MINGW*|MSYS*|CYGWIN*)     echo "windows" ;;
        *)  fail "Unsupported platform: $(uname -s)" ;;
    esac
}

enable_flutter_desktop() {
    local platform
    platform="${1:-$(detect_flutter_platform)}"
    flutter config --enable-"${platform}"-desktop >/dev/null 2>&1 || true
}

ensure_desktop_device_available() {
    local platform
    local devices_output

    platform="${1:-$(detect_flutter_platform)}"
    if ! devices_output="$(flutter devices 2>&1)"; then
        printf '%s\n' "$devices_output" >&2
        fail "Unable to list Flutter devices. Run 'flutter doctor -v' and resolve the reported issues."
    fi

    if ! grep -qi "$platform" <<<"$devices_output"; then
        printf '%s\n' "$devices_output" >&2
        fail "Flutter ${platform} desktop support is unavailable. Run 'flutter doctor -v' and install the required toolchain."
    fi
}

ensure_client_prerequisites() {
    require_command flutter "Install the Flutter SDK and retry."
    require_command dart "Install the Dart SDK via Flutter and retry."
    require_command cargo "Install Rust/Cargo and retry."
    require_command rustup "Install rustup and retry."
    require_command flutter_rust_bridge_codegen "Run 'cargo install flutter_rust_bridge_codegen' and retry."
}

generate_frb_bindings() {
    log "Generating flutter_rust_bridge bindings"
    (cd "${PROJECT_ROOT}/client/flutter" && flutter_rust_bridge_codegen generate)
}

run_client_rust_checks() {
    log "Running Rust checks for the client workspace"
    (
        cd "${PROJECT_ROOT}/client/rust"
        cargo fmt --all --check
        cargo clippy --workspace --all-targets -- -D warnings
        cargo test --workspace
    )
}

run_shared_rust_checks() {
    log "Running Rust checks for the shared crate"
    (
        cd "${PROJECT_ROOT}/shared/rust"
        cargo fmt --check
        cargo clippy --all-targets -- -D warnings
        cargo test
    )
}

run_server_rust_checks() {
    log "Running Rust checks for the server workspace"
    (
        cd "${PROJECT_ROOT}/server/rust"
        cargo fmt --all --check
        cargo clippy --workspace --all-targets -- -D warnings
        cargo test --workspace
    )
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

try_copy_to_clipboard() {
    local text="$1"
    if command -v wl-copy >/dev/null 2>&1 && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        printf '%s' "$text" | wl-copy 2>/dev/null && return 0
    fi
    if command -v xclip >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
        printf '%s' "$text" | xclip -selection clipboard 2>/dev/null && return 0
    fi
    if command -v xsel >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
        printf '%s' "$text" | xsel --clipboard --input 2>/dev/null && return 0
    fi
    if command -v pbcopy >/dev/null 2>&1; then
        printf '%s' "$text" | pbcopy 2>/dev/null && return 0
    fi
    return 1
}

display_public_url() {
    local url="${1:?missing url}"
    local url_file="${PROJECT_ROOT}/.tunnel-url"

    printf '%s' "$url" > "$url_file"

    local clipboard_note=""
    if try_copy_to_clipboard "$url"; then
        clipboard_note="Copied to clipboard  |  "
    fi
    local footer="${clipboard_note}Saved to .tunnel-url"

    local title="Re:Link Public URL"
    local inner=${#url}
    (( ${#footer} > inner )) && inner=${#footer}
    (( ${#title} > inner )) && inner=${#title}
    (( inner < 40 )) && inner=40

    local rule=""
    for (( i = 0; i < inner + 4; i++ )); do rule+="─"; done

    _pad() {
        local t="$1" gap=$(( inner - ${#1} ))
        printf '│  %s%*s  │\n' "$t" "$gap" ""
    }
    _blank() { printf '│  %*s  │\n' "$inner" ""; }

    printf '\n'
    printf '┌%s┐\n' "$rule"
    _blank
    _pad "$title"
    _blank
    _pad "$url"
    _blank
    _pad "$footer"
    _blank
    printf '└%s┘\n' "$rule"
    printf '\n'
}

cleanup_tunnel_url_file() {
    rm -f "${PROJECT_ROOT}/.tunnel-url" 2>/dev/null || true
}
