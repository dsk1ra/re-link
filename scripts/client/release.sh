#!/usr/bin/env bash
#
# Build the Re:Link client in release mode with full checks.
#
# Steps: pub get → rust checks → FRB codegen → dart analyze → flutter test → flutter build
#
# Usage:
#   ./scripts/client/release.sh            # auto-detect platform
#   ./scripts/client/release.sh windows    # force platform
#   ./scripts/client/release.sh --run      # build + launch
#   ./scripts/client/release.sh linux --run
#   ./scripts/client/release.sh linux --run --reset

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common.sh
source "${SCRIPT_DIR}/../common.sh"

RUN=false
RESET=false
PLATFORM=""

for arg in "$@"; do
    case "$arg" in
        --run)   RUN=true ;;
        --reset) RESET=true ;;
        --*)     fail "Unknown option '$arg'" ;;
        *)
            if [[ -n "$PLATFORM" ]]; then
                fail "Only one platform can be specified."
            fi
            PLATFORM="$arg"
            ;;
    esac
done

PLATFORM="${PLATFORM:-$(detect_flutter_platform)}"

ensure_client_prerequisites
enable_flutter_desktop "$PLATFORM"
ensure_desktop_device_available "$PLATFORM"

log "Fetching Flutter dependencies"
(cd "${PROJECT_ROOT}/client/flutter" && flutter pub get)

run_client_rust_checks
run_shared_rust_checks
generate_frb_bindings

log "Running Flutter analysis and tests"
(
    cd "${PROJECT_ROOT}/client/flutter"
    dart analyze lib/
    flutter test
)

log "Building release bundle (${PLATFORM})"
(cd "${PROJECT_ROOT}/client/flutter" && flutter build "$PLATFORM" --release)

log "Release build complete: client/flutter/build/${PLATFORM}/"

if [[ "$RUN" == true ]]; then
    log "Launching Flutter app in release mode (${PLATFORM})"
    cd "${PROJECT_ROOT}/client/flutter"
    if [[ "$RESET" == true ]]; then
        log "Resetting saved app settings on launch"
        exec env RESET_APP_PREFS=1 flutter run -d "$PLATFORM" --release
    fi
    exec flutter run -d "$PLATFORM" --release
elif [[ "$RESET" == true ]]; then
    log "--reset applies when launching the app; use --run to reset settings from this script."
fi
