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

> The repository's only automated test — `shellcheck commands/*.cmd utils/*.sh`, run by
> `.github/workflows/shellcheck.yml` — currently **fails** (6 errors, 111 warnings, 95 notes as of
> version 0.7.2), so it provides no regression signal. `roll db dump` is also broken against the
> MariaDB 11.x images that are in active use. Both are recorded in
> [Known issues & improvement points](#known-issues--improvement-points) as **H1** and **H2**.

## Contents

- [Stack](#stack)
- [Getting started](#getting-started)
- [Architecture](#architecture)
- [Module boundaries & coupling](#module-boundaries--coupling)
- [Environments](#environments)
- [Common tasks](#common-tasks)
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
| Bash version | 3.2.57 (system bash) | usually 5.x | Why the Bash 3.2 constraint exists; a bash-4 construct fails only on macOS (**H3**) |
| File sync | Mutagen session, named volume for the web root | direct bind mount, no Mutagen | `environments/<type>/<type>.darwin.yml`, `commands/sync.cmd:33-35` (fatals off darwin) |
| `sed -i` | BSD — requires a backup suffix | GNU — suffix optional | Always use `sed_inplace` (`utils/core.sh:167`) |
| `ping` flags | `-t` is a **timeout** | `-t` is the **TTL** | `isOnline` (`utils/core.sh:161`) is wrong on Linux — finding **M11** |
| SSH agent socket | fixed host path `/run/host-services/ssh-auth.sock` | `${SSH_AUTH_SOCK}` from the host, and a socat proxy unless UID is 1000 | `environments/includes/php-fpm.darwin.yml` vs `.linux.yml`, `utils/config.sh:445-447` |
| `.test` DNS | automatic via `/etc/resolver/test` | manual — `roll install` only prints a warning | `commands/install.cmd:56-66` |
| Root CA trust | `security add-trusted-cert` | Fedora/CentOS and Debian/Ubuntu paths only; other distros silently skipped | `commands/install.cmd:29-52`, finding **L10** |
| tunnel key permissions | untouched | `chown root:root` on `ssh_key.pub`, because bind mounts are native | `commands/install.cmd:82-84` |
| Xdebug host | `host.docker.internal` | container gateway address, looked up at runtime | `commands/debug.cmd:13-21` |
| `mapfile` | absent (bash 3.2) | present | `commands/status.cmd:20-28` shows the required fallback |
| CI coverage | **none** | `ubuntu-latest` | All five workflows; finding **M10** |

Prerequisites: Docker (Desktop on macOS/Windows, Engine on Linux) with `docker compose` ≥ 2.2.3, and
Homebrew. On macOS, Mutagen is installed automatically on first `roll sync` if missing.

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
4. `setConfigDefault` fills in every schema key that has a literal default and is not yet set.
5. `assertValidEnvType` checks that `environments/<type>/<type>.base.yml` exists.
6. `postProcessConfig` derives image variants (`ROLL_SVC_PHP_VARIANT`, `ROLL_SVC_PHP_NODE`), the
   Xdebug tag, and the nginx template name.

Step 4 running before step 6 is the root cause of finding **M1** below: any `${VAR:-default}`
expression in step 6 (or in `commands/env.cmd`) is unreachable for a key that has a literal schema
default, because step 4 already gave it a value.

Every value is exported, so it reaches `docker compose` both through `--env-file .env.roll` and
through the process environment. Where the two disagree, the exported value wins — which is why the
`${...:-fallback}` defaults written inside the YAML fragments are mostly dead (finding **M2**).

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
| `utils/core.sh` | 184 lines | Messaging helpers, array/version utilities, network peering | **Coherent** — the three box-drawing functions are near-identical triplets (finding **L4**) |
| `utils/config.sh` | 606 lines | Config schema, loading, validation, post-processing | **Coherent**, but owns defaults that `commands/env.cmd` also owns (**M1**) |
| `utils/registry.sh` | 461 lines | Command discovery and priority resolution | **Oversized for what it delivers** — ~200 lines serve `roll registry`'s reporting subcommands; the metadata layer they report on is a stub (**M6**) |
| `utils/env.sh` | 108 lines | Env path location, partial precedence, env-type validation | **Coherent** |
| `utils/install.sh` | 63 lines | Host install assertion, SSH config | **Coherent** |
| `commands/env.cmd` | 286 lines | Assemble and run the compose invocation | **Coherent** — the one place that must know everything |
| `commands/backup.cmd`, `restore.cmd`, `restore-full.cmd`, `duplicate.cmd` | 3 929 lines — **57 % of all top-level command code** | Archive, restore, and clone an environment | **Oversized and redundant** — `restore.cmd` and `restore-full.cmd` are ~84 % identical (**M4**) |
| `commands/magento2-init.cmd` | 784 lines | Scaffold a Magento 2 project | **Oversized** — a project generator living in a command file |
| `commands/*.cmd` (wrappers) | 5–25 lines each | One `roll env exec` invocation | **Coherent** |
| `commands/magento2/`, `commands/wordpress/` | 344 lines / 11 lines | Env-type-specific commands | **Coherent**; `commands/magento1/` and both `usage.help`-only directories contain no commands |
| `environments/includes/` | 20 fragments | One service each | **Coherent** |
| `environments/<type>/` | 11 types | Per-type overrides and seeds | **Shell** for `local` (`environments/local/local.base.yml` is a 0-byte file) and thin for `vuejs` (no `init.env`) — see **L5** |
| `docker/`, `config/` | 290 lines | Shared-services compose and Traefik/OpenSSL config | **Coherent** |
| `docs/` | 3 666 lines / 31 pages | User documentation | **Coherent**, drifting from the code (**M5**, **L1**) |

### Real coupling map

The declared structure — `bin/roll` sources four libraries, then sources one command — is the easy
part. These are the couplings that are not visible from it:

| A | B | Mechanism | What breaks if separated |
|---|---|---|---|
| `utils/config.sh` (`postProcessConfig`) | `commands/env.cmd:24-105` | The **same** env-type defaulting logic is written twice, in full: PHP/Node image variants, DB distribution version, Xdebug tag, nginx template, `CHOWN_DIR_LIST`, magento1/magento2 service toggles | Nothing breaks — they already disagree. `env.cmd`'s copy is dead for keys with literal schema defaults, so the two produce different results depending on which keys `.env.roll` sets (**M1**) |
| `utils/config.sh` schema defaults | `environments/**/*.yml` `${VAR:-fallback}` | Config exports a value for every key with a literal default, so the YAML fallback never applies | The YAML fallbacks read as the effective default and are not; eight of them disagree with the schema (**M2**) |
| `commands/backup.cmd` | `commands/restore.cmd`, `commands/restore-full.cmd` | Undocumented on-disk contract: the staging directory `<cwd>/.roll/backups`, the archive layout, and the metadata JSON. Each file re-derives the path independently (documented in a comment at `commands/backup.cmd:22-35`) | Changing the layout in one file silently breaks the others; `restore-full.cmd` never loads the env config at all, so it resolves paths differently |
| `commands/status.cmd:6` | `docker/docker-compose.yml` | The shared network name is recovered by `grep -A3 'networks:' … \| tail -n1 \| sed`, i.e. by text-parsing YAML | Reordering keys in `docker-compose.yml` breaks `roll status`'s "is RollDev running" check |
| `commands/describe.cmd:18`, `commands/vnc.cmd:12` | Compose container naming | Both reconstruct container names by string concatenation instead of asking `roll env ps -q` — and they disagree: `describe` uses v2 (`name-svc-1`), `vnc` uses v1 (`name_svc_1`) | `roll vnc` cannot find a container under the Compose v2 that `bin/roll:26` requires (**M8**) |
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

**MB2. `roll registry`'s reporting layer describes metadata that is never collected** —
`utils/registry.sh:68-92`

- *What:* `extractCommandMetadata` is a stub: the `description` branch returns an empty string and
  the `category` branch returns the constant `general`, both with a `# Simple approach - just return
  empty for now` comment. Roughly 200 lines of `utils/registry.sh` and `commands/registry.cmd` exist
  to filter, group, count and export those two fields.
- *Why it matters:* `roll registry list`, `search`, `categories`, `stats`, `info` and `export` all
  report a single category (`global`) and blank descriptions, so `roll registry stats` on a stock
  install prints `global : 48 commands` and nothing else useful. The `.help` files that would supply
  the descriptions already exist and are already located by the registry.
- *Suggested fix:* Either implement the extraction — parse a `## @description:` / `## @category:`
  comment header from the `.help` file, which requires adding those headers to the 40 built-in help
  files — or delete the category and description arrays and the subcommands that consume them,
  keeping `list`, `info`, `paths`, `validate` and `export`. The half-built version is worse than
  either: it makes the CLI look as though the feature works.

#### Low

**LB1. `commands/magento2-init.cmd` is a project generator inside a command file** — 784 lines

- *What:* The largest non-backup command scaffolds a full Magento 2 project: version resolution,
  Composer authentication, `env-init`, `env up`, installation, sample data.
- *Why it matters:* It duplicates decisions that `commands/env-init.cmd` and
  `environments/magento2/init.env` also own, and it is the file most likely to need editing when
  Magento's installation procedure changes — while being the least testable.
- *Suggested fix:* Extract the phases (`resolve version`, `create project`, `write env`,
  `install`) into functions in a `utils/magento2-init.sh`, so each phase can be re-run
  independently after a failure. This is worth doing when the file is next substantially edited, not
  on its own.

**LB2. `environments/local/` is an empty environment type** — `environments/local/local.base.yml`

- *What:* A 0-byte file. It satisfies `assertValidEnvType` (`utils/env.sh:83`), so `local` appears in
  `roll env-init`'s list of valid types, and `commands/env.cmd:51,112` special-case it to skip
  `php-fpm` and the nginx/db/redis defaults. There is no `init.env`.
- *Why it matters:* `roll env-init x local && roll env up` produces an environment with a network and
  nothing else. Whether that is the intent is not recorded anywhere.
- *Suggested fix:* If it is intended as "networking only, bring your own `.roll/roll-env.yml`", say so
  in a comment in the file and in `docs/environments/types.md`. If not, remove the directory; the
  type disappears from the list automatically.

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
| `local` | **no** | **no** | Empty base fragment — see **LB2** |

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

For a `magento2` project the effective values of `ROLL_VARNISH`, `ROLL_ELASTICSEARCH` and
`ROLL_RABBITMQ` come from `init.env`, not from the env-type block in `commands/env.cmd:73-76` — see
finding **M1**.

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

## Conventions

These are enforced by review rather than by tooling, except where noted.

- **Every change must work on macOS and Linux.** Both are first-class targets — see
  [Supported platforms](#supported-platforms) for the table of real behavioural differences. CI only
  runs Ubuntu (finding **M10**), so the macOS half is on the author: run the affected command under
  `/bin/bash` on macOS before merging. The recurring traps are bash 3.2, BSD vs GNU flag semantics
  (`sed`, `ping`, `stat`), Mutagen-vs-bind-mount file sync, and the SSH agent socket path.
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
  maintained by hand and is currently out of date (finding **L1**).
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

**H1. The repository's only automated test fails** — `.github/workflows/shellcheck.yml:20`

- *What:* CI runs `shellcheck commands/*.cmd utils/*.sh`, which exits 1. **Verified:** 6 errors, 111
  warnings and 95 notes on a clean checkout. There is no `.shellcheckrc` and no severity threshold, so
  every one of the 212 findings is a failure. The errors are:

  | Location | Check | Problem |
  |---|---|---|
  | `utils/core.sh:147`, `utils/core.sh:154` | SC2068 | Unquoted `${DOCKER_PEERED_SERVICES[@]}` re-splits elements |
  | `utils/core.sh:26`, `commands/sign-certificate.cmd:12` | SC2242 | `exit -1` — the process actually exits 255 |
  | `commands/restore.cmd:186`, `commands/restore-full.cmd:195` | SC2145 | A string argument mixed with an array expansion |

- *Why it matters:* A gate that is always red is indistinguishable from a gate that has just gone red,
  so the one mechanism that could have caught the quoting and array-expansion bugs elsewhere in this
  list provides no signal. `exit -1` in `fatal` also means every fatal error reports exit status 255,
  which is indistinguishable from a signal-terminated process to any script wrapping `roll`.
- *Suggested fix:* Fix the six errors first (`"${DOCKER_PEERED_SERVICES[@]}"`, `exit 1`, `${arr[*]}`
  where a single string is intended), then add `.shellcheckrc` with the `disable=` list for the
  warning classes the codebase deliberately accepts, so the gate goes green and stays meaningful.
  Raising the threshold with `shellcheck -S error` is the quicker alternative but leaves the 111
  warnings unreviewed.

**H2. `roll db dump` fails against the MariaDB 11.x images in active use** — `commands/db.cmd:44`

- *What:* The `dump` subcommand runs `mysqldump` inside the `db` container. **Verified:** in
  `ghcr.io/epartment/roll/mariadb:11.4` — the image a running environment on the review machine was
  using — `mysqldump` does not exist; MariaDB 11 renamed it to `mariadb-dump`. The compatibility
  symlink for the client (`mysql`, used by `connect` at `commands/db.cmd:34` and `import` at
  `commands/db.cmd:40`) *is* still present, so only `dump` is affected.
- *Why it matters:* `roll db dump` exits with a Docker "executable file not found" error rather than
  anything mentioning MariaDB versions, on a command whose whole purpose is to produce a backup. The
  schema still defaults `MARIADB_VERSION` to 10.4, so the failure only appears on projects that pin a
  newer version — which makes it look intermittent across projects.
- *Suggested fix:* Probe once and fall back, so both generations work:
  `DUMP_BIN=$(roll env exec -T db sh -c 'command -v mariadb-dump || command -v mysqldump')`, then
  invoke `${DUMP_BIN}`. Apply the same treatment to `mysql` in `connect`/`import` before the client
  symlink is dropped too. A `mysqldump` symlink in the images repository would also fix it, but the
  probe keeps this repo working against images it does not control.

**H3. `roll registry categories` aborts on macOS** — `utils/registry.sh:273`,
`commands/registry.cmd:36`

- *What:* Both lines use `${category^}`, bash 4's "uppercase first character" expansion. **Verified:**
  under bash 3.2.57 (the macOS system bash, which `#!/usr/bin/env bash` resolves to on a machine
  without a newer bash first on `PATH`) the command dies with
  `bad substitution` and prints nothing else. A third occurrence, `${categories[$i]^}` at
  `utils/registry.sh:363`, is silently accepted by bash 3.2 as a no-op, so `roll registry stats`
  works but never capitalises.
- *Why it matters:* It is a hard failure of a documented subcommand on the primary development
  platform, and it contradicts the Bash 3.2 constraint that the rest of the codebase carefully
  observes. The inconsistency between the scalar and array forms is why it survived: the array form
  produces no error to notice.
- *Suggested fix:* Replace all three with a helper — `printf '%s%s' "$(echo "${s:0:1}" | tr
  '[:lower:]' '[:upper:]')" "${s:1}"` — or simply drop the capitalisation, since the category values
  are already lowercase words. Add a `bash --posix`-independent smoke test that runs
  `roll registry categories` under `/bin/bash` on a macOS runner, because Linux-only CI cannot catch
  this class of bug.

### Medium

**M1. Env-type service defaults are dead code; the toggles they set resolve to 0** —
`utils/config.sh:378-381` and `utils/config.sh:473-476`, duplicated at `commands/env.cmd:73-76`

- *What:* `loadRollConfig` runs `setConfigDefault` for every schema key (`utils/config.sh:378-381`)
  *before* calling `postProcessConfig` (`utils/config.sh:389`). `ROLL_VARNISH`,
  `ROLL_ELASTICSEARCH` and `ROLL_RABBITMQ` are declared `boolean:0`, so by the time
  `postProcessConfig` evaluates `export ROLL_VARNISH="${ROLL_VARNISH:-1}"` the variable is already
  `0` and the `:-1` never applies. `commands/env.cmd:73-76` repeats the same block and fails the same
  way. **Verified** by loading a minimal `magento2` `.env.roll` (containing only `ROLL_ENV_NAME` and
  `ROLL_ENV_TYPE`) through `loadEnvConfig`: `ROLL_VARNISH=0`, `ROLL_ELASTICSEARCH=0`,
  `ROLL_RABBITMQ=0`.
- *Why it matters:* A `magento2` environment whose `.env.roll` does not list these keys comes up with
  no Varnish, no search engine and no message queue — and Magento's own configuration will point at
  services that are not running. New projects are shielded because
  `environments/magento2/init.env` sets all three explicitly, so the bug only surfaces on
  hand-written or older `.env.roll` files, which is exactly when it is hardest to attribute. The same
  ordering makes `postProcessConfig`'s `DB_DISTRIBUTION_VERSION` branch (`utils/config.sh:424-430`)
  unreachable.
- *Suggested fix:* Move the `setConfigDefault` loop to *after* `postProcessConfig`, so per-type
  derivation runs against unset variables and the schema fills in only what is still missing. Then
  delete the duplicated block at `commands/env.cmd:24-105` outright — it is the second copy of logic
  `utils/config.sh` already owns, and keeping both guarantees they drift (see the coupling map).
  Add a test that loads a minimal `.env.roll` per env type and asserts the effective toggles.

**M2. YAML image-version fallbacks are unreachable and disagree with the schema** —
`utils/config.sh:95-121` vs `environments/`

- *What:* Because every schema key with a literal default is exported before `docker compose` runs,
  the `${VAR:-fallback}` defaults written into the fragments never apply. Eight of them name a
  different version from the schema:

  | Variable | Schema default (`utils/config.sh`) | Fragment fallback | Fragment |
  |---|---|---|---|
  | `PHP_VERSION` | `8.1` | `8.3` | `environments/includes/php-fpm.base.yml:22` |
  | `NODE_VERSION` | `18` | `22` | `environments/includes/php-fpm.base.yml:27` |
  | `ELASTICSEARCH_VERSION` | `7.17` | `8.11` | `environments/includes/elasticsearch.base.yml:4` |
  | `OPENSEARCH_VERSION` | `2.5` | `2.19` | `environments/includes/opensearch.base.yml:4` |
  | `RABBITMQ_VERSION` | `3.11` | `3.8` | `environments/includes/rabbitmq.base.yml:4` |
  | `REDIS_VERSION` | `7.0` | `5.0` | `environments/includes/redis.base.yml:4` |
  | `VARNISH_VERSION` | `7.0` | `6.0` | `environments/includes/varnish.base.yml:10` |
  | `NGINX_VERSION` | `1.27` | `1.26` | `environments/includes/nginx.base.yml:4` |

  A third value exists for some of these in `describe.cmd` (PHP `8.2`, Node `18`, Redis `7.2`), used
  only for display. **Verified** for `PHP_VERSION`: a minimal `magento2` `.env.roll` resolves to
  `8.1`, not the `8.3` the fragment appears to promise.
- *Why it matters:* Reading the fragment gives the wrong answer about what a project without an
  explicit pin actually gets, and the schema's values are the older ones — a `magento2` project
  missing `PHP_VERSION` silently runs PHP 8.1 against Magento 2.4.7+. `roll env describe` then
  reports a third number.
- *Suggested fix:* Make the schema the single source of truth: bring `utils/config.sh`'s defaults up
  to the versions the fragments claim, then reduce the fragments to bare `${VAR}` so a missing value
  fails loudly instead of resolving to a stale one. Drop the hardcoded fallbacks in
  `commands/describe.cmd:108,120,133` and print the resolved values.

**M3. The network-existence check in `env up` never matches, so a redundant compose pass runs every
time** — `commands/env.cmd:206`

- *What:* `docker network ls -f 'name=$(renderEnvNetworkName)' -q` is single-quoted, so the command
  substitution is not performed and Docker filters on the literal string
  `name=$(renderEnvNetworkName)`. **Verified:** such a filter matches nothing, so the `-z` test is
  always true and the `docker compose … up --no-start` block at `commands/env.cmd:208-210` executes on
  every `roll env up`, not only on first creation.
- *Why it matters:* Every `env up` performs a full extra compose pass — resolving images, creating
  containers with `--no-start` — before the real `up`. It is wasted wall-clock on every start and,
  because `--no-start` creates containers, it can mask ordering problems that a genuine first-run
  would expose.
- *Suggested fix:* `docker network ls -f "name=^$(renderEnvNetworkName)$" -q`, with double quotes and
  anchors so a longer environment name is not matched as a prefix.

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

**M6. `roll registry`'s metadata layer is a stub** — see boundary finding
[**MB2**](#boundary-findings).

**M7. Nothing validates `ROLL_ENV_NAME`, and Compose rejects uppercase project names** —
`commands/env-init.cmd:21-23`, `utils/config.sh:65`

- *What:* `env-init` prompts for a name and accepts anything non-empty; the schema declares
  `ROLL_ENV_NAME` as `string:required`, which only checks for emptiness. The name is passed straight
  to `docker compose -p` (`commands/env.cmd:248`). **Verified:** `docker compose -p TestUpper …`
  fails with `invalid project name "TestUpper": must consist only of lowercase alphanumeric
  characters, hyphens, and underscores as well as start with a letter or number`.
- *Why it matters:* `roll env-init MyProject magento2` succeeds, and then every subsequent `roll env`
  command fails with a Docker error that names neither RollDev nor `.env.roll`. Related: several
  places lowercase the name (`renderEnvNetworkName`, `utils/env.sh:50`) while others do not
  (`commands/describe.cmd:18`, the `traefik.docker.network=${ROLL_ENV_NAME}_default` labels in every
  fragment), so even a name that Compose tolerates can produce a label that does not match the real
  network.
- *Suggested fix:* Validate in `commands/env-init.cmd` before writing the file — reject anything not
  matching `^[a-z0-9][a-z0-9_-]*$` and re-prompt — and add the same check to
  `validateConfigValue` for `ROLL_ENV_NAME` so existing files are caught by `roll config validate`.

**M8. `roll vnc` builds Compose v1 container names** — `commands/vnc.cmd:12`

- *What:* It constructs `${ROLL_ENV_NAME}_${service}_${index}` — the Compose v1 separator — while
  `bin/roll:26-30` requires Compose v2, which names containers `name-service-1`.
  `commands/describe.cmd:18` uses the v2 form, so the two disagree.
- *Why it matters:* The SSH forward and the generated Remmina profile both target a hostname that does
  not resolve, so `roll vnc` cannot reach the Selenium VNC server on any supported Compose version.
- *Suggested fix:* Resolve the container through Compose instead of reconstructing the name:
  `roll env ps -q "${service}"`, then `docker container inspect` for the hostname. That also removes
  the assumption of a single replica. Apply the same change to `commands/describe.cmd:18`.

**M9. `fixowns` and `fixperms` mishandle multiple arguments** — `commands/magento2/fixowns.cmd:17,20`,
`commands/magento2/fixperms.cmd:17,21`

- *What:* Both test `[ -z "${ROLL_PARAMS[@]}" ]`. With one element that works by accident; with two or
  more, `[` receives three arguments and fails with `too many arguments`. `fixowns.cmd:20` then
  interpolates the array into a single path — `/var/www/html/"${ROLL_PARAMS[@]}"` — which concatenates
  the elements rather than treating them as separate targets.
- *Why it matters:* `roll fixowns app/code var` reports a shell error instead of fixing ownership, or
  chowns a path that does not exist. Since these commands exist to recover from permission problems,
  they fail exactly when someone is already stuck.
- *Suggested fix:* Test the count — `if (( ${#ROLL_PARAMS[@]} == 0 )); then` — and pass the array
  through as separate arguments, prefixing each with `/var/www/html/` in a loop rather than inside one
  quoted expansion.

**M10. Nothing tests the macOS half of a platform the tool must support** —
`.github/workflows/shellcheck.yml:17`

- *What:* All five workflows run on `ubuntu-latest`. There is no macOS job, and no runtime smoke test
  on any platform — CI lints shell sources and builds documentation, nothing more.
- *Why it matters:* macOS is the primary developer platform *and* the one with the divergent
  behaviour (bash 3.2, BSD flag semantics, Mutagen), so every platform-specific defect in this list
  is invisible to CI by construction. **H3** is the clearest case: `${category^}` lints clean and runs
  fine on Ubuntu, and hard-fails on the platform most users are on. **M11** is the mirror image — a
  bug that only manifests on Linux, shipped from macOS machines.
- *Suggested fix:* Add a `macos-latest` job running the same ShellCheck invocation, then a minimal
  matrix smoke test across `macos-latest` and `ubuntu-latest` that needs no Docker daemon:
  `./bin/roll version`, `./bin/roll registry validate`, `./bin/roll registry categories`,
  `./bin/roll config schema`, and a `roll env-init` into a temporary directory followed by
  `roll config validate`. On macOS, invoke via `/bin/bash ./bin/roll` so bash 3.2 is exercised rather
  than whatever the runner has on `PATH`. That set would have caught **H3**, **M7** and **M9**.

**M11. `isOnline` always reports offline on Linux, so `roll svc up` never refreshes images** —
`utils/core.sh:161-163`

- *What:* `isOnline` probes with `ping -q -c1 -t 2 8.8.8.8`. `-t` means *timeout in seconds* on BSD
  ping (macOS) but *TTL* on GNU and BusyBox ping (Linux), so on Linux the probe sends a packet with
  TTL 2 and both public resolvers are further away than two hops. **Verified** in a Linux container:
  `-t 2` gives 100 % packet loss and exit 1, `-t 64` and `-W 2` both succeed, and the identical
  command exits 0 on the macOS host — so the flag semantics, not connectivity, are the cause.
- *Why it matters:* The only caller is `commands/svc.cmd:50-52`, which skips `roll svc pull` when the
  probe says offline. On Linux the shared-service images are therefore never pulled by `roll svc up`,
  so Traefik, dnsmasq, Mailpit and the tunnel silently stay on whatever tags were first fetched. That
  is precisely the platform where nobody is watching, and the symptom — a stale image — surfaces much
  later as unexplained behaviour rather than as a failed pull.
- *Suggested fix:* Do not use `ping` for a reachability check at all; ICMP is also blocked in many
  networks and container runtimes, which would produce the same false negative on macOS. Probe the
  registry that is actually needed, with a portable timeout:
  `curl -fsS -m 3 -o /dev/null https://ghcr.io/v2/ && echo true || echo false`. If `ping` must stay,
  branch on `${ROLL_ENV_SUBT}` and use `-W 2` on Linux — but note `isOnline` is in `utils/core.sh`,
  which is sourced before the config is loaded, so `$OSTYPE` is the only signal available there.

**M12. WSL hosts get no OS-specific compose fragment at all** — `utils/config.sh:361-363`,
`utils/env.sh:96,98`

- *What:* `loadRollConfig` sets `ROLL_ENV_SUBT=wsl` when `/proc/sys/kernel/osrelease` mentions
  Microsoft. `appendEnvPartialIfExists` then looks for `<name>.wsl.yml`, and **no such file exists**
  anywhere in `environments/` (verified — only `.base.yml`, `.darwin.yml` and `.linux.yml` are
  present). A WSL host therefore receives neither the darwin nor the linux variant of any fragment.
- *Why it matters:* The most consequential loss is `environments/includes/php-fpm.linux.yml`, the only
  place the host's SSH agent socket is mounted into the containers. Without it `SSH_AUTH_SOCK` falls
  back to `/tmp/ssh-auth.sock` from `environments/includes/php-fpm.base.yml:26`, which nothing
  creates, so agent forwarding — and therefore `composer install` against private repositories —
  cannot work on WSL, and the unconditional `chmod 777` at `commands/env.cmd:285-287` targets a path
  that does not exist. WSL2 is a documented install target in `docs/installing.md`, so this is a
  supported configuration silently missing a fragment. *The WSL-side consequences are read from the
  code; unverified, as no WSL host was available for this review.*
- *Suggested fix:* Either treat WSL as Linux for fragment selection — have
  `appendEnvPartialIfExists` fall back to the `linux` variant when `ROLL_ENV_SUBT` is `wsl`, which
  matches the intent, since WSL is a Linux kernel — or add `environments/includes/php-fpm.wsl.yml`.
  The fallback is preferable: it is one change in `utils/env.sh` and it covers every present and
  future `.linux.yml` rather than only the one that is currently missed. Keep the separate `wsl`
  value, because `utils/config.sh:440-442` legitimately needs it for `XDEBUG_CONNECT_BACK_HOST`.

### Low

**L1. `commands/usage.help` is out of date** — `commands/usage.help:44-77`

- *What:* The hand-maintained command list omits nine commands that the registry resolves from this
  repository: `cliq`, `describe`, `duplicate`, `magerun`, `multistore`, `node`, `npm`, `vnc`, and the
  internal `usage`. (`roll registry export simple` also lists commands supplied by third-party packs
  under `~/.roll/reclu`, which correctly do not appear here.)
- *Why it matters:* `roll` with no arguments is the primary discovery path, so undocumented commands
  are effectively invisible — including `roll env describe`, which is the most useful of them.
- *Suggested fix:* Add the missing entries. Longer term this is what **MB2** would remove the need
  for: a working registry description mechanism would let `usage.cmd` render the list from the
  `.help` files instead.

**L2. Global configuration is loaded by `eval`, bypassing the schema** — `commands/env.cmd:20`,
`commands/svc.cmd:16,29,32,56`, `commands/shell.cmd:5`, `commands/rootshell.cmd:5`

- *What:* Six places read `~/.roll/.env` with `eval "$(cat … | grep '^ROLL_')"` or a narrower grep,
  rather than going through `loadConfigFromFile` (`utils/config.sh:235`), which parses `KEY=VALUE`
  with a regex and validates against the schema.
- *Why it matters:* Any shell metacharacter in that file executes — a value containing `$(…)` or a
  backtick runs as a command. The file is user-owned so this is not a privilege boundary, but it turns
  a typo into arbitrary execution and it silently skips the validation everything else relies on. It
  also means the same file is parsed two different ways depending on which command runs.
- *Suggested fix:* Call `loadConfigFromFile "${ROLL_HOME_DIR}/.env"` in all six places. It already
  handles CRLF stripping and quote removal, which is what the `sed`/`grep` pipelines were
  approximating.

**L3. `ROLL_SERVICE_PORTAINER` has three different defaults** — `utils/config.sh:151`,
`commands/svc.cmd:35`, `commands/install.cmd:96,113`, `commands/status.cmd:79-84`

- *What:* The schema says `boolean:1`; `commands/svc.cmd:35` falls back to `0`;
  `commands/install.cmd` writes `ROLL_SERVICE_PORTAINER=1` into a fresh `~/.roll/.env` while the
  comment above the second occurrence (`commands/install.cmd:112`) reads
  `Set to "0" to disable global Portainer service`; `commands/status.cmd` falls back to `0` again.
- *Why it matters:* Whether Portainer starts depends on which code path ran, and `roll status` can
  report it as disabled while `roll svc` started it. The stray comment makes the file look as though
  it writes `0`.
- *Suggested fix:* Read the value through `getConfig ROLL_SERVICE_PORTAINER` in both `svc.cmd` and
  `status.cmd` so the schema is the only default, and fix the comment.

**L4. The three box-drawing helpers are copies** — `utils/core.sh:29-120`

- *What:* `boxinfo`, `boxsuccess` and `boxerror` are 30-line functions differing only in the
  `tput setaf` colour code (3, 2, 1) and one leading space in the border.
- *Why it matters:* Ninety lines where thirty-two would do, and a change to the box format has to be
  made three times.
- *Suggested fix:* One `box <colour> <lines…>` function with the three names as one-line wrappers.

**L5. `vuejs` has no `init.env`, so it inherits stale schema defaults** —
`environments/vuejs/`

- *What:* Every other populated environment type ships an `init.env` that `commands/env-init.cmd:48`
  appends. `vuejs` does not, so a new project gets only the five base lines and falls back to the
  schema — PHP 8.1, Node 18, MariaDB 10.4 — for a type whose whole purpose is a Node toolchain.
- *Why it matters:* A Vue project is created with an eight-version-old Node by default, and the fact
  that it is a default rather than a choice is invisible.
- *Suggested fix:* Add `environments/vuejs/init.env` pinning at least `NODE_VERSION`, `PHP_VERSION`
  and `ROLL_DB`. See **LB2** for the related question about `environments/local/`.

**L6. Traefik mounts the Docker socket read-write** — `docker/docker-compose.yml:12`

- *What:* `- /var/run/docker.sock:/var/run/docker.sock`, with no `:ro`. Traefik's Docker provider only
  reads.
- *Why it matters:* Write access to the Docker socket is equivalent to root on the host. This is a
  local development tool, so the exposure is bounded by the host itself, but the write access buys
  nothing.
- *Suggested fix:* Append `:ro`.

**L7. `env up` chmods the SSH agent socket to 777 unconditionally** — `commands/env.cmd:285-287`

- *What:* Every `up` and `start` runs `roll root chmod 777 /run/host-services/ssh-auth.sock` in the
  `php-fpm` container, with no check that the path exists or that agent forwarding is in use. On Linux
  the mount source is `${SSH_AUTH_SOCK:-/dev/null}` (`environments/includes/php-fpm.linux.yml:3`), so
  without an agent this chmods `/dev/null`'s bind target.
- *Why it matters:* It makes the forwarded agent socket writable by every process in the container,
  and the unconditional run means a failure here is noise rather than signal. Anything running in the
  container can then use the host's SSH keys, which is the intent for the developer but also true for
  anything that ends up inside a `composer install`.
- *Suggested fix:* Guard on `[[ -n "${SSH_AUTH_SOCK:-}" ]]` and use the narrowest mode that works —
  `chown www-data` plus `chmod 600`, since only that user needs it.

**L8. Sphinx is configured for directories that do not exist** — `docs/conf.py:43,45`

- *What:* `html_static_path = ['_static']` and `html_extra_path = ['_redirects']`; neither
  `docs/_static` nor `docs/_redirects` exists in the repository.
- *Why it matters:* Every documentation build emits warnings for both. Harmless, but it means a build
  log is never clean, so a real warning is easy to miss.
- *Suggested fix:* Remove both settings, or add the directories with a `.gitkeep`.

**L9. The ShellCheck gate does not cover the env-type commands or the help files** —
`.github/workflows/shellcheck.yml:5-13,20`

- *What:* The glob is `commands/*.cmd utils/*.sh`. It excludes the ten `.cmd` files in
  `commands/magento2/` and the one in `commands/wordpress/` (344 and 11 lines), and all 40 `.help`
  files, which are Bash scripts sourced by `commands/usage.cmd:32`. The `paths:` trigger has the same
  gap, so a change to `commands/magento2/` does not even start the workflow.
- *Why it matters:* Finding **M9** lives in exactly that blind spot — SC2199/SC2198 would have
  flagged `[ -z "${ROLL_PARAMS[@]}" ]`.
- *Suggested fix:* Lint `commands/**/*.cmd`, `commands/**/*.help` and `utils/*.sh`, and widen the
  `paths:` filter to match. Do this after **H1**, since it will surface more findings.

**L10. Root CA trust is skipped without warning on Linux distributions that are neither Debian- nor
Fedora-family** — `commands/install.cmd:29-52`

- *What:* The trust step is an `if`/`elif`/`elif` chain testing for
  `/etc/pki/ca-trust/source/anchors` (Fedora/CentOS), `/usr/local/share/ca-certificates`
  (Debian/Ubuntu), then `darwin`. If a Linux host has neither directory — Arch, openSUSE, Alpine,
  Void — no branch runs and nothing is printed. Contrast the DNS step immediately below, which does
  emit a `warning` for every non-macOS host (`commands/install.cmd:65`).
- *Why it matters:* `roll install` reports success, and the first symptom is every `.test` site
  showing a certificate error with no indication that a step was skipped rather than failed. The CA
  file is generated correctly, so the user has no reason to suspect the trust step.
- *Suggested fix:* Add a final `elif [[ "$OSTYPE" =~ ^linux ]]` branch that warns and prints the CA
  path (`${ROLL_SSL_DIR}/rootca/certs/ca.cert.pem`) with a pointer to the documentation, mirroring
  the DNS warning. Detecting `update-ca-trust`/`update-ca-certificates` on `PATH` instead of probing
  directories would also widen distribution coverage.

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
  `commands/vnc.cmd` are correctly macOS- and Linux-specific respectively. `ping` in `isOnline`
  (**M11**) and the missing `wsl` fragment (**M12**) are the only two places where the platform
  difference was not handled.
- **Bash 3.2 compliance elsewhere.** The parallel-indexed-array pattern in `utils/config.sh` and
  `utils/registry.sh` is applied consistently; no associative arrays anywhere. `commands/status.cmd`
  correctly guards its `mapfile` use with a `while read` fallback. The only bash-4 constructs found are
  the three `${var^}` uses in finding **H3**.
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
  skips it and the `${NGINX_TEMPLATE:-…}` chains in `utils/config.sh:460-491` and
  `commands/env.cmd:61-95` do resolve as written — unlike the boolean toggles in **M1**. The
  apparently redundant trailing `export` lines in the `magento1`/`magento2` blocks are harmless
  because `:-` preserves the value set by the branch above.
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
| `invalid project name "…"` from `roll env up` | `ROLL_ENV_NAME` contains uppercase or an illegal character | Lowercase it in `.env.roll`; note the rename orphans the old volumes (finding **M7**) |
| Environment comes up on an empty database after a rename | `ROLL_ENV_NAME` is the Compose project name and prefixes every named volume | Bring the environment down, copy `oldname_dbdata` to `newname_dbdata`, bring it up |
| `bad substitution` from `roll registry categories` | Bash 4 syntax under macOS bash 3.2 | Finding **H3**; no workaround for the subcommand — use `roll registry list` |
| `executable file not found` from `roll db dump` | `mysqldump` absent on MariaDB 11.x | Finding **H2**; workaround `roll env exec -T db mariadb-dump -u… -p… <db>` |
| Magento cannot reach Varnish, Elasticsearch or RabbitMQ, and the containers are not running | `.env.roll` omits the toggles, which resolve to `0` despite the env-type default | Finding **M1**; set `ROLL_VARNISH=1`, `ROLL_ELASTICSEARCH=1`, `ROLL_RABBITMQ=1` explicitly |
| A project silently runs an older PHP or Node than expected | Schema default won over the fragment fallback | Finding **M2**; pin the version in `.env.roll` |
| `port is already allocated` on `php-fpm` | `ROLL_BROWSERSYNC=1` publishes fixed host ports on that service — the only fragment that publishes any | Set `ROLL_BROWSERSYNC=0`; verify with `roll env config \| grep published`. See `FEATURE-REQUESTS.md` H2 |
| A command run right after `roll env up` fails to connect to the DB or search engine | No fragment declares a `healthcheck:` and `up` does not pass `--wait`, so it returns when containers *start* | Retry with a wait loop against the service. See `FEATURE-REQUESTS.md` H1 |
| Shared-service images never update on Linux, however often `roll svc up` runs | `isOnline` uses BSD `ping -t` semantics, so the probe always fails on Linux and `svc pull` is skipped | Finding **M11**; run `roll svc pull` explicitly |
| SSH agent forwarding does not work inside the containers on WSL2 | `ROLL_ENV_SUBT=wsl` matches no compose fragment, so the socket mount from `php-fpm.linux.yml` is never applied | Finding **M12**; as a workaround add the mount to the project's `.roll/roll-env.yml` |
| `.test` sites show a certificate error on Linux after a clean `roll install` | CA trust is only wired up for Debian- and Fedora-family distributions, and is skipped silently otherwise | Finding **L10**; add `~/.roll/ssl/rootca/certs/ca.cert.pem` to the distribution's trust store manually |
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
