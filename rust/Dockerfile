# Builder stage
FROM rust:slim-bookworm as builder

WORKDIR /app

# Install build dependencies (needed for some crates like openSSL if not pure rust)
RUN apt-get update && apt-get install -y pkg-config libssl-dev && rm -rf /var/lib/apt/lists/*

# Copy manifest files to cache dependencies
COPY Cargo.toml Cargo.lock ./

# Create a dummy src directory to build dependencies
# We need to mimic the library/binary structure to cache effectively.
# Since it's a mixed crate, we'll create a dummy lib.rs and bin file.
RUN mkdir -p src/bin && \
    echo "fn main() {}" > src/bin/signaling_server.rs && \
    echo "" > src/lib.rs && \
    echo "" > src/frb_generated.rs

# Build dependencies only
RUN cargo build --release --bin signaling_server || true

# Now copy the actual source code
COPY src ./src

# Build the actual application
# We need to touch the main file to force a rebuild of the binary
# Also touch lib.rs to ensure the library part of the crate is rebuilt
RUN touch src/lib.rs src/bin/signaling_server.rs && cargo build --release --bin signaling_server

# Runtime stage
FROM debian:bookworm-slim

WORKDIR /app

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

# Copy the binary from the builder stage
COPY --from=builder /app/target/release/signaling_server /app/signaling_server

# Set default environment variables
ENV SIGNALING_ADDR=0.0.0.0
ENV SIGNALING_PORT=8080

# Expose the port
EXPOSE 8080

# Run the server
CMD ["/app/signaling_server"]
