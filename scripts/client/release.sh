#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common.sh
source "${SCRIPT_DIR}/../common.sh"

require_command flutter "Install the Flutter SDK and retry."
require_command dart "Install the Dart SDK via Flutter and retry."
require_command cargo "Install Rust/Cargo and retry."
require_command rustup "Install rustup and retry."

log "Enabling Flutter Windows desktop support"
enable_flutter_windows
ensure_windows_device_available

log "Fetching Flutter dependencies"
(
    cd "${PROJECT_ROOT}/client/flutter"
    flutter pub get
)

log "Running Rust checks for the client workspace"
(
    cd "${PROJECT_ROOT}/client/rust"
    cargo fmt --all --check
    cargo clippy --workspace --all-targets -- -D warnings
    cargo test --workspace
)

log "Building the Rust bridge library used by the desktop FRB loader"
(
    cd "${PROJECT_ROOT}/client/rust"
    cargo build --manifest-path crates/mobile-bridge/Cargo.toml --release
)

log "Running Rust checks for the shared crate"
(
    cd "${PROJECT_ROOT}/shared/rust/shared"
    cargo fmt --check
    cargo clippy --all-targets -- -D warnings
    cargo test
)

log "Running Flutter analysis and tests"
(
    cd "${PROJECT_ROOT}/client/flutter"
    flutter analyze
    flutter test
)

log "Building the Windows release bundle"
(
    cd "${PROJECT_ROOT}/client/flutter"
    flutter build windows --release
)

log "Launching the Flutter Windows app in release mode"
cd "${PROJECT_ROOT}/client/flutter"
exec flutter run -d windows --release
