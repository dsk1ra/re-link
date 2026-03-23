# Multi-stage Dockerfile for Rust server
# Stage 1: Builder
FROM rust:alpine AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache musl-dev linux-headers

# Copy all project files to match the repo structure
# The relative paths in Cargo.toml assume this structure from the root
COPY server/rust /app/server/rust/
COPY shared/rust /app/shared/rust/

# Build the release binary
# Using the server crate workspace
RUN cd /app/server/rust && cargo build --release

# Stage 2: Runtime
FROM gcr.io/distroless/cc-debian12

# Copy the binary from the builder stage
COPY --from=builder /app/server/rust/target/release/signaling-server /app/signaling

# Expose port 8080
EXPOSE 8080

# Set the entrypoint
ENTRYPOINT ["/app/signaling"]
