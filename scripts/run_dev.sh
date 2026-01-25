#!/bin/bash

# Ensure we are at the project root
cd "$(dirname "$0")/.."

# 1. Start Redis
pgrep redis-server > /dev/null || redis-server --daemonize yes

# 2. Start local Signaling Server
cd rust
SIGNALING_REDIS_URL=redis://127.0.0.1/ SIGNALING_REDIS_REQUIRE_TLS=false SIGNALING_ADDR=0.0.0.0 nohup ./target/debug/signaling_server > ../server.log 2>&1 &
cd ..

# 3. Start/Get Cloudflare Tunnel URL
if ! pgrep cloudflared > /dev/null; then
    nohup cloudflared tunnel --url http://localhost:8080 > tunnel.log 2>&1 &
    sleep 5
fi
TUNNEL_URL=$(grep -o 'https://[-a-zA-Z0-9.]*\.trycloudflare\.com' tunnel.log | tail -n 1)

echo "------------------------------------------------"
echo "🚀 Environment: DEVELOPMENT"
echo "🔗 Tunnel URL:  $TUNNEL_URL"
echo "------------------------------------------------"

# 4. Update dev.json automatically (in client/config)
echo "{\"SIGNALING_URL\": \"$TUNNEL_URL\"}" > client/config/dev.json

# 5. Launch Flutter
cd client
flutter run -d linux --dart-define-from-file=config/dev.json