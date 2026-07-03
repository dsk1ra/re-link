#!/usr/bin/env bash
#
# Build and run the Re:Link client in debug mode.
#
# Steps: pub get → FRB codegen → flutter run (debug)
#
# Usage:
#   ./scripts/client/develop.sh                 # auto-detect platform
#   ./scripts/client/develop.sh linux           # force platform
#   ./scripts/client/develop.sh linux --reset   # reset saved app settings on launch

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common.sh
source "${SCRIPT_DIR}/../common.sh"

ensure_client_prerequisites

RESET=false
PLATFORM=""

for arg in "$@"; do
    case "$arg" in
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
enable_flutter_desktop "$PLATFORM"
ensure_desktop_device_available "$PLATFORM"

log "Fetching Flutter dependencies"
(cd "${PROJECT_ROOT}/client/flutter" && flutter pub get)

generate_frb_bindings

log "Launching Flutter app in debug mode (${PLATFORM})"
cd "${PROJECT_ROOT}/client/flutter"
if [[ "$RESET" == true ]]; then
    log "Resetting saved app settings on launch"
    exec env RESET_APP_PREFS=1 flutter run -d "$PLATFORM"
fi
exec flutter run -d "$PLATFORM"
