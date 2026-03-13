## Project Structure

This project is organized as a monorepo:

- **`client/flutter/`**: The Flutter application (frontend + UX).
- **`client/rust/`**: Client Rust workspace (`crates/mobile-bridge`, `crates/client-core`) used by Flutter/FRB.
- **`server/rust/`**: Server Rust workspace (`crates/signaling`).
- **`shared/rust/`**: Shared Rust crate (`shared`) for protocol + crypto.
- **`scripts/`**: DevOps, build, and setup scripts.
- **`docs/`**: Project documentation, architecture diagrams, and reports.

## Getting Started

### Prerequisites
- Flutter SDK
- Rust (Cargo)
- Docker (optional, for server)

### Running the Client
```bash
cd client/flutter
flutter run
```

### Building Client Rust Backend (FRB)
```bash
cargo build --manifest-path client/rust/crates/mobile-bridge/Cargo.toml
```

### Running the Server (Local)
```bash
cargo run --manifest-path server/rust/crates/signaling/Cargo.toml
```