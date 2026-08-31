# Diagnosing an environment with `roll env doctor`

`roll env doctor` (also available as the top-level `roll doctor`) answers a single question: is
the current project environment actually fit to run? Instead of letting a problem surface later as
an opaque Docker or application error deep into a build, it runs a fixed set of checks and reports
one line per check.

```
roll env doctor
```

```
roll env doctor --format json
```

## What it checks

- **`env-config`** — `.env.roll` for this project loads.
- **`docker`** — the Docker daemon is reachable.
- **`container:<service>`** — every container this project has is running, and if it carries a
  Docker healthcheck, that healthcheck reports healthy. A container with no healthcheck configured
  at all — for example one started before its compose fragment gained a healthcheck — is reported
  as running but unverified, not as a failure.
- **`port-80` / `port-443` / `port-53`** — the ports the shared roll core services need (Traefik on
  80/443, dnsmasq on 53) are bound by those services, or free for them to bind. Project containers
  route through Traefik rather than publishing ports of their own, so these are the ports every
  project actually depends on.
- **`port-browsersync`** — when BrowserSync is enabled with host port publication on, whether its
  ports are bound.
- **`search-engine:<engine>`** — the configured search engine (OpenSearch or Elasticsearch, reached
  through Traefik on its own subdomain) answers `/_cluster/health` with a status other than red.
- **`search-engine-write:<engine>`** — the search engine also accepts a throwaway index write,
  immediately deleted again. A green cluster that refuses writes — for example after hitting a disk
  watermark — is exactly the failure a health-only probe would miss.
- **`disk`** — the Docker data root has at least 5GB free. Probed from inside a running container
  belonging to the project so it works the same way whether the Docker daemon runs natively on
  Linux or inside a VM (Docker Desktop, OrbStack).

## Exit status and output

Exit status is `0` when every check passes and `1` when any check fails, so `roll env doctor` is
safe to use as a build pipeline gate.

`--format json` prints a single JSON object instead of the human-readable box, with no ANSI escapes
and no credentials:

```json
{
  "checks": [
    {"check": "docker", "ok": true, "detail": "Docker daemon is reachable."}
  ],
  "ok": true
}
```

Each entry in `checks` has `check` (the check name), `ok` (boolean) and `detail` (a human-readable
explanation) — the same shape the failing check would have in the human-readable report, so
automation and interactive use see the same information.
