#!/bin/bash
#
# End-to-end pairing test runner for the Rimote Mac agent.
#
# Builds the app, launches it with an isolated test environment (fixed pairing
# PIN, throwaway home directory so no real pairing or login item is touched),
# waits for the WebSocket port, then drives the real binary through the full
# PROTOCOL.md handshake via Tests/E2EPairingTest.swift.
#
# Usage:  Tests/run-e2e.sh
# Exit:   0 = all checks passed, non-zero = build or a check failed.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

TEST_PIN="1357"
PORT="8765"
DERIVED="$REPO/DerivedData"            # gitignored
TEST_HOME="$(mktemp -d)"               # isolates Application Support + login item
AGENT_PID=""

cleanup() {
  [ -n "$AGENT_PID" ] && kill "$AGENT_PID" 2>/dev/null || true
  [ -n "$AGENT_PID" ] && wait "$AGENT_PID" 2>/dev/null || true
  rm -rf "$TEST_HOME"
}
trap cleanup EXIT

echo "==> Building Rimote.app"
xcodebuild -project Rimote.xcodeproj -scheme Rimote -configuration Debug \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build >/dev/null

APP="$DERIVED/Build/Products/Debug/Rimote.app/Contents/MacOS/Rimote"
[ -x "$APP" ] || { echo "build did not produce $APP"; exit 1; }

echo "==> Launching agent (isolated home: $TEST_HOME)"
env RIMOTE_TEST_MODE=1 RIMOTE_TEST_PIN="$TEST_PIN" \
    HOME="$TEST_HOME" CFFIXED_USER_HOME="$TEST_HOME" \
    "$APP" >/dev/null 2>&1 &
AGENT_PID=$!

echo "==> Waiting for ws://127.0.0.1:$PORT"
for _ in $(seq 1 40); do
  if nc -z 127.0.0.1 "$PORT" 2>/dev/null; then break; fi
  if ! kill -0 "$AGENT_PID" 2>/dev/null; then echo "agent exited early"; exit 1; fi
  sleep 0.25
done
nc -z 127.0.0.1 "$PORT" 2>/dev/null || { echo "port $PORT never opened"; exit 1; }

echo "==> Running pairing test"
RIMOTE_TEST_PIN="$TEST_PIN" RIMOTE_TEST_HOST="127.0.0.1:$PORT" \
  swift "$REPO/Tests/E2EPairingTest.swift"
