# Monitoring Stack (Phase 7A)

This directory contains the Docker Compose foundation for the project's monitoring infrastructure. It runs three services side by side on a dedicated Docker network. This phase only stands up the containers — Nagios checks, Graphite metric pipelines, and Grafana dashboards are configured in later phases.

## Services

| Service  | Purpose                                                              | Port(s)                                                     |
|----------|-----------------------------------------------------------------------|--------------------------------------------------------------|
| Nagios   | Host/service availability monitoring and alerting                    | 8085 (web UI, mapped to container port 80)                   |
| Graphite | Time-series metrics storage and rendering backend                    | 8081 (web UI), 2003-2004 (Carbon plaintext/pickle), 2023-2024 (Carbon cache query), 8125/udp (StatsD), 8126 (StatsD admin) |
| Grafana  | Dashboards and visualization on top of Graphite (and other sources)   | 3000 (web UI)                                                 |

Configuration for each service is bind-mounted from the `nagios/`, `graphite/`, and `grafana/` subdirectories into the respective containers, so config/data persists across container recreation.

## Network

All three services share a dedicated bridge network, `monitoring-network`, so they can reach each other by container name (e.g. Grafana can query Graphite at `http://graphite:80`).

## Usage

Run these commands from inside the `monitoring/` directory.

**Start the stack (recommended — also regenerates the TechnoVista Website Nagios check with the current Kubernetes NodePort):**
```
./up.sh
```

**Start the stack without NodePort auto-regeneration:**
```
docker compose up -d
```

**Stop the stack:**
```
docker compose down
```

**Check status:**
```
docker compose ps
```

**View logs:**
```
docker compose logs
```

## URLs

- Nagios: http://localhost:8085
- Graphite: http://localhost:8081
- Grafana: http://localhost:3000

## Default credentials

- **Grafana**: `admin` / `admin` (you'll be prompted to change this on first login).
- **Nagios**: `nagiosadmin` / `nagios` (default for the `jasonrivers/nagios` image — change before any non-local use).
- **Graphite**: no default login is enforced by the base image for the endpoints used here.
