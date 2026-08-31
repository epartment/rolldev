# RollDev feature requests

Gaps found while driving RollDev from an automated build pipeline that provisions many Magento 2
environments in parallel, unattended, on a single Linux host. Every item below is something that
cost a failed or undiagnosable build and had to be worked around outside RollDev.

The bias of this list is therefore **unattended and parallel operation**. None of these matter much
for a developer running one environment interactively, which is presumably why they have not come up
before.

Each item cites the file it concerns. Where a claim could not be verified from this repository it is
labelled *unverified* in the sentence that makes it.

## Scope note

Anything requiring a binary, package or PHP extension to exist *inside* a container belongs to the
separate images repository, not here (see `CLAUDE.md`, "Container images live in a separate repo").
Those requests are collected in their own section at the end so they are not mixed in with changes
that can be made in this repo.

## Severity

Adapted from the usual defect scale, since these are gaps rather than bugs:

- **High** — causes builds to fail or to fail undiagnosably today; no in-repo workaround, or only a
  workaround that reaches around RollDev's own configuration.
- **Medium** — works, but costs time or hides the real cause when something goes wrong.
- **Low** — ergonomics; a documented workaround exists.

## Requests

### High

**H1. Service readiness gating — `env up` returns before services accept connections** — `commands/env.cmd:201`

- *What:* No service definition in `environments/` declares a `healthcheck:` (verified —
  `grep -rn "healthcheck" environments/` matches nothing), and `env up` does not pass docker
  compose's `--wait`. `roll env up` therefore returns as soon as containers are *started*, not when
  they are *usable*.
- *Why it matters:* Any command run straight after `env up` races the services it needs. The search
  containers are the worst case because they take the longest to become ready: an application step
  that follows immediately fails with `No alive nodes found in your cluster`, which reads like a
  misconfiguration rather than a race. It is non-deterministic, and it gets worse under parallel
  load, which is exactly when it is hardest to reproduce by hand.
- *Suggested fix:* Add `healthcheck:` blocks to the `db`, `opensearch`, `elasticsearch` and `redis`
  partials in `environments/includes/`, then support `roll env up --wait`. Docker compose's native
  `--wait` already implements the waiting; it just needs healthchecks defined to be meaningful, so
  the healthchecks are the substantive part of this request.

**H2. No supported way to run an environment with no published host ports** — `environments/includes/browsersync.base.yml:3-5`

- *What:* When `ROLL_BROWSERSYNC=1`, that partial publishes `${BROWSERSYNC_PORT_WEB:-3000}` and
  `${BROWSERSYNC_PORT_UI:-3001}` **on the `php-fpm` service**. It is the only file in
  `environments/` that publishes host ports at all (verified — `grep -rl "ports:" environments/`
  matches only this file).
- *Why it matters:* Two environments on one host with browsersync enabled collide on the fixed host
  port. Compose reports `Bind for 0.0.0.0:<port> failed: port is already allocated`, `php-fpm` never
  starts, and every subsequent command fails against a container that is not running. Because the
  ports come from RollDev's own partial rather than the project, rewriting a project's
  `.roll/roll-env*.yml` overrides cannot remove them — the ports are not in the project to begin
  with, so tooling that strips overrides reports success while the collision persists.
- *Suggested fix:* A `ROLL_PUBLISH_PORTS` boolean in the config schema (default `1`, declared
  alongside the other flags around `utils/config.sh:81`) that suppresses host port publication for
  the whole environment. Auto-assigning an ephemeral host port on collision would also solve it and
  would help interactive multi-project use too. The workaround today is to force
  `ROLL_BROWSERSYNC=0` into `.env.roll` before `env up`, which means reaching around RollDev's
  configuration to defeat RollDev's own partial.

### Medium

**M1. Search-container heap size is hardcoded** — `environments/includes/elasticsearch.base.yml:15`, `environments/includes/opensearch.base.yml:15`

- *What:* Both partials set the heap as a literal: `-Xms64m -Xmx512m`. Every other tunable in these
  files (image version, cluster options) is parameterised with `${...}`; the heap is not.
- *Why it matters:* 512 MB is not enough for a large catalog. The container is OOM-killed part way
  through indexing and the visible symptom is a connection error from the application, which points
  the investigation at configuration or networking rather than at memory. Raising it currently means
  editing RollDev's own files, which an upgrade overwrites.
- *Suggested fix:* `${ELASTICSEARCH_JAVA_OPTS:--Xms64m -Xmx512m}` and
  `${OPENSEARCH_JAVA_OPTS:--Xms64m -Xmx512m}`, with matching schema entries in `utils/config.sh`.

