#!/bin/sh
# Starts the monitoring stack and makes sure the TechnoVista Website check
# is regenerated with the current Kubernetes NodePort every time.
#
# Use this instead of a bare `docker compose up -d` so the website check
# never goes stale after a NodePort change (e.g. after `kubectl apply -f k8s/`
# recreates the Service). See nagios/README.md for what discover-nodeport.sh
# does and why it can't run automatically from inside the Nagios container.
#
# Usage: ./up.sh

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$SCRIPT_DIR"
docker compose up -d

echo "Waiting for the nagios container to be ready..."
until docker exec nagios true 2>/dev/null; do
    sleep 1
done

"$SCRIPT_DIR/nagios/discover-nodeport.sh"
