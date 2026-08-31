# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Read the README first

[README.md](README.md) is the authoritative description of this repository and is kept current. It is
not a marketing page — it documents the architecture, the platform contract, the conventions, and the
known defects, with `file:line` citations. **Read the sections relevant to your task before editing**,
rather than re-deriving the same facts from the source:

| Question | README section |
|---|---|
| What is this, what is the stack, what versions | [Stack](README.md#stack) |
| How do I install/run it, which hosts are supported | [Getting started](README.md#getting-started), [Supported platforms](README.md#supported-platforms) |
| How does dispatch, the command registry, or config loading work | [Architecture](README.md#architecture) |
| How is a `docker compose` invocation assembled from YAML fragments | [How a compose invocation is assembled](README.md#how-a-compose-invocation-is-assembled) |
| Which environment types and service toggles exist, and what each actually provides | [Environments](README.md#environments) |
| What are the commands people run | [Common tasks](README.md#common-tasks) |
| What are the rules for editing this codebase | [Conventions](README.md#conventions) |
| Which components are too big, duplicated, or wrongly coupled | [Module boundaries & coupling](README.md#module-boundaries--coupling) |
| Is this behaviour a bug, and is it already known | [Known issues & improvement points](README.md#known-issues--improvement-points) |
| Was this already investigated and found correct | [Audited and clean](README.md#audited-and-clean) |
| A symptom I am debugging | [Troubleshooting](README.md#troubleshooting) |

Everything below is guidance that belongs to *working on* the repository rather than to the repository
itself, so it is not duplicated in the README.

## Before you start

- **Check the known defects before diagnosing anything.** Several surprising behaviours are already
  documented with a verified root cause in
  [Known issues & improvement points](README.md#known-issues--improvement-points) — a red ShellCheck
  run, `roll db dump` failing, `roll registry categories` dying on macOS, magento2 environments coming
  up without Varnish or a search engine, images never refreshing on Linux. Do not re-derive them, and
  do not report one as a new discovery.
- **Check [Audited and clean](README.md#audited-and-clean) before investigating something that looks
  wrong.** It records what was checked and found correct, including two things that read as bugs and
  are not.
- **Check [FEATURE-REQUESTS.md](FEATURE-REQUESTS.md) before proposing an improvement.** It records
  gaps found while driving RollDev unattended, with severities and citations, plus a "checked, and
  already covered" table. Its `H1`/`M1`/`L1` numbering is independent of the README's.

## Non-negotiables when editing

These are the constraints most easily broken by a plausible-looking edit. Each is explained in
[Conventions](README.md#conventions) — this is the checklist, not the explanation.

1. **Bash 3.2.** No associative arrays, no `${var^}`, no bare `mapfile`. macOS ships bash 3.2.57, so
   a bash-4 construct passes CI and fails for most users.
2. **macOS *and* Linux.** Both are required targets and they differ in ways that matter; see the
   difference table in [Supported platforms](README.md#supported-platforms). CI runs Ubuntu only.
3. **Keep the sourcing guard** `[[ ! ${ROLL_DIR} ]] && … exit 1` at the top of every `.cmd` and util
   script.
4. **`x=$((x + 1))`, never `((x++))`.** `bin/roll` runs under `set -e` and sources command bodies into
   that shell, so a statement returning non-zero kills the CLI silently.
5. **Register new config in the schema** (`initConfigSchema` in `utils/config.sh`). Do not rely on a
   `${VAR:-default}` fallback inside a YAML fragment — the exported schema value wins, which is why
   eight such fallbacks in `environments/` are currently dead code.
6. **Use the messaging helpers** from `utils/core.sh`, not raw `echo`.

## Container images are built in a separate repository

The Docker images this CLI runs — `php-fpm` and its `magento1`/`magento2`/`wordpress`/`node` variants,
`mariadb`, `mysql`, `nginx`, `elasticsearch`, `opensearch`, `redis`, `varnish`, `rabbitmq`, `dnsmasq` —
are **not built here**. They live in [github.com/epartment/images](https://github.com/epartment/images)
(Dockerfiles plus a GitHub Actions matrix) and are published to `ghcr.io/epartment/roll`. This
repository only references them by tag.

So any change requiring a binary, package, or PHP extension to exist *inside* a container — adding a
CLI tool, baking in a PHP extension, changing a base image — must be made in the images repository,
not here. Nothing in `commands/` or `environments/` can add a tool to a container.

That repository is not part of this checkout and its local path varies per machine. **If a task needs
it, ask the user for the local directory** rather than guessing; there is no derivable location.

## Verifying a change

There is no unit-test suite. What is available:

- **ShellCheck**, the only CI gate: `shellcheck commands/*.cmd utils/*.sh`. Note that it **already
  fails** on a clean checkout (finding **H1** in the README), so a red run is not evidence that your
  change broke something. Capture the finding count before your change and compare, or scope the run
  to the files you touched. The gate also does not cover `commands/magento2/`, `commands/wordpress/`
  or the `.help` files (finding **L9**), so lint those explicitly if you edit them.
- **Running the CLI from source:** `./bin/roll <command>`. On macOS invoke it as
  `/bin/bash ./bin/roll <command>` when checking Bash 3.2 compatibility, so the system bash is
  exercised rather than a newer one from `PATH`.
- **Commands that need no Docker daemon** and are useful smoke tests: `roll version`,
  `roll config schema`, `roll registry validate`, `roll registry paths`, and `roll env-init` into a
  temporary directory followed by `roll config validate`.
- **Loading the config in isolation**, to check what a `.env.roll` actually resolves to: source
  `utils/core.sh`, `utils/config.sh`, `utils/registry.sh`, `utils/env.sh` in that order with
  `ROLL_DIR` and `ROLL_HOME_DIR` set, then call `loadEnvConfig <project-path>` and print the
  variables. This is how the effective-defaults findings in the README were confirmed.

Do not claim a change is verified on the strength of a syntax check alone: most of the defects in the
README's findings list are syntactically valid shell.

## Blast radius

RollDev is distributed via Homebrew (`epartment/roll/roll`) and installs itself into `~/.roll` on
first run, so a released change reaches every installed machine on the next `brew upgrade`, and
`assertRollDevInstall` (`utils/install.sh:43`) re-runs `roll install` whenever `bin/roll` is newer than
`~/.roll/.installed`. When changing anything in `commands/install.cmd`, `utils/install.sh`, or the
`~/.roll` layout, verify the **upgrade** path and the **fresh-install** path separately — "it
self-installs, so it is fine" is not an analysis. Several install steps require `sudo` and touch
host-level state (`/etc/resolver/test`, `/etc/ssh/ssh_config`, the system trust store).

## Keeping documentation in sync

- **[README.md](README.md)** — update it in the same change as the behaviour it describes. When a
  finding in [Known issues & improvement points](README.md#known-issues--improvement-points) is
  fixed, **remove** it rather than marking it done; git history is the record. Note that the section
  above `<!-- include_open_stop -->` is inlined into the published documentation home page by
  `docs/index.md`, so keep that marker in place.
- **`docs/`** — user-facing documentation, built with Sphinx and published to
  [epartment.github.io/rolldev](https://epartment.github.io/rolldev) on push to `main`. Update it for
  any user-visible behaviour change. The README is the contributor-facing document; `docs/` is the
  user-facing one, and they should not contradict each other.
- **[FEATURE-REQUESTS.md](FEATURE-REQUESTS.md)** — add an entry when you find a gap you are not
  fixing; move it out when it is implemented.
