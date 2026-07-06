# Graphite Metrics (Phase 7C)

## Architecture

```
publish-metrics.sh (host)
  |
  |-- curl checks: Jenkins /login, TechnoVista website NodePort, Kubernetes API /healthz
  |-- for each: computes available (1/0), response_time_ms, http_status
  v
Carbon plaintext protocol (TCP, "<metric.path> <value> <unix-timestamp>\n")
  v
graphite container :2003 (Carbon line receiver, process "carbon"/carbon-cache)
  v
Whisper storage (on the graphite container's filesystem)
  v
Graphite render API (http://localhost:8081/render?target=...) - used to verify ingestion
```

`run-loop.sh` wraps `publish-metrics.sh` in a `while true; sleep <interval>` loop so metrics arrive continuously. No exporter, agent, or third-party monitoring framework (no Prometheus, Telegraf, collectd, StatsD client library, etc.) is used — this is plain `curl` + bash's built-in `/dev/tcp`, talking directly to Carbon's plaintext port, the same lightweight approach `discover-nodeport.sh` (Phase 7B) uses for `kubectl`.

## Why a publisher script instead of Nagios performance data

Nagios's `check_http`/`check_tcp` plugin output does include Nagios-native performance data (visible as `|time=...` in `plugin_output`), but exporting that into Graphite requires either the image's bundled `nagiosgraph` add-on (which needs its own object/service config wiring and a different, non-plaintext ingestion path) or a custom NSCA/perfdata bridge — both meaningfully more moving parts than the assignment's "avoid unnecessary third-party exporters" guidance favors. Sending the same kind of check (HTTP availability + response time) straight from a small script to Carbon's plaintext port is simpler, transparent, and uses only tools already in this project's toolchain (`curl`, `bash`, `kubectl`).

## Metrics being collected

| Metric name | Meaning | Value | Source |
|---|---|---|---|
| `devops.jenkins.available` | Is Jenkins responding? | `1` if HTTP 200, else `0` | `curl http://localhost:8080/login` |
| `devops.jenkins.response_time_ms` | Jenkins response time | milliseconds | same curl call (`%{time_total}`) |
| `devops.jenkins.http_status` | Raw HTTP status code | e.g. `200` | same curl call |
| `devops.website.available` | Is the TechnoVista website (Kubernetes) responding? | `1`/`0` | `curl http://localhost:<NodePort>/` |
| `devops.website.response_time_ms` | Website response time | milliseconds | same curl call |
| `devops.website.http_status` | Raw HTTP status code | e.g. `200` | same curl call |
| `devops.kubernetes_api.available` | Is the Kubernetes API responding? | `1`/`0` | `curl https://localhost:6443/healthz` |
| `devops.kubernetes_api.response_time_ms` | K8s API response time | milliseconds | same curl call |
| `devops.kubernetes_api.http_status` | Raw HTTP status code | e.g. `200` | same curl call |

Every value is a real measurement from an actual `curl` request made at send time — nothing is fabricated or hardcoded. The website's NodePort is discovered fresh on every run via `kubectl get svc college-event-service`, the same way `monitoring/nagios/discover-nodeport.sh` does it; if discovery fails, the website metrics are skipped for that cycle (with a warning) rather than sending an invented port or a fake "down" reading.

## Transmission mechanism

