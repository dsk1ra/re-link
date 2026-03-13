FROM rust:slim-bookworm AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y pkg-config libssl-dev && rm -rf /var/lib/apt/lists/*

COPY rust-server/Cargo.toml rust-server/Cargo.toml
COPY rust-server/crates/signaling/Cargo.toml rust-server/crates/signaling/Cargo.toml
COPY rust-shared/shared/Cargo.toml rust-shared/shared/Cargo.toml

COPY rust-server/crates/signaling rust-server/crates/signaling
COPY rust-shared/shared rust-shared/shared

WORKDIR /app/rust-server
RUN cargo build --release --manifest-path crates/signaling/Cargo.toml

FROM debian:bookworm-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/rust-server/target/release/signaling-server /app/signaling-server

ENV SIGNALING_ADDR=0.0.0.0
ENV SIGNALING_PORT=8080

EXPOSE 8080

CMD ["/app/signaling-server"]
