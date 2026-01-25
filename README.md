## Project Structure

This project is organized as a monorepo:

- **`client/`**: The Flutter Application (Frontend & Client Logic).
- **`rust/`**: The Rust Workspace containing:
    - Signaling Server
    - Core Application Logic (shared with client via FRB)
- **`scripts/`**: DevOps, build, and setup scripts.
- **`docs/`**: Project documentation, architecture diagrams, and reports.

## Getting Started

### Prerequisites
- Flutter SDK
- Rust (Cargo)
- Docker (optional, for server)

### Running the Client
```bash
cd client
flutter run
```

### Running the Server (Local)
```bash
cd rust
cargo run --bin signaling_server
```
