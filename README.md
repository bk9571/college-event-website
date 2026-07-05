# TechnoVista — College Event Website

A static website for **TechnoVista**, a college's annual technical symposium. Built with plain HTML, CSS, and JavaScript (no frameworks) so it can be containerized with Docker and deployed via Kubernetes in a later phase of this DevOps assignment.

## Pages

- **Home** (`index.html`) — hero banner, intro, and key dates
- **Schedule** (`schedule.html`) — event timings, venues, and tracks by day
- **Register** (`register.html`) — static registration form with client-side validation
- **Speakers** (`speakers.html`) — speaker bios and talk topics
- **Announcements** (`announcements.html`) — news-feed style updates

## Tech Stack

- HTML5, CSS3 (custom "Circuit Noir" dark theme, no CSS framework)
- Vanilla JavaScript (mobile nav toggle, form validation)
- No build step, no backend — everything runs from static files

## Folder Structure

```
college-event-website/
├── index.html
├── schedule.html
├── register.html
├── speakers.html
├── announcements.html
├── css/
│   └── style.css
├── js/
│   └── script.js
├── assets/
│   └── images/
│       └── favicon.svg
├── pom.xml
├── Dockerfile
├── .dockerignore
├── Jenkinsfile
├── k8s/
│   ├── deployment.yaml
│   └── service.yaml
└── README.md
```

Note: since this is plain HTML with no templating/includes, the navbar and footer markup is duplicated identically across each page.

## Running Locally

No build tools or dependencies are required. Either:

1. Open `index.html` directly in a browser, or
2. Serve the folder with any static file server, e.g.:
   ```
   npx serve .
   ```
   or
   ```
   python -m http.server
   ```
   then visit `http://localhost:<port>`.

## Maven Build

This project remains a plain static website — Maven is used only as a packaging tool for the DevOps pipeline, not to run a Java application. There is no Java source code, no application server, and no framework involved.

**How to build:**

```
mvn clean package
```

**Where packaged files are located:**

`target/site` — a complete, runnable copy of the website (all HTML files, `css/`, `js/`, and `assets/`, including the favicon).

Other useful commands:

- `mvn validate` — validates the project is correct
- `mvn clean` — removes the `target/` directory

## Docker

The packaged site (`target/site`, produced by `mvn clean package`) is served using Nginx inside a minimal Docker image. Run `mvn clean package` before building the image so `target/site` exists.

**Build:**

```
docker build -t college-event-website:latest .
```

Optional production tag:

```
docker build -t college-event-website:v1.0 .
```

**Run:**

```
docker run -d -p 8081:80 --name college-event-site college-event-website:latest
```

