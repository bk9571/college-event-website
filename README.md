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

## Project Status

This is Phase 1 of a larger DevOps pipeline assignment. Later phases will add Docker, Kubernetes, CI/CD (Jenkins), and monitoring (Nagios/Graphite/Grafana) on top of this static site.
