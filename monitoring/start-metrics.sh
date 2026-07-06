#!/bin/bash
# Convenience wrapper: starts the existing Graphite metrics publisher loop
# (monitoring/graphite/scripts/run-loop.sh) in the background and tracks its
# PID so it can be stopped later. Does not duplicate any publishing or
# looping logic - it only launches the existing script.
#
# Usage: ./start-metrics.sh [interval_seconds]   (default: 60, passed through)
# Stop with: kill $(cat monitoring/graphite/scripts/run-loop.pid)

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_LOOP="$SCRIPT_DIR/graphite/scripts/run-loop.sh"
PID_FILE="$SCRIPT_DIR/graphite/scripts/run-loop.pid"
LOG_FILE="$SCRIPT_DIR/graphite/scripts/run-loop.log"

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "Metrics publisher already running (PID $(cat "$PID_FILE"))."
    exit 0
fi

nohup "$RUN_LOOP" "${1:-60}" > "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"

echo "Started metrics publisher (PID $(cat "$PID_FILE"))."
echo "Logs: $LOG_FILE"
echo "Stop with: kill \$(cat $PID_FILE)"