**M2. No preflight/diagnostic command** — new command

- *What:* There is no single command that answers "is this environment actually fit to run?".
- *Why it matters:* Automation discovers problems as opaque Docker or application errors, often deep
  into an expensive run — a port already bound, a search cluster that is up but refusing writes, a
  host with no disk headroom. Each surfaces as a different downstream error message that names the
  wrong layer.
- *Suggested fix:* `roll env doctor` that checks services are healthy, required host ports are free,
  the configured search engine answers and accepts an index, and the host has disk headroom; exits
  non-zero with a machine-readable summary. This composes well with H1 — the healthchecks it needs
  are the same ones.

**M4. No machine-readable output from RollDev's own commands** — `commands/status.cmd`

- *What:* `roll status` renders ANSI-formatted output intended for a terminal.
- *Why it matters:* Automation ends up parsing formatted text, which breaks on any cosmetic change.
  This applies to RollDev's own aggregate commands; anything that passes straight through to docker
  compose (for example `roll env ps`) already inherits compose's `--format json`.
- *Suggested fix:* `--format json` for `status` and `describe`.

**M5. No capability query for scripting** — `utils/registry.sh`

- *What:* There is no supported way to ask whether a command exists before depending on it.
- *Why it matters:* Automation that must degrade gracefully across RollDev versions currently parses
  the help listing, which is presentation output and not a contract.
- *Suggested fix:* `roll has-command <name>` communicating through its exit code, or
  `roll registry list --format json`. The registry already discovers commands, so the data exists.

### Low

**L1. `roll db` passes the database password as a process argument** — `commands/db.cmd:51,58,63`

- *What:* `connect`, `import` and `dump` all invoke the client as
  `-p"${MYSQL_PASSWORD}"`, so the password is visible to anything that can read `ps` inside the db
  container. Pre-existing; the MariaDB 11 binary probe (finding H2) did not change it either way.
- *Why it matters:* It is the same class of exposure as RECLU's H2 for TablePlus, which the 0.8.0
  plan fixes in milestone 24. Fixing it here too would make the rule uniform across both repos.
- *Suggested fix:* Feed the credentials through `MYSQL_PWD` in the exec environment, or write a
  `0600` defaults file into the container and pass `--defaults-extra-file`. The latter is what the
  clients themselves recommend and it survives `import`'s stdin pipe, which `MYSQL_PWD` also does.

**L2. Unreachable code at the end of `magepack.cmd`** — `commands/magento2/magepack.cmd`

- *What:* An unconditional `exit 1` sits above the final
  `roll env exec magepack generate …` line, so that line can never run. ShellCheck flags it as
  SC2317, but SC2317 is disabled repo-wide in `.shellcheckrc`, so the gate no longer surfaces it.
- *Why it matters:* Either the `exit 1` is wrong and `magepack generate` is silently dead, or the
  trailing line is leftover and should go. Both readings are defects, and the lint suppression now
  hides the evidence.
- *Suggested fix:* Establish which of the two was intended, delete the other, and drop the
  `disable=SC2317` line from `.shellcheckrc` so the check protects the file again.

## Checked, and already covered

Recorded so the next reader does not re-propose them:

| Considered | Finding |
|---|---|
| Config validation | Already exists — `roll config validate`, `roll config conflicts`, `roll config schema` (`commands/config.cmd`). |
| Argument quoting in `cli`/`clinotty` | Safe. Both pass `"${ROLL_PARAMS[@]}" "$@"` as argv without joining into a shell string (`commands/cli.cmd`, `commands/clinotty.cmd`), so arguments containing spaces, quotes or shell metacharacters survive intact. Note this is a property of the built-in commands; a site-local override of `cli.cmd` may not preserve it. |
| `myloader` flag handling | Correct as designed — the wrapper injects only connection and location defaults and forwards all behaviour flags untouched (`commands/magento2/myloader.cmd`). |
| PHP `STDERR` constant unavailable in the `php-fpm` container | Not an image or RollDev issue. The base is the official `php:*-fpm` image and its `php` is the CLI SAPI, which does define `STDIN`/`STDOUT`/`STDERR` — verified with `docker run --rm php:8.1-fpm-bullseye php -r 'var_dump(PHP_SAPI, defined("STDERR"));'` returning `"cli"` and `true`. A script piped into `php` in the container may use them. |
| `curl` availability in the `php-fpm` container | Present — it ships in the official base image, so probing a service from inside the container needs no change. |
| Compose passthrough | `roll env` forwards extra arguments to docker compose, so `ps --format json`, `logs --tail`, `config` and `down --remove-orphans` all work without RollDev-side support. |
