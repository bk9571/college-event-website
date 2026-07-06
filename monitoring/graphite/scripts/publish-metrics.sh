#!/bin/bash
# Phase 7C - collects real availability/response-time readings for Jenkins,
# the TechnoVista website (Kubernetes), and the Kubernetes API, and sends
# them to Graphite's Carbon receiver using the plaintext protocol
# ("<metric.path> <value> <unix-timestamp>\n" over a plain TCP socket).
#
# This is a one-shot pass (checks each target once and exits). Run it in a
# loop for periodic publishing - see run-loop.sh in this same directory.
#
# No third-party exporter, agent, or monitoring framework is used: this is
# plain curl + bash's built-in /dev/tcp, sent straight to Carbon's line
# receiver, exactly like discover-nodeport.sh talks to kubectl and Nagios's
# check_http/check_tcp talk to their targets.

set -u

GRAPHITE_HOST="${GRAPHITE_HOST:-localhost}"
GRAPHITE_PORT="${GRAPHITE_PORT:-2003}"

send_metric() {
    # $1 = metric path, $2 = value, $3 = unix timestamp
    exec 3<>"/dev/tcp/${GRAPHITE_HOST}/${GRAPHITE_PORT}" || {
        echo "ERROR: could not connect to Carbon at ${GRAPHITE_HOST}:${GRAPHITE_PORT}" >&2
        return 1
    }
    printf '%s %s %s\n' "$1" "$2" "$3" >&3
    exec 3<&- 3>&-
}

check_and_publish() {
    # $1 = metric name segment (e.g. "jenkins"), $2 = URL to check
    name="$1"
    url="$2"
    ts=$(date +%s)

    # -k is required only for the Kubernetes API check (see README: Docker
    # Desktop's Kubernetes API uses a local self-signed certificate). It is
    # a no-op for the plain-HTTP Jenkins/website checks.
    read -r http_code time_total < <(curl -sk --max-time 5 -o /dev/null -w '%{http_code} %{time_total}' "$url")

    if [ "$http_code" = "200" ]; then
        available=1
    else
        available=0
    fi
    response_ms=$(awk "BEGIN { printf \"%.0f\", ${time_total:-0} * 1000 }")

    send_metric "devops.${name}.available" "$available" "$ts"
    send_metric "devops.${name}.response_time_ms" "$response_ms" "$ts"
    send_metric "devops.${name}.http_status" "$http_code" "$ts"

    echo "[${name}] http_status=${http_code} available=${available} response_time_ms=${response_ms}"
}

check_and_publish "jenkins" "http://localhost:8080/login"

nodeport="$(kubectl get svc college-event-service -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)"
if [ -n "$nodeport" ]; then
    check_and_publish "website" "http://localhost:${nodeport}/"
else
    echo "WARNING: could not discover NodePort for college-event-service - skipping website metric (not fabricating a value)" >&2
fi

check_and_publish "kubernetes_api" "https://localhost:6443/healthz"
