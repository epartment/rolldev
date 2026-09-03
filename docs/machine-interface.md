# Driving RollDev from a script

RollDev is normally used interactively, but everything it does is also reachable without a terminal:
from a CI job, a deployment script, a build server rebuilding environments overnight, or an AI
assistant. This page collects the parts of the interface that exist for that.

The rule underneath all of it: **never parse RollDev's human output.** It is formatted for people,
carries ANSI colour, and its layout is not a contract. The JSON surfaces below are.

## Machine-readable output

Four commands accept `--format json`:

```bash
roll status --format json          # every project on the host
roll env describe --format json    # one project, its services and their state
roll registry list --format json   # every available command, with descriptions
roll env doctor --format json      # per-check diagnostics
```

The output carries no ANSI escapes and no credentials. Values are escaped, so a project path
containing a quote or a non-ASCII character still parses.

The two project commands share a vocabulary — `name`, `type`, `dir`, `url`, `network`, `containers`
— but nest it differently, because one covers every project and the other covers one:

- `status` returns `{"projects": [ … ], "services": [ … ]}`, where `projects` holds one object per
  environment on the host and `services` holds the **shared** RollDev services (traefik, dnsmasq and
  friends).
- `describe` returns a single project object directly, with its own `services` array for that
  project's containers.

Service entries carry at least `name` and `status`.

```bash
# which of this project's services are not running
roll env describe --format json | jq -r '.services[] | select(.status != "running") | .name'

# every environment on the host, by name
roll status --format json | jq -r '.projects[].name'
```

`doctor` returns an overall `ok` alongside a `checks` array, one row per check:

```json
{
  "ok": true,
  "checks": [
    {"check": "search-engine-write:opensearch", "ok": true, "detail": "..."}
  ]
}
```

`registry list` returns `command`, `category`, `description`, `priority` and `source`. Priority is
the registry search tier — project `.roll/commands` (1), `~/.roll/commands` (2), `~/.roll/reclu` (3),
built-in (4) — and **lower wins**, so a project-local command shadows a built-in of the same name.

## Feature detection

Do not assume a command exists. Command availability varies: RollDev version, whether an internal
command pack is installed, and whether the project defines its own commands.

```bash
if roll has-command pull; then
    roll pull
fi
```

`has-command` prints nothing and exits `0` or `1`. It resolves through the registry, so it sees
project-local and add-on commands, not just built-ins.

## Waiting for services

`roll env up` returns as soon as Compose has started the containers, which is not the same as the
services being ready. A script that continues immediately will race the database.

```bash
roll env up --wait
roll db connect -e 'SELECT 1'    # safe: --wait returned only once db reported healthy
```

`--wait` relies on the healthchecks RollDev defines for `db`, `redis`, `elasticsearch`,
`opensearch`, `rabbitmq`, `varnish` and `nginx`. The search engines are checked through
`/_cluster/health` rather than a port probe, because those containers can hold a port open while the
cluster inside them is dead.

One caveat: containers created **before** the healthchecks existed report no health status, so
`--wait` has nothing to wait on for them. Recreate the environment once (`roll env down && roll env
up`) after upgrading.

## Prompts, flags and no terminal

Every prompt resolves in this order: **a value supplied by flag, positional argument or environment
variable, then gum on a terminal, then a hard error naming the flag that would have supplied it.**

A prompt never blocks waiting for input that cannot arrive. Without a terminal, an unanswerable
prompt fails immediately and tells you what to pass:

```
ERROR: Cannot prompt for a password: no terminal attached.
ERROR: Supply it non-interactively with --encrypt=<password>.
```

So a script never hangs, and the fix is always in the error. The non-interactive forms:

| Interactive prompt | Non-interactive form |
|---|---|
| `roll env-init` name and type | `roll env-init <name> <type>` |
| `roll env-init` overwrite confirmation | `ROLL_ENV_INIT_FORCE=1` |
| `roll backup` encryption password | `--encrypt=<password>` |
| `roll restore` decryption password | `--decrypt=<password>` |
| `roll duplicate` encryption password | `--encrypt=<password>` |

`gum` is only needed for the interactive path. A fully flag-driven run works without it installed.

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Success. For `doctor`, every check passed. For `has-command`, the command exists. |
| `1` | Failure. For `doctor`, at least one check failed. For `has-command`, no such command. |
| `130` | Cancelled at an interactive prompt (Ctrl-C). Only reachable on a terminal. |

`--help` also exits `1`, which is long-standing behaviour rather than an error signal — do not treat
a non-zero exit from `--help` as a failed command.

## Pinning versions

From 0.8.0 an enabled service with no version pinned produces a warning, and from 0.9.0 it will be
an error. For unattended use, pin explicitly so that upgrading RollDev cannot change which images a
project runs:

```bash
roll config check-pins    # exits 1 if any enabled service lacks a pin
roll config fix-pins      # writes the versions the project runs today
```

`check-pins` is the one to put in CI. See [Service version pins](configuration/version-pins.md).

## Running many environments on one host

Two settings exist for build servers running several environments at once:

- `ROLL_PUBLISH_PORTS=0` stops the browsersync partial publishing host ports, which otherwise
  collide across environments and cannot be overridden from `.roll/roll-env.yml`.
- `ELASTICSEARCH_JAVA_OPTS` / `OPENSEARCH_JAVA_OPTS` replace the fixed search-engine heap, so
  several search containers can coexist.

See [Unattended operation](configuration/unattended-operation.md).

## A worked example

```bash
#!/usr/bin/env bash
set -euo pipefail

roll config check-pins                       # fail early on unpinned versions
roll env up --wait                           # block until services are actually ready

if ! roll env doctor --format json > doctor.json; then
    jq -r '.checks[] | select(.ok == false) | "\(.check): \(.detail)"' doctor.json >&2
    exit 1
fi

if roll has-command pull; then               # optional add-on command
    roll pull
fi

roll env sh php-fpm 'bin/magento setup:upgrade'   # quoted: redirects apply in the container
```

Note the last line. `roll env exec php-fpm bin/magento ... > out.log` writes `out.log` on the
**host**; `roll env sh` wraps the command in `sh -c` inside the container so redirects and pipes
behave as written.
