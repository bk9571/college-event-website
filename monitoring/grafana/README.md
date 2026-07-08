# Grafana Dashboard (Phase 7D)

## Architecture

```
devops.* metrics (Phase 7C publisher)
  v
Graphite (Whisper storage, render API)
  v
Grafana datasource "Graphite" (provisioned, type=graphite, url=http://graphite)
  v
Dashboard "TechnoVista DevOps Monitoring" (provisioned from repo JSON)
  v
6 panels (3 Stat + 3 Time series), each querying one devops.* metric
```

Grafana and Graphite share the `monitoring-network` Docker network, so Grafana reaches Graphite by its Compose service/container name (`graphite`) rather than `localhost` or the host-mapped port.

## Datasource

Provisioned (not manually configured through the UI) via `provisioning/datasources/graphite.yml`:

| Field | Value |
|---|---|
| Name | `Graphite` |
| Type | `graphite` |
| URL | `http://graphite` |
| UID | `graphite` (fixed, so dashboard panels can reference it reliably) |
| Access | `proxy` (Grafana backend queries Graphite server-side) |

## Provisioning

Grafana's default provisioning path is `/etc/grafana/provisioning`, which is **not** part of the existing bind mount (`./grafana:/var/lib/grafana`). Files placed there on disk would not be visible to the container, and files placed inside the container at that path would not survive `docker compose down` (nothing there is persisted). To make repo-tracked provisioning survive container recreation without adding a second bind mount, `monitoring/docker-compose.yml`'s `grafana` service now sets:

```yaml
environment:
  - GF_PATHS_PROVISIONING=/var/lib/grafana/provisioning
```

This redirects Grafana's provisioning lookup to a path *inside* the already bind-mounted `./grafana` directory, so everything under `monitoring/grafana/provisioning/` is both repo-tracked and automatically picked up on every container start - no manual re-creation needed after `docker compose down && docker compose up -d`.

Provisioning files:
- `provisioning/datasources/graphite.yml` - the Graphite datasource definition (see above).
- `provisioning/dashboards/dashboard.yml` - tells Grafana to load any dashboard JSON files from `/var/lib/grafana/provisioning/dashboards` (the same directory this file lives in) on a 30-second poll.
- `provisioning/dashboards/technovista-dashboard.json` - the dashboard itself, in Grafana's dashboard JSON model, committed to the repository (not only inside Grafana's internal `grafana.db`).

## Dashboard

**Title:** TechnoVista DevOps Monitoring (`uid: technovista-devops`)

| # | Panel title | Type | Metric |
|---|---|---|---|
| 1 | Jenkins Availability | Stat | `devops.jenkins.available` |
| 2 | Website Availability | Stat | `devops.website.available` |
| 3 | Kubernetes API Availability | Stat | `devops.kubernetes_api.available` |
| 4 | Jenkins Response Time | Time series | `devops.jenkins.response_time_ms` |
| 5 | Website Response Time | Time series | `devops.website.response_time_ms` |
| 6 | Kubernetes API Response Time | Time series | `devops.kubernetes_api.response_time_ms` |

Layout: the three Stat panels form the top row (availability at a glance, value-mapped to `UP`/`DOWN` with green/red background); the three Time series panels form the row below (response time in ms). No metrics were created or changed for this phase - all six panels query metrics that Phase 7C's publisher already produces.

## Verification

**Via the UI:** http://localhost:3000 -> Dashboards -> TechnoVista DevOps Monitoring. Requires metrics to have been published at least once (see [`monitoring/graphite/README.md`](../graphite/README.md) for `start-metrics.sh`/`run-loop.sh`) for panels to show non-empty data.

**Via the HTTP API** (proves provisioning was actually loaded, not just present on disk):
```
# Datasource was provisioned
curl -u <user>:<pass> http://localhost:3000/api/datasources

# Datasource can actually reach Graphite
curl -u <user>:<pass> http://localhost:3000/api/datasources/uid/graphite/health

# Dashboard was auto-loaded from the repo file
curl -u <user>:<pass> "http://localhost:3000/api/search?type=dash-db"
curl -u <user>:<pass> http://localhost:3000/api/dashboards/uid/technovista-devops
# look for "provisionedExternalId":"technovista-dashboard.json" in the response

# A panel's query returns real, non-null data points (through Grafana's own
# query path, not just Graphite directly)
curl -u <user>:<pass> "http://localhost:3000/api/datasources/proxy/uid/graphite/render?target=devops.jenkins.available&format=json&from=-10min"
```

## Troubleshooting

- **Dashboard/datasource don't reappear after `docker compose down && up`**: confirm `GF_PATHS_PROVISIONING=/var/lib/grafana/provisioning` is still set on the `grafana` service in `monitoring/docker-compose.yml`, and that `monitoring/grafana/provisioning/` exists on the host with both `datasources/graphite.yml` and `dashboards/dashboard.yml` + `technovista-dashboard.json` present.
- **`docker logs grafana` shows no `provisioning.datasources`/`provisioning.dashboard` lines**: Grafana isn't finding the provisioning directory - check `docker exec grafana env | grep GF_PATHS_PROVISIONING` and `docker exec grafana ls /var/lib/grafana/provisioning`.
- **Panels show "No data"**: the Graphite metrics publisher (Phase 7C) hasn't run recently, or the dashboard's time range doesn't overlap with when it did. Run `./start-metrics.sh` from `monitoring/` and re-check, or widen the dashboard's time range.
- **Datasource health check fails ("Successfully connected" not returned)**: confirm the `graphite` container is running and reachable on the `monitoring-network` (`docker exec grafana sh -c "wget -qO- http://graphite/render?target=carbon.agents.graphite.pointsPerUpdate&format=json"` as a quick reachability test).
- **Can't log into the API/UI**: Grafana's admin credentials are whatever was set for this environment - they are not stored in this repository. If truly lost, `docker exec grafana grafana-cli admin reset-admin-password <new-password>` resets them (this changes live credentials, so only do it deliberately).
