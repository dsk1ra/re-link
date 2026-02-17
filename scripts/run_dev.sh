#!/bin/bash

# Get the absolute path of the project root
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ -z "$PROJECT_ROOT" ]; then
    echo "Error: Could not determine PROJECT_ROOT."
    exit 1
fi

cd "$PROJECT_ROOT"

# 1. Start Redis
echo "Checking Redis..."
if ! pgrep redis-server > /dev/null; then
    echo "Starting Redis..."
    redis-server --daemonize yes
fi

# 2. Start local Signaling Server
echo "Checking Signaling Server..."
if [ ! -f "rust/target/debug/signaling-server" ]; then
    echo "Building Signaling Server..."
    cd rust && cargo build -p signaling-server && cd "$PROJECT_ROOT"
fi

if pgrep -f "target/debug/signaling-server" > /dev/null; then
    echo "Signaling Server already running."
else
    echo "Starting Signaling Server..."
    cd rust
    SIGNALING_REDIS_URL=redis://127.0.0.1/ \
    SIGNALING_REDIS_REQUIRE_TLS=false \
    SIGNALING_ADDR=0.0.0.0 \
    SIGNALING_MAILBOX_TTL_SECS=300 \
    nohup ./target/debug/signaling-server > "../server.log" 2>&1 &
    cd "$PROJECT_ROOT"
fi

# 3. Start/Get Tunnel URL
echo "Checking Tunnel..."

if ! pgrep -f "cloudflared tunnel --url http://localhost:8080" > /dev/null; then
    echo "Starting Cloudflare Tunnel..."
    # Clear old log to avoid picking up stale URLs
    > "tunnel.log"
    nohup cloudflared tunnel --url http://localhost:8080 > "tunnel.log" 2>&1 &
    sleep 10
fi

# Extract Cloudflare URL
TUNNEL_URL=$(grep -o 'https://[-a-z0-9.]*\.trycloudflare\.com' "tunnel.log" | tail -n 1)

if [ -z "$TUNNEL_URL" ]; then
    echo "Error: Could not retrieve Tunnel URL from tunnel.log"
    echo "Check tunnel.log content:"
    cat tunnel.log
    exit 1
fi

echo "------------------------------------------------"
echo "Environment: DEVELOPMENT"
echo "Tunnel URL:  $TUNNEL_URL"
echo "------------------------------------------------"

# 4. Update dev.json automatically (in client/config)
mkdir -p client/config
echo "{\"SIGNALING_URL\": \"$TUNNEL_URL\"}" > client/config/dev.json

# 5. Launch Flutter
echo "Launching Flutter App..."
cd client
flutter run -d linux --dart-define-from-file=config/dev.json
