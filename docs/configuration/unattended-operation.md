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

## Silencing setup advice

Some of what RollDev prints is advice about how the host or the project is *set up* rather than a
report of what happened during a run: a service whose version is not pinned, a configuration key
RollDev does not recognise. On a developer's machine that advice is the point — they are the only
person who can act on it, in the project's committed `.env.roll`. On a build server it is noise:
the build cannot fix it, should not be editing a shared file to do so, and every line of it
competes with real diagnostics in whatever log or report the run produces.

`ROLL_ADVISORIES=0` turns that advice off:

```bash
ROLL_ADVISORIES=0 roll env up
```

It silences only advice. Warnings about what actually happened during the run are never
suppressed — a database volume written by a different engine, a dump with no schema files in it, a
configuration file that failed to load. Those are exactly what an unattended run needs to report,
so they keep their voice.

Pass it per invocation, as above, or export it for a whole unattended session. It is deliberately
awkward to set project-wide: a committed `.env.roll` that hid this advice would hide it from every
other developer on that project, which is the opposite of what it is for.
