# Unattended operation

These toggles matter most on a build server that provisions many environments in parallel,
unattended. Interactively running a single project usually needs neither.

## Suppressing published host ports

When [BrowserSync](livereload.md) is enabled with `ROLL_BROWSERSYNC=1`, RollDev publishes its web
and UI ports on the host so a browser can reach them directly. Those ports are fixed, so two
environments on the same host with BrowserSync enabled collide on the same host port — Compose
reports `Bind for 0.0.0.0:<port> failed: port is already allocated` and the `php-fpm` container
never starts.

Set `ROLL_PUBLISH_PORTS=0` in `.env.roll` to suppress host port publication for the whole
environment:

```
ROLL_PUBLISH_PORTS=0
```

The default is `1` (publish ports, current behaviour). With it set to `0`, `BROWSERSYNC_PORT_WEB`
and `BROWSERSYNC_PORT_UI` are still passed into the `php-fpm` container as environment variables —
only the host port mapping is skipped, so BrowserSync itself is unaffected for anything reaching it
through the container network (e.g. Traefik).

## Search-engine heap size

`ROLL_ELASTICSEARCH` and `ROLL_OPENSEARCH` both default their JVM heap to `-Xms64m -Xmx512m`. That
is enough for a small catalog but too little for a large one — the container gets OOM-killed part
way through indexing, and the visible symptom is a connection error from the application rather
than anything that points at memory.

Override it per project in `.env.roll`:

```
ELASTICSEARCH_JAVA_OPTS=-Xms256m -Xmx2g
OPENSEARCH_JAVA_OPTS=-Xms256m -Xmx2g
```

Each applies only to its own service — set the one matching whichever engine
(`ROLL_ELASTICSEARCH`/`ROLL_OPENSEARCH`) the project has enabled.