Open [http://localhost:8081](http://localhost:8081).

**Stop:**

```
docker stop college-event-site
```

**Remove container:**

```
docker rm college-event-site
```

**Remove image:**

```
docker rmi college-event-website:latest
```

## Jenkins CI

A `Jenkinsfile` at the repo root defines a CI-only pipeline: it checks out the code, verifies the toolchain, runs the Maven build, builds the Docker image, verifies both build outputs, and archives artifacts. It does not run containers or deploy anywhere.

**Prerequisites:**

- Jenkins LTS with the following plugins installed:
  - Git plugin (repository checkout)
  - Pipeline plugin (declarative pipeline support)
  - Workspace Cleanup plugin (`cleanWs()`)
- A Jenkins agent (or the built-in node) with `git`, a JDK, Maven, and Docker Desktop available on its `PATH`. This project targets a Windows agent (the pipeline uses `bat`, not `sh`).

**Creating the pipeline job:**

1. In Jenkins, choose **New Item → Pipeline**, name it (e.g. `college-event-website-ci`).
2. Under **Pipeline**, set **Definition** to **Pipeline script from SCM**.
3. Set **SCM** to **Git**.
4. **Repository URL:** `https://github.com/bk9571/college-event-website.git`
5. **Branch Specifier:** `*/main`
6. **Script Path:** `Jenkinsfile`
7. Save the job.

Since the repository is public, no credentials are required for checkout.

**Triggering a build manually:**

Open the job in Jenkins and click **Build Now**. (No webhooks or automatic triggers are configured in this phase.)

**Expected pipeline stages:**

1. Clean Workspace
2. Checkout Source
3. Environment Verification (`git`, `java`, `mvn`, `docker` versions)
4. Maven Build (`mvn clean package`)
5. Verify Build Output (`target/site` exists)
6. Docker Build (`docker build -t college-event-website:latest .`)
7. Verify Docker Image (image exists via Docker CLI)
8. Run Docker Container (starts a smoke-test container on port 8082 — see [Phase 5B](#phase-5b--docker-smoke-testing))
9. Smoke Test (curl check against the running container)
10. Archive Build Artifacts (`target/**`, `README.md`, `pom.xml`, with fingerprinting)

## Phase 5B – Docker Smoke Testing

After the Docker image is built and verified, the pipeline proves the image actually serves the website — not just that it exists — by running it and hitting it with a real HTTP request.

**What it does:**

1. **Run Docker Container** — removes any leftover `college-event-ci` container from a previous run (ignoring errors if none exists), then starts a fresh container from `college-event-website:latest` named `college-event-ci`, publishing it on **port 8082**. The pipeline waits a few seconds for nginx to finish starting before testing it.
2. **Smoke Test** — uses `curl` to request `http://localhost:8082/`. The build fails immediately if the HTTP request fails. The response body is then checked for the string `TechnoVista` (present in the page `<title>`); the build fails if that content is missing. A success message is printed when both checks pass.
3. **Cleanup Container** — `docker stop college-event-ci` and `docker rm college-event-ci` always run, regardless of whether the smoke test passed or failed, via the pipeline's `post { always {} }` block. This guarantees no leftover container survives a build, successful or not.

This stays a pure CI check — the container is disposable and torn down every run; nothing is deployed or left running.

## Phase 6A – Kubernetes Deployment

The existing Docker image (`college-event-website:latest`) can be deployed manually to a local Kubernetes cluster using the manifests in `k8s/`. This is a manual workflow — Jenkins is not yet integrated with Kubernetes (that's Phase 6B).

**Prerequisites:**

- Docker Desktop with Kubernetes enabled (tested against a single-node `docker-desktop` cluster).
- `kubectl` configured against that cluster (`kubectl get nodes` should show `docker-desktop` as `Ready`).
- The `college-event-website:latest` image already built locally (`docker build -t college-event-website:latest .`), since the Deployment uses `imagePullPolicy: IfNotPresent` and does not pull from a registry.

**Directory structure:**

```
k8s/
├── deployment.yaml   # Deployment: college-event-deployment (2 replicas, resource limits, health checks)
└── service.yaml      # Service: college-event-service (NodePort, auto-assigned port)
```

**Deploy:**

```
kubectl apply -f k8s/
```

**Verify:**

```
kubectl get deployments
kubectl get pods
kubectl get services
kubectl describe deployment college-event-deployment
kubectl describe service college-event-service
```

The Service is `NodePort` type with no hardcoded port — Kubernetes assigns one automatically. Find it with:

```
kubectl get service college-event-service -o jsonpath="{.spec.ports[0].nodePort}"
```

then open `http://localhost:<nodePort>` in a browser.

**Scaling:**

```
kubectl scale deployment college-event-deployment --replicas=3
kubectl get pods
```

**Rollout status:**

```
kubectl rollout status deployment college-event-deployment
kubectl rollout history deployment college-event-deployment
```

**Cleanup:**

```
kubectl delete -f k8s/
```

## Project Status

This is Phase 1 of a larger DevOps pipeline assignment. Later phases will add Docker, Kubernetes, CI/CD (Jenkins), and monitoring (Nagios/Graphite/Grafana) on top of this static site.
