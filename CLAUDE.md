# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

RollDev is a CLI (pure Bash) that orchestrates Docker development environments for PHP frameworks/CMS (Magento 1/2, Laravel, Symfony, TYPO3, Shopware, WordPress, Akeneo, plain PHP, Vue.js). There is no application code — it is a wrapper that assembles `docker compose` invocations from layered YAML fragments and runs commands inside containers. Distributed primarily via Homebrew (`epartment/roll/roll`).

## Commands

- **Lint (the only CI test):** `shellcheck commands/*.cmd utils/*.sh`. This runs in `.github/workflows/shellcheck.yml` on any change to `commands/*.cmd` or `utils/*.sh`. There is no unit-test suite — run shellcheck locally before pushing changes to those files.
- **Run the CLI from source:** `./bin/roll <command>`. The `version` file holds the current version string.
- **Two orchestration scopes:**
  - `roll svc <up|down|...>` — global shared services (Traefik reverse proxy, tunnel, mailhog, optional portainer/startpage). Compose project name is always `roll`, project dir `~/.roll`.
  - `roll env <up|down|...>` — the per-project environment, run from inside a project dir containing `.env.roll`.

## Architecture

### Entry point and dispatch (`bin/roll`)
`bin/roll` resolves its own real path (following symlinks — important for the Homebrew symlink install), then sources the four util libs in order: `core.sh`, `config.sh`, `registry.sh`, `env.sh`. It verifies Docker + docker compose ≥ 2.2.3, then dispatches: the first arg is looked up via `findCommand` (registry), and the matching `commands/<verb>.cmd` is **sourced** (not exec'd) so it runs in the same shell with all globals/functions available. Argument parsing puts positional args in `ROLL_PARAMS`; commands in the `ROLL_CMD_ANYARGS` list (svc, env, db, composer, magento, etc.) pass through all flags untouched so they reach docker/the container.

### Command registry (`utils/registry.sh`)
Commands are discovered, not hardcoded. Each command is a pair: `<name>.cmd` (the script) and `<name>.help` (usage text). `initializeRegistry` scans multiple directories by **priority** (lower number wins), letting users override built-in commands:
1. Project-local `${ROLL_ENV_PATH}/.roll/commands` and env-type-specific dirs (priority 1)
2. `~/.roll/commands`, `~/.roll/reclu` (user overrides, priority 2–3)
3. `${ROLL_DIR}/commands` (built-in, lowest priority 4)

Env-type subdirs like `commands/magento2/` provide commands only available inside that environment type. Written for **Bash 3.2** (macOS default) — uses parallel indexed arrays instead of associative arrays everywhere. Maintain that constraint.

### Configuration (`utils/config.sh`, `utils/env.sh`)
A project is identified by an `.env.roll` file. `locateEnvPath` walks up from `pwd` to find it (and resolves it if it's a symlink to a parent stack). `.env.roll` must define `ROLL_ENV_NAME` and `ROLL_ENV_TYPE`. `config.sh` holds the **config schema** (`initConfigSchema`) — the authoritative list of every `ROLL_*`/service variable, its type, and default. When adding a new service toggle or version variable, register it in the schema here.

### How a docker compose invocation is assembled (`env.cmd` + `appendEnvPartialIfExists`)
This is the core mechanism. `env.cmd` reads the service toggles (`ROLL_NGINX`, `ROLL_DB`, `ROLL_REDIS`, `ROLL_ELASTICSEARCH`, `ROLL_VARNISH`, etc.) and, for each enabled one, appends `-f <fragment>.yml` args by calling `appendEnvPartialIfExists`. That function searches a fixed precedence chain and includes **every** match found (later ones layer on top):
```
environments/includes/<name>.base.yml
environments/includes/<name>.<subtype>.yml      # subtype = darwin | linux
environments/<envtype>/<name>.base.yml
environments/<envtype>/<name>.<subtype>.yml
~/.roll/environments/...   (same four, user overrides)
```
So a YAML fragment can be shared (`environments/includes/`), specialized per env type (`environments/magento2/`), and/or specialized per OS (`.darwin.yml` / `.linux.yml`). `env.cmd` also sets env-type-specific defaults (e.g. magento2 turns on varnish/elasticsearch/rabbitmq; magento1 picks an nginx template) before assembling. Final command: `docker compose --env-file .env.roll --project-directory <project> -p $ROLL_ENV_NAME -f ... <params>`.

`environments/<type>/init.env` seeds a new project's `.env.roll` (via `roll env-init`) with sensible per-type defaults (versions, enabled services).

### Networking / peered services (`utils/core.sh`)
Global services in `DOCKER_PEERED_SERVICES` (traefik, tunnel, mailhog) live on the `roll` compose project but must be `docker network connect`ed into each project's network on `env up` (and disconnected on `down`). Traefik routes by `*.test` domains; SSL certs are generated under `~/.roll/ssl`.

### Container exec pattern
User-facing "run X in the container" commands (`shell`, `cli`, `composer`, `magento`, `node`, `npm`, etc.) are thin wrappers that ultimately call `roll env exec -u www-data <container> ...`. Default container is `php-fpm`, overridable via `ROLL_ENV_SHELL_CONTAINER`. `root*` variants drop the `-u www-data`.

### macOS file sync
On Darwin, file sync uses **Mutagen** (`environments/<type>/<type>.mutagen.yml`, overridable by `.roll/mutagen.yml`). `env.cmd` automatically starts/pauses/resumes/stops the sync session around `up`/`start`/`stop`/`down`. Linux mounts directly (no Mutagen).

## Conventions when editing

- Every `.cmd` and util script starts with the guard `[[ ! ${ROLL_DIR} ]] && ... exit 1` — they are meant to be sourced by `bin/roll`, never run directly. Keep this guard on new scripts.
- Use the messaging helpers from `core.sh` (`fatal`, `error`, `warning`, `info`, `success`, `box*`) rather than raw echo for user-facing output.
- Cross-platform: gate OS-specific logic on `$OSTYPE` (`darwin*` vs Linux) and use `sed_inplace` from `core.sh` instead of `sed -i` directly (BSD vs GNU sed differ).
- A new command = add `commands/<name>.cmd` + `commands/<name>.help`; the registry picks it up automatically, no central list to edit (but if it should accept arbitrary pass-through flags, add it to `ROLL_CMD_ANYARGS` in `bin/roll`).
- A new service = add YAML fragment(s) under `environments/includes/` (and per-type overrides), wire a `ROLL_<SERVICE>` toggle into `env.cmd`'s assembly block, and register the variable + default in `config.sh`'s schema.
- Default image registry is `ghcr.io/epartment/roll`, overridable via `ROLL_IMAGE_REPOSITORY`.

## Docs
User-facing documentation lives in `docs/` (published to `epartment.github.io/rolldev` via GitHub Pages). Update it when changing user-visible behavior.
