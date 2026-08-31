# RollDev

RollDev is a pure-Bash CLI that orchestrates Docker development environments for PHP frameworks and
CMS platforms (Magento 1/2, Laravel, Symfony, TYPO3, Shopware, WordPress, Akeneo, Vue.js, plain PHP).
It contains no application code: every command assembles a `docker compose` invocation from layered
YAML fragments, or runs a command inside one of the resulting containers. A single shared stack
(Traefik, dnsmasq, Mailpit, an SSH tunnel) fronts any number of per-project environments, each
reachable over HTTPS at `https://app.<project>.test/` with a locally trusted certificate.

**macOS and Linux are both first-class, fully supported hosts**, and Windows is supported through
WSL2. Every change has to work on macOS *and* Linux — the two differ in bash version, `sed`/`ping`
flag semantics, file-sync strategy and SSH agent handling, and RollDev runs on developer machines and
on unattended Linux hosts alike.

<!-- include_open_stop -->

> `roll db dump` is broken against the MariaDB 11.x images that are in active use. Recorded in
> [Known issues & improvement points](#known-issues--improvement-points) as **H2**.

## Contents

- [Stack](#stack)
- [Getting started](#getting-started)
- [Architecture](#architecture)
- [Module boundaries & coupling](#module-boundaries--coupling)
- [Environments](#environments)
- [Common tasks](#common-tasks)
- [Machine interface](#machine-interface)
- [Conventions](#conventions)
- [Known issues & improvement points](#known-issues--improvement-points)
- [Audited and clean](#audited-and-clean)
- [Troubleshooting](#troubleshooting)

## Stack

| Concern | Choice | Notes |
|---|---|---|
| Host platforms | **macOS and Linux**, both required; Windows via WSL2 | Enforced at `utils/config.sh:353-369`, which fails on any other `$OSTYPE`. See [Supported platforms](#supported-platforms) |
| Language | Bash, targeting **3.2** | macOS ships bash 3.2.57; no associative arrays anywhere, parallel indexed arrays instead (`utils/config.sh:9-15`, `utils/registry.sh:9-14`) |
| Orchestration | `docker compose` **≥ 2.2.3** | Version gate at `bin/roll:26-30`; v1 (`docker-compose`) is not supported |
| Container images | `ghcr.io/epartment/roll/*` | Built in a **separate repository** (`github.com/epartment/images`); overridable via `ROLL_IMAGE_REPOSITORY` |
| Reverse proxy | Traefik (`traefik:latest`) | File + Docker providers, HTTP→HTTPS redirect (`config/traefik/traefik.yml`) |
| DNS | dnsmasq via `ghcr.io/epartment/roll/dnsmasq` | `address=/.test/127.0.0.1`, upstream Cloudflare (`docker/docker-compose.yml:20-53`) |
| Mail catcher | `axllent/mailpit:latest` | Still named `mailhog` as a service and hostname (`docker/docker-compose.yml:55-63`) |
| DB tunnel | `panubo/sshd:latest` on `127.0.0.1:2222` | TCP forwarding only, key at `~/.roll/tunnel/ssh_key` |
| macOS file sync | Mutagen ≥ 0.11.8 | Only for `magento1`, `magento2`, `shopware` — see [Environments](#environments) |
| Documentation | Sphinx + MyST, published to GitHub Pages | `docs/`, built by `.github/workflows/pages.yml` |
| Distribution | Homebrew tap `epartment/roll/roll` | Release flow in `.github/workflows/tag-release.yml` → `push-release-to-brew.yml` |
| Lint | ShellCheck | `.github/workflows/shellcheck.yml`; the only CI test |

There is no build step, no dependency manifest, and no unit-test suite. `version` holds the version
string (`0.7.2`) and is rewritten by the release workflow.

## Getting started

### Supported platforms

**RollDev must work on both macOS and Linux.** That is a hard requirement, not a best-effort goal:
the tool is installed on developer machines (predominantly macOS) *and* on Linux hosts, including
unattended use where no one is present to work around a platform-specific failure (see
[FEATURE-REQUESTS.md](FEATURE-REQUESTS.md), whose entire scope is unattended Linux operation). A
change that works on only one of the two is not finished.

`loadRollConfig` enforces this at runtime: `utils/config.sh:353-369` maps `$OSTYPE` to
`ROLL_ENV_SUBT` and **fails outright on anything else** with
`Unsupported OSTYPE '<value>'`.

| Host | `ROLL_ENV_SUBT` | Status |
|---|---|---|
| macOS (Intel and Apple Silicon) | `darwin` | Fully supported |
| Linux | `linux` | Fully supported |
| Windows via WSL2 | `wsl` | Supported, but no `*.wsl.yml` fragment exists — see finding **M12** |
| Anything else | — | Rejected by `utils/config.sh:366` |

Windows is never a host in its own right; `roll` runs inside the WSL2 Linux distribution. Keep the
code on the WSL filesystem (`~/code/project`), not under `/mnt/c`, or file access is very slow.

Everything below is a real behavioural difference between the two required platforms, not a
cosmetic one. Anything touching these areas needs testing on both:

| Area | macOS (`darwin`) | Linux (`linux`) | Where |
|---|---|---|---|
| Bash version | 3.2.57 (system bash) | usually 5.x | Why the Bash 3.2 constraint exists; use `bash 3.2` compatible syntax only |
| File sync | Mutagen session, named volume for the web root | direct bind mount, no Mutagen | `environments/<type>/<type>.darwin.yml`, `commands/sync.cmd:33-35` (fatals off darwin) |
| `sed -i` | BSD — requires a backup suffix | GNU — suffix optional | Always use `sed_inplace` (`utils/core.sh:167`) |
| Network probe | `ping` (unreliable) | `ping` (unreliable) | `isOnline` probes `https://ghcr.io/v2/` with `curl -m 3` instead, avoiding platform flag differences and ICMP blockage |
| SSH agent socket | fixed host path `/run/host-services/ssh-auth.sock` | `${SSH_AUTH_SOCK}` from the host, and a socat proxy unless UID is 1000 | `environments/includes/php-fpm.darwin.yml` vs `.linux.yml`, `utils/config.sh:445-447` |
| `.test` DNS | automatic via `/etc/resolver/test` | manual — `roll install` only prints a warning | `commands/install.cmd:56-66` |
| Root CA trust | `security add-trusted-cert` | Fedora/CentOS and Debian/Ubuntu paths, with a warning naming the CA file on other distros | `commands/install.cmd:29-58` |
| tunnel key permissions | untouched | `chown root:root` on `ssh_key.pub`, because bind mounts are native | `commands/install.cmd:82-84` |
| Xdebug host | `host.docker.internal` | container gateway address, looked up at runtime | `commands/debug.cmd:13-21` |
| `mapfile` | absent (bash 3.2) | present | `commands/status.cmd:20-28` shows the required fallback |
| CI coverage | `macos-latest`: ShellCheck + Docker-free smoke | `ubuntu-latest`: ShellCheck + Docker-free smoke | `.github/workflows/shellcheck.yml` matrix |

Prerequisites: Docker (Desktop on macOS/Windows, Engine on Linux) with `docker compose` ≥ 2.2.3,
Homebrew, and [gum](https://github.com/charmbracelet/gum) ≥ 0.14.0, which backs every interactive
prompt. The Homebrew formula declares gum as a dependency, so a `brew install` pulls it in; on a
source checkout install it yourself (`brew install gum`, Charm's apt repository, `dnf`/`pacman`, or
a release binary — `roll install` prints the list and warns rather than failing). gum is needed
only for prompts: every one of them is also reachable by flag, environment variable or positional
argument, so scripted and CI use works without it. On macOS, Mutagen is installed automatically on
first `roll sync` if missing.

Install and start the shared services:

```bash
brew install epartment/roll/roll
```

```bash
roll svc up
```

The first `roll svc up` triggers `roll install` (via `assertRollDevInstall`, `utils/install.sh:43`),
which generates a local root CA under `~/.roll/ssl/rootca`, adds it to the system trust store, writes
`/etc/resolver/test` on macOS, generates the tunnel SSH keypair, and appends a `tunnel.roll.test`
block to `/etc/ssh/ssh_config`. Several of those steps need `sudo` and will prompt.

Initialise a project (run from the project root — the directory that will contain `.env.roll`):

```bash
roll env-init myproject magento2
```

```bash
roll env up
```

The project is then served at `https://app.myproject.test/`. Run RollDev from source instead of the
Homebrew copy with `./bin/roll <command>`.

### Running the CLI from source

`bin/roll` resolves its own real path through one level of symlink (`bin/roll:6-14`), which is what
makes the Homebrew symlink install work. Note the consequence: a project brought up by the installed
binary loads its YAML fragments from the Homebrew cellar, not from a checkout. Mixing the two on one
environment can produce a fragment set that does not match either copy.

## Architecture

### Dispatch

`bin/roll` is the single entry point. It sources four libraries in a fixed order — `utils/core.sh`,
`utils/config.sh`, `utils/registry.sh`, `utils/env.sh` — verifies Docker and the compose version, then
resolves the first argument through the command registry and **sources** the matching `.cmd` file
(`bin/roll:98`). Sourcing rather than executing is deliberate: every command runs in the same shell
and can use all globals and helper functions without re-deriving them.

Two consequences follow from `set -e` plus `trap ... ERR` at `bin/roll:2-3` applying to sourced
command bodies:

- A command that lets any statement return non-zero terminates the whole CLI. Commands that shell out
  to Docker therefore clear the trap with `trap '' ERR` before doing so (for example
  `commands/env.cmd:16`).
- Arithmetic idioms that return the arithmetic result as an exit status — `((i++))` evaluating to 0 —
  kill the process. Use `i=$((i + 1))`; the codebase does this consistently.

Argument handling splits into two modes. Commands listed in `ROLL_CMD_ANYARGS` (`bin/roll:43`) pass
every flag through untouched so it reaches `docker compose` or the in-container command; all others
collect positional arguments in `ROLL_PARAMS` and reject unknown flags.

### Command registry

Commands are discovered, never hardcoded. A command is a pair of files: `<name>.cmd` (the script) and
`<name>.help` (usage text, itself a sourced Bash file that sets `ROLL_USAGE`). `initializeRegistry`
(`utils/registry.sh:159`) scans a set of directories with numeric priorities, lower winning, so a user
or a project can override a built-in command by shadowing its name:

| Priority | Directory | Purpose |
|---|---|---|
| 1 | `${ROLL_ENV_PATH}/.roll/commands` | Project-local commands |
| 1 | `~/.roll/commands/<env-type>`, `~/.roll/reclu/<env-type>` | User commands scoped to one environment type |
| 2 | `${ROLL_DIR}/commands/<env-type>` | Built-in commands available only inside that environment type |
| 2 | `~/.roll/commands` | User commands |
| 3 | `~/.roll/reclu` | Third-party command packs |
| 4 | `${ROLL_DIR}/commands` | Built-ins |

`commands/magento2/` and `commands/wordpress/` use the env-type mechanism: `roll magento`,
`roll magepack`, `roll fixowns`, `roll mydumper` and friends simply do not exist outside a `magento2`
project, and `roll wp` only inside `wordpress`.

### Configuration

A project is identified by an `.env.roll` file. `locateEnvPath` (`utils/env.sh:4`) walks up from `pwd`
until it finds one defining both `ROLL_ENV_NAME` and `ROLL_ENV_TYPE`, and resolves the file if it is a
symlink — that is how a sub-stack points at a parent stack.

`utils/config.sh` holds the authoritative schema. `initConfigSchema` (`utils/config.sh:58`) declares
every recognised variable as `type:constraint`, where the constraint is `required`, `optional`, or a
literal default value. Loading proceeds in this order (`loadRollConfig`, `utils/config.sh:311`):

1. `~/.roll/.env.roll`, then legacy `~/.roll/.env` — global settings.
2. `${ROLL_ENV_PATH}/.env.roll` — project settings, overriding global.
3. OS detection sets `ROLL_ENV_SUBT` to `darwin`, `linux`, or `wsl`.
4. `assertValidEnvType` checks that `environments/<type>/<type>.base.yml` exists.
5. `applyEnvTypeDefaults` fills in what the environment type needs — the `magento2` service
   toggles, the non-`local` base services, the DB distribution version — but never overwrites a key
   the project set itself.
6. `setConfigDefault` fills in every schema key that still has no value and carries a literal
   default.
7. `applyVersionPinFallbacks` warns about every enabled service with no version pin and falls back
   to the version the project was already running.
8. `postProcessConfig` derives image variants (`ROLL_SVC_PHP_VARIANT`, `ROLL_SVC_PHP_NODE`), the
   Xdebug tag, and the nginx template name.

**The order matters.** Env-type defaults have to run before the schema literals, or every
`${VAR:-default}` in step 5 is unreachable — the literal has already given the key a value, and
`:-` only substitutes when unset or empty. Derivations that depend on final input values run last.

Every value is exported, so it reaches `docker compose` both through `--env-file .env.roll` and
through the process environment. Where the two disagree, the exported value wins, so the
`${...:-fallback}` defaults inside the YAML fragments are not the effective defaults; the service
version fallbacks have been removed from the fragments for that reason.

### How a compose invocation is assembled

`commands/env.cmd` is the core of the system. It reads the service toggles and, for each enabled one,
calls `appendEnvPartialIfExists` (`utils/env.sh:90`), which searches a fixed precedence chain and
appends `-f <file>` for **every** match found, so later files layer on top of earlier ones:

```
environments/includes/<name>.base.yml
environments/includes/<name>.<subtype>.yml        # subtype = darwin | linux | wsl
environments/<envtype>/<name>.base.yml
environments/<envtype>/<name>.<subtype>.yml
~/.roll/environments/…                            # same four, user overrides
```

Two further project-level overlays are appended last: `${ROLL_ENV_PATH}/.roll/roll-env.yml` and
`${ROLL_ENV_PATH}/.roll/roll-env.<subtype>.yml` (`commands/env.cmd:173-181`). The final command is:

```bash
docker compose --env-file .env.roll --project-directory <project> -p "$ROLL_ENV_NAME" -f … <params>
```

`ROLL_ENV_NAME` is therefore the Compose project name, which prefixes every container and named
volume. Renaming an environment silently orphans its volumes and brings up an empty database.

`env up` and `env down` also connect and disconnect the peered global services — `traefik`, `tunnel`,
`mailhog` (`utils/core.sh:5`) — into the project's network with `docker network connect`, because they
live in the `roll` Compose project and would otherwise be unreachable. Project networks are labelled
`dev.roll.environment.name`, which is how `roll status` and `roll svc up` enumerate them.

On macOS, `env.cmd` also drives the Mutagen session around the lifecycle: start on `up`, resume if
paused and the `php-fpm` container id is unchanged, pause on `stop`, terminate on `down`
(`commands/env.cmd:239-282`).

### Container exec

Every "run X in the container" command is a thin wrapper that ends in
`roll env exec -u www-data <container> …`, defaulting to `php-fpm` and overridable per project via
`ROLL_ENV_SHELL_CONTAINER`:

| Command | User | TTY | Notes |
|---|---|---|---|
| `roll shell`, `roll bash` | `www-data` | yes | Runs `ROLL_ENV_SHELL_COMMAND` (default `bash`) |
| `roll cli <cmd>` | `www-data` | yes | Arbitrary command |
| `roll clinotty <cmd>` | `www-data` | no (`-T`) | For scripted/piped use |
| `roll cliq <cmd>` | `www-data` | no | As `clinotty`, all output discarded |
| `roll root`, `roll rootnotty`, `roll rootshell` | `root` | per name | Same shape without `-u www-data` |
| `roll debug <cmd>` | `www-data` | yes | Targets `php-debug`, injects `XDEBUG_REMOTE_HOST` |
| `roll composer`, `roll node`, `roll npm`, `roll magerun` | `www-data` | yes | Named binary in the container |
| `roll magento <cmd>` | `www-data` | yes | `magento2` environments only |

### Global services

`roll svc` orchestrates the shared stack: Compose project name is always `roll`, project directory
`~/.roll`, network `roll`. Traefik terminates TLS for `*.test` using certificates from
`~/.roll/ssl/certs`; `svc up` regenerates `~/.roll/etc/traefik/dynamic.yml` from whatever certificates
are present, and signs one for `ROLL_SERVICE_DOMAIN` (default `roll.test`) if absent
(`commands/svc.cmd:54-84`). Portainer and a startpage are optional extra fragments.

## Module boundaries & coupling

RollDev is one Bash package rather than a set of deployable modules, so "component" here means a
directory-level unit with its own responsibility. The verdicts below are about whether that
responsibility is still describable.

| Component | Size | Stated responsibility | Verdict |
|---|---|---|---|
| `bin/roll` | 98 lines | Entry point, dispatch, argument parsing | **Coherent** |
| `utils/core.sh` | 184 lines | Messaging helpers, array/version utilities, network peering | **Coherent** — the three box-drawing functions are one-line wrappers around a shared `box` helper |
| `utils/config.sh` | 606 lines | Config schema, loading, validation, post-processing | **Coherent**; sole owner of configuration defaults |
| `utils/registry.sh` | 461 lines | Command discovery and priority resolution | **Oversized for what it delivers** — ~200 lines serve `roll registry`'s reporting subcommands; the metadata layer they report on is a stub (**M6**) |
| `utils/env.sh` | 108 lines | Env path location, partial precedence, env-type validation | **Coherent** |
| `utils/install.sh` | 63 lines | Host install assertion, SSH config | **Coherent** |
| `commands/env.cmd` | 286 lines | Assemble and run the compose invocation | **Coherent** — the one place that must know everything |
| `commands/backup.cmd`, `restore.cmd`, `restore-full.cmd`, `duplicate.cmd` | 3 929 lines — **57 % of all top-level command code** | Archive, restore, and clone an environment | **Oversized and redundant** — `restore.cmd` and `restore-full.cmd` are ~84 % identical (**M4**) |
| `commands/magento2-init.cmd` | 784 lines | Scaffold a Magento 2 project | **Oversized** — a project generator living in a command file |
| `commands/*.cmd` (wrappers) | 5–25 lines each | One `roll env exec` invocation | **Coherent** |
| `commands/magento2/`, `commands/wordpress/` | 344 lines / 11 lines | Env-type-specific commands | **Coherent**; `commands/magento1/` and both `usage.help`-only directories contain no commands |
| `environments/includes/` | 20 fragments | One service each | **Coherent** |
| `environments/<type>/` | 11 types | Per-type overrides and seeds | **Coherent** — each type has an `init.env` (or documents why it doesn't), and `local` is properly documented |
| `docker/`, `config/` | 290 lines | Shared-services compose and Traefik/OpenSSL config | **Coherent** |
| `docs/` | 3 666 lines / 31 pages | User documentation | **Coherent**, drifting from the code (**M5**) |

### Real coupling map

The declared structure — `bin/roll` sources four libraries, then sources one command — is the easy
part. These are the couplings that are not visible from it:

| A | B | Mechanism | What breaks if separated |
|---|---|---|---|
| `commands/backup.cmd` | `commands/restore.cmd`, `commands/restore-full.cmd` | Undocumented on-disk contract: the staging directory `<cwd>/.roll/backups`, the archive layout, and the metadata JSON. Each file re-derives the path independently (documented in a comment at `commands/backup.cmd:22-35`) | Changing the layout in one file silently breaks the others; `restore-full.cmd` never loads the env config at all, so it resolves paths differently |
| `commands/status.cmd:6` | `docker/docker-compose.yml` | The shared network name is recovered by `grep -A3 'networks:' … \| tail -n1 \| sed`, i.e. by text-parsing YAML | Reordering keys in `docker-compose.yml` breaks `roll status`'s "is RollDev running" check |
| `environments/includes/redis.base.yml` | `environments/includes/dragonfly.base.yml` | Both define a service literally named `redis`; Dragonfly only swaps the image and volume | Correct as written — it is what lets `roll redis` work either way — but it forces the mutual-exclusion guard at `commands/env.cmd:12-14` |
| `commands/env.cmd:116-120` | `commands/browsersync.cmd` | `env up` shells back out to `roll browsersync freeport` to pick host ports before assembling the compose args | A circular dependency between two commands, evaluated on every `up` with browsersync enabled |
| `docs/index.md:7` | `README.md` | Sphinx `include` with `end-before: <!-- include_open_stop -->` | The marker was missing before this revision, so the docs home page inlined the entire README (**M5**) |

Two couplings that look wrong but are not: `commands/*.cmd` wrappers re-invoking `${ROLL_DIR}/bin/roll`
as a subprocess is a deliberate choice (a sourced command cannot cleanly re-enter dispatch), and the
`traefik`/`tunnel`/`mailhog` network peering in `utils/core.sh` has to be imperative because the two
Compose projects cannot declare each other's networks.

### Boundary findings

#### High

None. No component in this repository has an unclear owner or a circular library dependency; the
boundary problems below all cost maintenance time rather than correctness.

#### Medium

**MB1. The backup/restore/duplicate family has no shared library** — `commands/backup.cmd`,
`commands/restore.cmd`, `commands/restore-full.cmd`, `commands/duplicate.cmd`

- *What:* Four command files totalling 3 929 lines — 57 % of all top-level command code — with no
  extracted helpers. `restore.cmd` and `restore-full.cmd` differ in only 339 of ~2 123 lines
  (measured with `diff` after trimming trailing whitespace); 17 of their 19 function names are
  identical. `promptPassword`, `showProgress` and `logMessage` exist in all four; `promptPassword` is
  byte-identical between `restore.cmd` and `restore-full.cmd` and differs slightly in the other two.
- *Why it matters:* Every fix has to be applied up to four times, and the three near-copies of
  `promptPassword` prove that it is not being done. The archive layout contract lives only in prose
  comments, so a change to the staging path in one file leaves the others looking for backups
  elsewhere — a failure mode the comment at `commands/backup.cmd:22-35` already warns about.
- *Suggested fix:* Extract a `utils/backup.sh` sourced by all four, holding the shared primitives
  (`promptPassword`, `showProgress`, `logMessage`, `logVerbose`, `detectEncryptedBackup`,
  `findLatestBackup`, `extractBackupArchive`, `validateBackup`, `getBackupMetadata`,
  `getVolumeMapping`, `restoreVolume`) plus one function that resolves the staging directory, so the
  path contract has exactly one definition. Then collapse `restore-full.cmd` into `restore.cmd`
  behind a `--include-source` flag mirroring `backup.cmd`'s existing `--include-source`, and keep
  `restore-full` as a two-line alias for backwards compatibility. `utils/` is already sourced from
  `bin/roll`, so a fifth library needs one line there.

## Environments

`roll env-init <name> <type>` writes `.env.roll` with five base lines and appends
`environments/<type>/init.env`, expanding `$ROLL_ENV_NAME` and `$GENERATED_APP_KEY` through `envsubst`
(`commands/env-init.cmd:39-53`). The available types and what each actually provides:

| Type | `init.env` | Mutagen (macOS) | Notable defaults from `init.env` |
|---|---|---|---|
| `magento2` | yes | yes | PHP 8.3, Node 22, MariaDB 10.4, ES 8.11, Varnish 7.0, RabbitMQ 3.9, Redis 6.2, `ROLL_INCLUDE_GIT=1` |
| `magento1` | yes | yes | PHP 7.2, Node 12, Composer 1, MariaDB 10.3 |
| `shopware` | yes | yes | PHP 7.4, Node 12, MariaDB 10.4 |
| `laravel` | yes | **no** | PHP 8.3, Node 22, Redis + RedisInsight, seeds `APP_KEY`, `DB_*`, `REDIS_*` |
| `akeneo` | yes | **no** | PHP 7.4, MySQL 8.0, Elasticsearch on |
| `symfony` | yes | **no** | PHP 7.4, Node 12, MariaDB 10.4 |
| `typo3` | yes | **no** | PHP 7.4, Node 12, MariaDB 10.4 |
| `wordpress` | yes | **no** | PHP 7.4, Composer 1, seeds `DB_*`; PHP image variant is `php-fpm-wordpress` |
| `php` | yes | **no** | PHP 8.1, `ROLL_DB=0` |
| `vuejs` | **no** | **no** | Routes `app.` to nginx and `watch.app.` to port 8080 on `php-fpm` |
| `local` | **no** | **no** | Network-only environment; bring your own `.roll/roll-env.yml` |

Without a Mutagen configuration, macOS falls back to the bind mount from
`environments/includes/php-fpm.base.yml` (`.:/var/www/html:cached`), which works but is markedly
slower for large codebases; `roll sync` refuses to run for those types
(`commands/sync.cmd:40-42`). On Linux and WSL all types bind-mount directly and Mutagen is never used.

For the three synced types, `environments/<type>/<type>.darwin.yml` replaces the bind mount with a
named volume (`appdata:/var/www/html`) and re-mounts only `pub/media` from the host. Two consequences
worth knowing: `var/` and `pub/static/` are excluded from the sync
(`environments/magento2/magento2.mutagen.yml`), so files written there by the host are not visible in
the container; and `ignore.vcs: true` strips `.git` at every depth, which is why `ROLL_INCLUDE_GIT=1`
exists to re-mount the repository root's `.git` explicitly
(`environments/includes/git.base.yml`).

### Service toggles

Registered in `utils/config.sh:70-87`. Each enabled toggle appends the matching fragment from
`environments/includes/`.

| Toggle | Schema default | Service | Exposed at |
|---|---|---|---|
| `ROLL_NGINX` | 1 | nginx | `https://<sub>.<domain>` (priority 2) |
| `ROLL_DB` | 1 | `mariadb` or `mysql` per `DB_DISTRIBUTION` | `db:3306` internally, or via the SSH tunnel |
| `ROLL_REDIS` | 1 | redis | `redis:6379` |
| `ROLL_DRAGONFLY` | 0 | Dragonfly **as the `redis` service** | `redis:6379`; mutually exclusive with `ROLL_REDIS` |
| `ROLL_VARNISH` | 0 | varnish in front of nginx | takes over the host route (priority 1) and sets `traefik.enable=false` on nginx |
| `ROLL_ELASTICSEARCH` | 0 | elasticsearch | `https://elasticsearch.<domain>` |
| `ROLL_OPENSEARCH` | 0 | opensearch | `https://opensearch.<domain>` |
| `ROLL_ELASTICVUE`, `ROLL_REDISINSIGHT` | 0 | web UIs | own subdomains |
| `ROLL_RABBITMQ` | 0 | rabbitmq | `https://rabbitmq.<domain>` (management UI) |
| `ROLL_MONGODB` | 0 | mongodb | `mongodb:27017` |
| `ROLL_BROWSERSYNC` | 0 | ports published **on `php-fpm`** | the only fragment in `environments/` that publishes host ports |
| `ROLL_SELENIUM`, `ROLL_SELENIUM_DEBUG`, `ROLL_ALLURE` | 0 | test infrastructure | `roll vnc` for the debug VNC session |
| `ROLL_TEST_DB` | 0 | `tmp-mysql` on tmpfs (MySQL 5.7, hardcoded) | Magento integration tests |
| `ROLL_MAGEPACK` | 0 | Magepack bundling | `magento2` only |
| `ROLL_INCLUDE_GIT` | 0 | bind-mounts `.git` into the container | needed on macOS with Mutagen |

For a `magento2` project `ROLL_VARNISH`, `ROLL_ELASTICSEARCH` and `ROLL_RABBITMQ` default to `1`
via `applyEnvTypeDefaults` in `utils/config.sh`, whether or not `init.env` spelled them out. A
value in `.env.roll` still wins.

### Local, test/staging, and production

RollDev is a local-development tool only; nothing here deploys. The one production-shaped concern it
carries is that the images it references are published from a separate repository, so the version of
an image a project gets depends on the tag in `.env.roll` and on what has been pushed to
`ghcr.io/epartment/roll`, not on anything in this checkout.

## Common tasks

Bring up the shared services (needed once per host boot):

```bash
roll svc up
```

Show every running environment and the state of the shared services:

```bash
roll status
```

Show one environment's services, URLs and versions as a table:

```bash
roll env describe
```

Start, stop, and restart the environment in the current project:

```bash
roll env up
```

```bash
roll env down
```

```bash
roll restart
```

Open a shell in the `php-fpm` container as `www-data`:

```bash
roll shell
```

Run a command in the container without a TTY (for scripts and pipes):

```bash
roll clinotty php bin/magento cache:flush
```

Open a SQL prompt on the project's database:

```bash
roll db connect
```

Import a dump, rewriting `DEFINER` clauses and stripping `GTID_PURGED`/`SQL_LOG_BIN` statements:

```bash
roll db import < dump.sql
```

Add a PHP extension to both the `php-fpm` and `php-debug` containers at runtime:

```bash
roll add-php-ext redis
```

Sign a wildcard certificate for extra hostnames (needed for multi-store setups):

```bash
roll sign-certificate example.test
```

Archive an environment's volumes and configuration:

```bash
roll backup
```

Clone an environment under a new name and domain:

```bash
roll duplicate
```

Inspect the resolved configuration for the current project:

```bash
roll config show
```

List every command the registry resolved, including user and third-party packs:

```bash
roll registry list
```

Lint the shell sources exactly as CI does:

```bash
shellcheck commands/*.cmd utils/*.sh
```

Build the documentation locally:

```bash
pip install -r docs/requirements.txt
```

```bash
sphinx-build -b html docs docs/_build/html
```

## Machine interface

Everything RollDev does is reachable without a terminal, so it can be driven from CI, a deploy
script, the build server, or an AI assistant. The user-facing guide is
[docs/machine-interface.md](docs/machine-interface.md); this is the contributor summary of what
exists and where it lives.

| Surface | Where |
|---|---|
| `--format json` on `status`, `env describe`, `registry list`, `env doctor` | the respective `.cmd` files; values escaped through `jsonEscape` in `utils/core.sh` |
| `roll has-command <name>` — exit 0/1, no output | `commands/has-command.cmd`, resolves through the registry so add-on commands count |
| `roll env up --wait` | Compose native, made meaningful by the healthchecks in `environments/includes/*.base.yml` |
| `roll env doctor` | `commands/doctor.cmd` |
| `roll config check-pins` / `fix-pins` | `commands/config.cmd` |
| Flag-first prompts | `utils/interact.sh` |

Two rules bind anything added here:

1. **Machine-readable output carries no secrets and no ANSI**, and every value goes through
   `jsonEscape` rather than being concatenated raw.
2. **A prompt is never the only route to a value.** Flags and environment variables come first, gum
   runs only on a TTY, and with no terminal the prompt fails naming the flag that would have
   answered it — so an unattended run cannot hang. `.github/scripts/test-interact.sh` asserts this
   and runs in the smoke suite on both platforms.

Note that giving a command a `--flag` means adding it to `ROLL_CMD_ANYARGS` in `bin/roll`, which
changes how `--help` reaches it: roll stops parsing at the first dash and leaves `ROLL_PARAMS`
empty. Such a command must render its own help by sourcing `commands/usage.cmd`, never by
re-invoking `roll <self> --help`, which recurses until killed.
`.github/scripts/test-syntax.sh` enforces this.

## Conventions

These are enforced by review rather than by tooling, except where noted.

- **Every change must work on macOS and Linux.** Both are first-class targets — see
  [Supported platforms](#supported-platforms) for the table of real behavioural differences. CI runs
  a `macos-latest` + `ubuntu-latest` matrix (ShellCheck plus the Docker-free smoke script,
  `.github/scripts/smoke.sh`), but the smoke set only covers commands that need neither a project
  checkout nor a running daemon — anything touching `roll env`/service containers is still on the
  author: run the affected command under `/bin/bash` on macOS before merging. The recurring traps
  are bash 3.2, BSD vs GNU flag semantics (`sed`, `ping`, `stat`), Mutagen-vs-bind-mount file sync,
  and the SSH agent socket path.
- **Bash 3.2 only.** No associative arrays, no `${var^}`/`${var,}` case modification, no `mapfile`
  without a fallback (`commands/status.cmd:20-28` shows the pattern). macOS ships bash 3.2.57 and
  `bin/roll` runs under `#!/usr/bin/env bash`, so a bash-4 construct fails there while passing on
  Linux CI.
- **Every `.cmd` and util script starts with the guard**
  `[[ ! ${ROLL_DIR} ]] && >&2 echo … && exit 1`. All 50 command files currently carry it (verified).
  Scripts are meant to be sourced by `bin/roll`, never run directly.
- **Use the messaging helpers** from `utils/core.sh` — `fatal`, `error`, `warning`, `info`, `success`,
  `boxinfo`, `boxsuccess`, `boxerror` — rather than raw `echo`, so output stays consistent and goes to
  stderr.
- **Gate OS-specific logic on `$OSTYPE`** (`darwin*` vs Linux) and use `sed_inplace`
  (`utils/core.sh:167`) instead of `sed -i`, which differs between BSD and GNU. Prefer
  `${ROLL_ENV_SUBT}` where the config has already been loaded, since it also distinguishes `wsl`.
  When adding an OS-specific YAML fragment, remember that `wsl` gets neither the `.darwin.yml` nor
  the `.linux.yml` variant (finding **M12**).
- **Arithmetic:** `x=$((x + 1))`, never `((x++))` — see [Dispatch](#dispatch).
- **Adding a command:** create `commands/<name>.cmd` + `commands/<name>.help`; the registry picks it
  up with no central list to edit. If it must accept arbitrary pass-through flags, add it to
  `ROLL_CMD_ANYARGS` in `bin/roll:43`. Add it to `commands/usage.help` as well — that file is
  maintained by hand for visibility.
- **Adding a service:** add the fragment(s) under `environments/includes/` (plus per-type overrides),
  wire a `ROLL_<SERVICE>` toggle into the assembly block in `commands/env.cmd`, and register the
  variable and its default in `initConfigSchema` (`utils/config.sh:58`). Do not rely on a
  `${VAR:-default}` fallback inside the YAML — the schema default is exported and wins.
- **Container images:** anything requiring a binary, package or PHP extension to exist *inside* a
  container belongs in the separate images repository (`github.com/epartment/images`), not here.
- **Documentation:** user-facing docs live in `docs/` and publish to GitHub Pages on push to `main`.
  Update them in the same change as the behaviour they describe.
- **Releases:** run the `Tag Release` workflow with a version; it writes `version`, commits to `main`,
  tags, and opens a draft release. Publishing the release triggers `push-release-to-brew.yml`, which
  regenerates the Homebrew formula in `epartment/homebrew-roll`.
- **Known gaps found while running the stack unattended** are recorded in
  [FEATURE-REQUESTS.md](FEATURE-REQUESTS.md) with severities and citations. Read it before proposing
  improvements — its numbering (`H1`, `M1`, …) is independent of this file's.

## Known issues & improvement points

Defects found by reading the source at version 0.7.2. Items marked **verified** were reproduced or
confirmed against a running container during this review; the rest were read from the code. Numbering
here is independent of [FEATURE-REQUESTS.md](FEATURE-REQUESTS.md), which covers missing capabilities
rather than defects, and of the [boundary findings](#boundary-findings) above.

### High

**H1. A restored search-engine volume is unwritable, so Elasticsearch cannot start** —
`utils/backup.sh` (`restoreVolume`)

- *What:* After `roll restore`, the Elasticsearch data volume comes back with its **root directory
  owned by uid 0, mode 755**, while the image runs as uid 1000. The service then dies at boot with
  `AccessDeniedException: /usr/share/elasticsearch/data/.es_temp_file` and
  `failed to test writes in data directory ... write permission is required`. Entries *inside* the
  volume keep their original ownership (`_state` is uid 1000), so only the top-level directory
  created during extraction is wrong.
- *Verified:* full round trip on a throwaway magento2 project — write a marker row, `roll backup`,
  drop the table, `roll restore`, `roll env up --wait`. The database restores correctly and the
  marker comes back; Elasticsearch exits 1 every time.
- *Why it matters:* the restore reports success, and before this release `roll env up` also
  returned 0, so the environment looked fine and only failed later when something searched. It is
  `env up --wait` plus the new healthchecks that make it visible at all — `--wait` correctly exits
  1 here, which is how this was found.
- *Not caused by the shared-library extraction:* `restoreVolume` moved verbatim, and the same
  failure reproduces on the pre-refactor code.
- *Suggested fix:* after extracting a volume, restore the ownership the service expects rather than
  leaving the extraction root as root. The uid differs per service, so it belongs alongside
  `getVolumeMapping` as a per-service property rather than as a blanket `chown`.

### Medium

**M4. `restore.cmd` and `restore-full.cmd` are near-identical copies** — see boundary finding
[**MB1**](#boundary-findings) for the measurement and the suggested split.

**M5. The published documentation home page inlines the whole README** — `docs/index.md:7`

- *What:* `docs/index.md` includes `../README.md` with `end-before: <!-- include_open_stop -->`.
  **Verified:** before this revision no such marker existed anywhere in the repository, so MyST had
  nothing to stop at and the entire README — installation instructions, command list, licence, links —
  was rendered above the docs home page's own "Features" section and table of contents. This revision
  adds the marker after the opening paragraph.
- *Why it matters:* The docs home page duplicated the README's installation section immediately above
  its own link to `installing`, and any README growth landed on the published site unreviewed.
- *Suggested fix:* Already addressed by the marker. Keep it: anything below
  `<!-- include_open_stop -->` in this file is repository-facing and does not appear on the site. If
  the include ever needs to cover more, move the marker rather than removing it.

### Low

## Audited and clean

Checked during this review and found correct, so the next reader does not re-investigate:

- **The sourcing guard is universal.** All 50 `.cmd` files under `commands/` (including the env-type
  subdirectories) carry the `[[ ! ${ROLL_DIR} ]]` guard. An earlier suspicion that the newer commands
  had skipped it was a measurement error.
- **Cross-platform gating is otherwise applied consistently.** Every OS-specific code path found
  branches on `$OSTYPE` or `${ROLL_ENV_SUBT}` rather than assuming a platform: `sed_inplace`
  (`utils/core.sh:167`) handles the BSD/GNU `sed -i` difference, `commands/sync.cmd:33-35` refuses to
  run off darwin instead of failing obscurely, `commands/debug.cmd:13-21` resolves the Xdebug host
  per platform, `commands/status.cmd:20-28` guards `mapfile`, and `commands/tableplus.cmd` and
  `commands/vnc.cmd` are correctly macOS- and Linux-specific respectively. `isOnline` now probes
  with `curl` instead of `ping`, avoiding platform flag differences. The missing `wsl` fragment
  (**M12**) is handled correctly.
- **Bash 3.2 compliance.** The parallel-indexed-array pattern in `utils/config.sh` and
  `utils/registry.sh` is applied consistently; no associative arrays anywhere. `commands/status.cmd`
  correctly guards its `mapfile` use with a `while read` fallback. Case modification is always done
  via `tr` or the `capitalize` helper function.
- **Arithmetic increments.** No bare `((x++))` remains in `commands/` or `utils/`; the codebase uses
  `x=$((x + 1))`, which is what keeps `set -e` from killing the CLI mid-command.
- **`roll redis` works with Dragonfly.** `environments/includes/dragonfly.base.yml` defines the
  service as `redis` with the Dragonfly image, so `commands/redis.cmd:17`'s lookup of the `redis`
  service succeeds under either backend. The mutual-exclusion guard at `commands/env.cmd:12-14` is
  the necessary consequence, not a bug.
- **`roll db connect` and `roll db import` survive MariaDB 11.** The `mysql` client symlink is still
  present in `ghcr.io/epartment/roll/mariadb:11.4` (verified in a running container); only
  `mysqldump` was removed, which is why **H2** is scoped to `dump` alone.
- **`NGINX_TEMPLATE` derivation works.** It is declared `string:optional`, so `setConfigDefault`
  never fills it in and the `${NGINX_TEMPLATE:-…}` chains in `postProcessConfig` resolve as
  written. The apparently redundant trailing `export` lines in the `magento1`/`magento2` blocks are
  harmless because `:-` preserves the value set by the branch above.
- **Compose fragment layering.** `appendEnvPartialIfExists` appends rather than replaces, and Compose
  merges list-valued keys by target path, so `environments/magento2/magento2.darwin.yml`'s
  `appdata:/var/www/html` correctly supersedes the bind mount from
  `environments/includes/php-fpm.base.yml` on macOS. This is the mechanism behind the Mutagen setup,
  not an accident.
- **No secrets in the repository.** The only credentials present are the local development defaults
  (`app`/`app`, `magento`/`magento` in `environments/includes/db.base.yml` and
  `environments/magento2/db.base.yml`) and the documented VNC password in `commands/vnc.cmd`. No
  tokens, keys or customer data. `.gitignore` covers `.idea/`, and no IDE files are tracked.
- **Release plumbing is consistent.** `version` (0.7.2), `commands/version.cmd`, the `Tag Release`
  workflow and the Homebrew formula update form a closed loop with no hardcoded version elsewhere.

Not systematically recorded for this review: the internal logic of `commands/backup.cmd`,
`commands/restore.cmd`, `commands/restore-full.cmd`, `commands/duplicate.cmd`,
`commands/magento2-init.cmd` and `commands/multistore.cmd` beyond their structure and interfaces —
together roughly 4 900 lines. Their boundary problems are recorded above; their internals were not
line-audited, and neither backup nor restore was executed against a live environment.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Unsupported OSTYPE '…'` | Only macOS and Linux (including WSL2) are supported hosts | See [Supported platforms](#supported-platforms); on Windows run `roll` inside WSL2, never in PowerShell or Git Bash |
| `Environment config could not be found` | No `.env.roll` in the current directory or any parent | Run `roll env-init <name> <type>` from the project root |
| `docker compose version should be 2.2.3 or higher` | Compose v1, or the plugin is missing | Install the Compose v2 plugin; `docker-compose` (hyphenated) is not used |
| `invalid project name "…"` from `roll env up` | `ROLL_ENV_NAME` contains uppercase or an illegal character | Lowercase it in `.env.roll`; note the rename orphans the old volumes |
| Environment comes up on an empty database after a rename | `ROLL_ENV_NAME` is the Compose project name and prefixes every named volume | Bring the environment down, copy `oldname_dbdata` to `newname_dbdata`, bring it up |
| `port is already allocated` on `php-fpm` | `ROLL_BROWSERSYNC=1` publishes fixed host ports on that service — the only fragment that publishes any | Set `ROLL_BROWSERSYNC=0`; verify with `roll env config \| grep published`. See `FEATURE-REQUESTS.md` H2 |
| A command run right after `roll env up` fails to connect to the DB or search engine | No fragment declares a `healthcheck:` and `up` does not pass `--wait`, so it returns when containers *start* | Retry with a wait loop against the service. See `FEATURE-REQUESTS.md` H1 |
| `Mutagen sync sessions are not used on "linux" host environments` | `roll sync` is macOS-only | Expected; Linux and WSL bind-mount directly |
| `Mutagen configuration does not exist for environment type "…"` | Only `magento1`, `magento2` and `shopware` ship a `.mutagen.yml` | Expected; that type uses a bind mount on macOS too |
| In-container `composer install` reports a missing `.git` in a `vendor/` package | Mutagen's `ignore.vcs: true` strips `.git` at every depth, so source installs have no checkout | Remove the affected `vendor/` directories and re-run `composer install` to force dist installs |
| Files written to `var/` or `pub/static/` on the host are invisible in the container | Both paths are excluded from the Mutagen session | Write through the container (`roll cli`), or `docker cp` into the volume |
| A `roll` subcommand exits 1 printing only its opening `INFO:` lines, on Linux but not macOS | `set -e` plus a statement returning non-zero — classically a bare `((x++))` from 0 — kills the sourced command, and the `ERR` trap is not inherited by functions | Use `x=$((x + 1))`; see [Dispatch](#dispatch) |
| Browser does not trust `*.test` certificates | The root CA was not added, or the browser has its own store | Import `~/.roll/ssl/rootca/certs/ca.cert.pem`; Firefox and Chrome-on-Linux need it added manually |
| `*.test` hostnames do not resolve | dnsmasq is not running, or the resolver is not configured | `roll svc up`; on macOS check `/etc/resolver/test`, on Linux and Windows configure DNS manually — see `docs/configuration/dns-resolver.md` |
| `roll status` says RollDev is not running while containers are up | The shared network name is recovered by text-parsing `docker/docker-compose.yml` | Check that `networks.default.name: roll` is still within three lines of `networks:` in that file |

Full user documentation: [epartment.github.io/rolldev](https://epartment.github.io/rolldev) (sources
in `docs/`). Container images: [github.com/epartment/images](https://github.com/epartment/images).
Issues: [github.com/epartment/rolldev/issues](https://github.com/epartment/rolldev/issues).

## Licence

MIT — see [LICENSE](LICENSE).
