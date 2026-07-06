# Nagios Configuration (Phase 7B)

## Purpose

This configuration makes the Nagios container (started by `monitoring/docker-compose.yml`) actively monitor four parts of the DevOps environment, all reachable through Docker Desktop's host gateway (`host.docker.internal`):

| Service | Check | Endpoint |
|---|---|---|
| Jenkins HTTP | `check_http -p 8080 -u /login` | `http://host.docker.internal:8080/login` |
| TechnoVista Website Kubernetes | `check_http -p <NodePort>` | `http://host.docker.internal:<NodePort>` (NodePort discovered dynamically, see below) |
| Docker Engine Proxy Check | `check_tcp -p 3000` | `host.docker.internal:3000` (proxy check, see limitation below) |
| Kubernetes API | `check_http -p 6443 -S -u /healthz` | `https://host.docker.internal:6443/healthz` |

All four are modeled as services on a single host object, `devops-host` (`conf.d/hosts.cfg`), since they're all reached through the same Docker Desktop host gateway.

## Configuration files

Everything lives in this bind-mounted directory (`monitoring/nagios/`), so it survives `docker compose down && docker compose up -d`:

- `nagios.cfg`, `objects/`, `resource.cfg`, `cgi.cfg`, `nsca.cfg`, etc. — the Nagios image's own default configuration, auto-copied into this directory by the container's entrypoint the first time it starts with an empty `monitoring/nagios/` folder. **Do not delete these** — without them Nagios has no main config file at all and will not start (see Troubleshooting).
- `conf.d/hosts.cfg` — the `devops-host` host object.
- `conf.d/services.cfg` — the three static service checks (Jenkins, Kubernetes API, Docker Engine proxy).
- `conf.d/technovista-website.cfg` — **generated file**, do not hand-edit. Produced by `discover-nodeport.sh`.
- `discover-nodeport.sh` — discovers the current Kubernetes NodePort for `college-event-service` and (re)generates `conf.d/technovista-website.cfg`, then validates and reloads Nagios.

`nagios.cfg`'s default `cfg_dir=/opt/nagios/etc/conf.d` picks up everything in `conf.d/` automatically — no edits to `nagios.cfg` itself were needed.

## Discovering the website NodePort (no hardcoding)

The TechnoVista website's Kubernetes NodePort is not fixed in any config file. Instead, run:

```
cd monitoring/nagios
./discover-nodeport.sh
```

This runs `kubectl get svc college-event-service -o jsonpath='{.spec.ports[0].nodePort}'`, writes the discovered port into `conf.d/technovista-website.cfg`, validates the Nagios config, and reloads Nagios. Re-run it any time the Service is recreated (e.g. after `kubectl apply -f k8s/` or a Jenkins deploy) and the NodePort may have changed.

If `college-event-service` can't be found or has no NodePort, the script prints a clear error explaining why and **exits without touching `technovista-website.cfg`** — it never invents a port number.

**Running it automatically on stack start:** `discover-nodeport.sh` cannot run *inside* the Nagios container automatically, because the `jasonrivers/nagios` image has neither `kubectl` nor the Docker CLI installed, and installing them would mean maintaining a custom image (out of scope for this phase). Instead, `monitoring/up.sh` wraps the stack start: it runs `docker compose up -d`, waits for the `nagios` container to be ready, then runs `discover-nodeport.sh` for you. Use `./up.sh` (from `monitoring/`) instead of a bare `docker compose up -d` so the website check is always regenerated with the current NodePort whenever the stack starts.

## Validate configuration

```
docker exec nagios /usr/local/bin/nagios -v /opt/nagios/etc/nagios.cfg
```

Expect `Total Warnings: 0` / `Total Errors: 0` (a `Warning: Host '...' has no default contacts...` is avoided here because `devops-host` sets `contact_groups admins`).

## Reload

```
docker exec nagios sv reload nagios
```

(`discover-nodeport.sh` does this automatically after regenerating the website check.) If you edit `hosts.cfg` or `services.cfg` by hand, validate first, then run the reload command above.

## Verify

