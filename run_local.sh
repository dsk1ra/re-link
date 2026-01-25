#!/bin/bash
set -e

# 1. Start Redis (if not running)
if ! pgrep redis-server > /dev/null; then
    echo "Starting Redis server..."
    redis-server --daemonize yes
else
    echo "Redis server is already running."
fi

# 2. Start Signaling Server (in background)
echo "Starting local Signaling Server..."
cd rust
# We use nohup to keep it running, and redirect output
# We override the Redis URL to point to localhost instead of AWS
export SIGNALING_REDIS_URL=redis://127.0.0.1/
export SIGNALING_REDIS_REQUIRE_TLS=false
export SIGNALING_ADDR=0.0.0.0

nohup cargo run --bin signaling_server > ../server.log 2>&1 &
SERVER_PID=$!
cd ..

echo "Signaling Server running (PID: $SERVER_PID). Logs in server.log"

# 3. Run Flutter App
# Point the app to the local server (10.0.2.2 is the emulator's alias for host loopback)
echo "Launching Flutter App..."
flutter run -d emulator-5554 --dart-define=SIGNALING_URL=http://10.0.2.2:8080

# 4. Cleanup on exit
echo "Stopping Signaling Server..."
kill $SERVER_PID