Plain Carbon **plaintext protocol**: `<metric path> <value> <unix timestamp>\n` written directly to a TCP socket on `localhost:2003` (bash's `/dev/tcp/<host>/<port>`, no `nc`/netcat dependency). This is Graphite's simplest, standard ingestion path — no pickle protocol, no StatsD, no AMQP.

## Ports

| Port | Purpose |
|---|---|
| 2003 | Carbon plaintext line receiver (what `publish-metrics.sh` sends to) |
| 2004 | Carbon pickle receiver (unused by this script) |
| 2023/2024 | Carbon aggregator (unused by this script) |
| 8125/udp, 8126 | StatsD (unused by this script) |
| 8081 | Graphite web UI / render API (used only for verification) |

## Running it

One-shot (single check + send):
```
./scripts/publish-metrics.sh
```

Continuous, in the foreground, every 30 seconds (default 60s if no argument given):
```
./scripts/run-loop.sh 30
```
Stop with Ctrl+C, or `kill` the PID it prints on startup.

### Starting metrics in the background

`monitoring/start-metrics.sh` is a thin convenience wrapper around `run-loop.sh` above — it launches the same loop in the background (via `nohup`) and records its PID, so you don't need to keep a terminal open. It does not implement any publishing/looping logic itself.

**Start (from `monitoring/`):**
```
./start-metrics.sh          # every 60s (default)
./start-metrics.sh 30       # every 30s
```
Output confirms the PID and log file location, e.g. `Started metrics publisher (PID 1234).` Logs go to `monitoring/graphite/scripts/run-loop.log`. Running `./start-metrics.sh` again while one is already active is a no-op — it detects the existing PID and exits without starting a second copy.

**Stop:**
```
kill $(cat monitoring/graphite/scripts/run-loop.pid)
```

### Verify metrics are flowing

After starting (either the foreground loop or `start-metrics.sh`), confirm data is actually arriving — not just that the process is running:
```
curl -s "http://localhost:8081/render?target=devops.jenkins.available&format=json&from=-10min"
```
Look for multiple non-null datapoints at increasing timestamps (one per publish cycle) — a single datapoint means it only ran once so far; none at all means metrics aren't reaching Graphite (see Troubleshooting below). The full set of verification commands for every metric is in the next section.

## Verification commands

**Confirm Carbon is listening (not just the web UI):**
```
docker exec graphite sh -c "netstat -tln 2>/dev/null | grep :2003"
```

**Send a manual test metric and read it back (proves ingestion + storage + query, not just "container running"):**
```
printf "test.manual.check 1 $(date +%s)\n" > /dev/tcp/localhost/2003
curl -s "http://localhost:8081/render?target=test.manual.check&format=json&from=-5min"
```
A non-null value at the timestamp you just sent confirms the full pipeline (transmission -> storage -> query) is working.

**Check a real metric after running the publisher:**
```
curl -s "http://localhost:8081/render?target=devops.jenkins.available&format=json&from=-10min"
curl -s "http://localhost:8081/render?target=devops.website.response_time_ms&format=json&from=-10min"
curl -s "http://localhost:8081/render?target=devops.kubernetes_api.http_status&format=json&from=-10min"
```

## Troubleshooting

- **"Error: missing required config '/opt/graphite/conf/carbon.conf'" in `docker logs graphite`, carbon-cache never listens on 2003**: the bind-mounted `monitoring/graphite/` folder is missing the image's default config files. Unlike the Nagios image, `graphiteapp/graphite-statsd` does **not** auto-seed an empty bind-mounted conf directory on container start — the config files must be present in `monitoring/graphite/` before/when the container starts. If this happens: extract the defaults from a fresh, unmounted container of the same image (`docker create` + `docker cp .../opt/graphite/conf/. <dest>` + `docker rm`), copy them into `monitoring/graphite/`, then `docker compose restart graphite`.
- **`/dev/tcp/localhost/2003: Connection refused`**: Carbon isn't listening yet, or the config is broken (see above). Check `docker exec graphite sh -c "netstat -tln | grep 2003"`.
- **Metric shows as `null` in `/render` output**: either it hasn't been sent yet, the timestamp is outside the `from=` window, or the metric name doesn't match what was sent exactly (Graphite metric paths are case-sensitive and dot-delimited).
- **Website metrics missing**: check the publisher's stderr for `WARNING: could not discover NodePort` — this means `kubectl get svc college-event-service` failed or returned no NodePort; fix Kubernetes/kubectl connectivity, don't hand-edit a port into the script.