```
docker exec nagios sh -c "ps aux | grep '[n]agios/bin/nagios'"      # confirm the core process is running
curl -u nagiosadmin:nagios http://localhost:8085/nagios/cgi-bin/status.cgi?host=all   # Web UI status page
```

Default Web UI login: `nagiosadmin` / `nagios` (set via `NAGIOSADMIN_USER`/`NAGIOSADMIN_PASS` env vars on the `jasonrivers/nagios` image — change for anything beyond local dev).

## Known limitation: Docker Engine check

**Docker Engine is monitored indirectly, not directly, and this is intentional.** Nagios has no way to ask the Docker Engine "are you healthy?" from inside the `nagios` container, for two concrete reasons:

1. **No Docker socket access**: querying the engine directly (e.g. `docker info`, `docker version`) requires either the Docker CLI plus a mounted `/var/run/docker.sock`, or access to the Docker Engine API over TCP. Neither is present in this container — `/var/run/docker.sock` is not bind-mounted in (confirmed: `ls /var/run/docker.sock` inside the container fails with "No such file or directory").
2. **Docker Desktop does not expose the daemon to containers by default**: the Docker Engine API's plaintext TCP port (2375) is not listening (confirmed: `check_tcp -H host.docker.internal -p 2375` returns "Connection refused"). Docker Desktop only exposes the daemon via a local named pipe/socket on the host, not over the network, and enabling "Expose daemon on tcp://" is a host-level Docker Desktop setting change, not something this repo's configuration controls.

Mounting the socket into the container, or turning on the remote API, would fix this — but both require changing `monitoring/docker-compose.yml` (to add a volume/mount) or host Docker Desktop settings, which are intentionally out of scope for this phase so the working Nagios/Compose configuration stays untouched.

**What we do instead:** `Docker Engine Proxy Check` runs `check_tcp` against port 3000 — Grafana's published port, on the same Docker Engine. The reasoning: if the Docker Engine were down, none of its containers' published ports (Grafana's 3000 included) would be listening at all, so a successful TCP connect to 3000 is indirect evidence the engine is up. This is **not** equivalent to a real daemon health check (it can't detect, for example, a hung dockerd that still holds its listening sockets) — it is the closest signal obtainable without expanding the container's access, and is called out explicitly here so it is never mistaken for a genuine Docker Engine health probe.

## Known note: Kubernetes API TLS

Docker Desktop's Kubernetes API uses a local self-signed certificate. `check_http` (monitoring-plugins 2.4.12, as shipped in the `jasonrivers/nagios` image) does not perform strict CA chain validation on the SSL handshake by default — verified empirically: the check succeeds against the self-signed cert with no additional flag. No certificate validation was silently disabled to make this work; if a future plugin version enforces strict validation, the fix is to add the cluster's CA certificate to the container's trust store, not to add an "ignore SSL errors" flag.

## Troubleshooting

- **"Cannot open main configuration file '/opt/nagios/etc/nagios.cfg'"** in `docker logs nagios`: the bind-mounted `monitoring/nagios/` folder is missing the default Nagios files. The image's entrypoint only auto-copies its defaults into this folder if the folder is *completely empty* on container start (no stray files, not even a placeholder). Fix: stop the container, make sure `monitoring/nagios/` is empty, then `docker compose up -d nagios` (or `docker compose restart nagios`) so it re-seeds, and re-add `conf.d/*.cfg`.
- **"Invalid service object directive '...'" during `nagios -v`**: a `notes` (or any) directive was wrapped across multiple physical lines. Nagios object definitions require each directive on a single line — put long `notes` text on one line.
- **"description string ... contains one or more illegal characters"**: `service_description` (and other name fields) can't contain characters like `()`, per `illegal_object_name_chars` in `nagios.cfg`. Use plain words instead (e.g. `Docker Engine Proxy Check`, not `Docker Engine (proxy check)`).
- **Service shows "PENDING" in the Web UI**: it hasn't run its first check yet (`generic-service` checks every 10 minutes). Force an immediate check via the command pipe:
  ```
  docker exec nagios sh -c 'echo "[$(date +%s)] SCHEDULE_FORCED_SVC_CHECK;devops-host;<Service Name>;$(date +%s)" >> /opt/nagios/var/rw/nagios.cmd'
  ```
