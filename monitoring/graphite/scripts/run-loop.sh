#!/bin/bash
# Phase 7C - runs publish-metrics.sh on a fixed interval so metrics keep
# arriving in Graphite continuously, without any external scheduler,
# exporter, or agent framework.
#
# Usage: ./run-loop.sh [interval_seconds]   (default: 60)
# Stop with Ctrl+C, or `kill` the PID printed on start.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INTERVAL="${1:-60}"

echo "Publishing metrics every ${INTERVAL}s (PID $$). Press Ctrl+C to stop."
while true; do
    "$SCRIPT_DIR/publish-metrics.sh"
    sleep "$INTERVAL"
done
