# Changelog

All notable changes to RollDev.

Entries are assembled from the git history, the release tags, and the notes attached to the
[GitHub releases](https://github.com/epartment/rolldev/releases). Where a release carried notes they
are quoted first, as the summary written at the time; the bullets beneath are the commits in that
range. Versions before 0.3.0 predate the GitHub releases and are reconstructed from commits alone.
Merge commits, automated `Tagged <version>` commits and version bumps are omitted, as are bullets
that only restate the release note above them.

## Unreleased

The 0.8.0 development work. Two changes need reading before upgrading — unpinned service versions
now warn (and become an error in 0.9.0), and gum becomes a dependency. Both are covered in
[RELEASE-NOTES-0.8.0.md](RELEASE-NOTES-0.8.0.md).

### Added

- `roll env doctor` — seventeen checks over Docker, containers, ports, search engine and disk, with
  `--format json` and an exit code you can gate on.
- `--format json` on `roll status`, `roll env describe`, `roll registry list` and `roll env doctor`.
  No ANSI, no credentials, values escaped.
- `roll has-command <name>` — exit 0/1, no output, for feature detection in scripts.
- `roll env up --wait`, backed by new healthchecks for db, redis, elasticsearch, opensearch,
  rabbitmq, varnish and nginx. The search engines are probed through `/_cluster/health` rather than a
  port, because those containers can hold a port open while the cluster inside them is dead.
- `roll env sh <service> '<command>'` — runs through `sh -c` inside the container, so redirects and
  pipes apply there rather than on the host.
- `roll config check-pins` and `roll config fix-pins` for the version-pin migration.
- `roll myloader --normalize-source-ddl` — strips the `ENCRYPTION` table option and remaps
  `utf8mb4_0900_*` collations so a MySQL 8 dump loads into MariaDB. Without the flag, a failed run
  now names the cause instead of reporting `Trace/breakpoint trap`.
- `ROLL_PUBLISH_PORTS=0` runs an environment without publishing host ports, for hosts running many
  environments at once. `ROLL_BROWSERSYNC=1` publishing ports on php-fpm was a known cause of
  "port is already allocated" that no `.roll/roll-env.yml` override could fix.
- `ELASTICSEARCH_JAVA_OPTS` / `OPENSEARCH_JAVA_OPTS` replace the hardcoded 512MB search-engine heap.
- `ROLL_ENV_INIT_FORCE=1` lets `roll env-init` overwrite an existing `.env.roll` non-interactively.
- `copyfromcontainer`, `copytocontainer`, `magento2/theme` and `convert` moved in from the internal
  command pack, each with its outstanding bugs fixed in transit: `copytocontainer --all` was
  unreachable and `copytocontainer <folder>` copied the whole project root into the destination,
  `copyfromcontainer --realpath` tested a container path against the host filesystem and built a
  destination whose parent never existed, theme discovery was relative to the working directory and
  only ever examined the first theme, the Gulp-or-Yarn choice is now made per theme so mixed
  projects build correctly, and `convert` overwrote `ELASTICSEARCH_VERSION` with a hardcoded value
  and wrote a `ROLL_NO_STATIC_CACHING` key no schema defines — it now translates that legacy
  negative-form value into `ROLL_MAGENTO_STATIC_CACHING`.
- `roll registry list` now carries real descriptions and categories, from `@description:` and
  `@category:` headers in the help files.
- Documentation: [driving RollDev from a script](docs/machine-interface.md), service version pins,
  unattended operation, and the `doctor` command.

### Changed

- **Unpinned service versions now warn**, and will be an error in 0.9.0. The fallback is the version
  the project was already running, so nothing changes behaviour today. A version set in global config
  (`~/.roll/.env`) counts as unpinned: it is not in the repository, so a colleague without that line
  still resolves a different image. `fix-pins` writes the inherited value in that case, not
  RollDev's built-in default.
- **gum is a dependency** for interactive prompts. Every prompt is also reachable by flag,
  environment variable or positional argument, so scripted use works without it, and `roll install`
  warns rather than failing when it is missing.
- Every prompt now resolves flag/env first, uses gum only on a terminal, and otherwise fails naming
  the flag that would have answered it — an unattended run can no longer hang on a prompt.
- `roll env-init` validates the environment name against Compose's project-name rules at creation,
  instead of letting it fail later.
- `roll tableplus` is now a RollDev command in its own right, with Setapp-aware discovery and a
  clear message on Linux rather than an obscure failure.
- `dialog` is no longer used anywhere.

### Fixed

- **`magento2` environments came up without Varnish, a search engine or RabbitMQ** unless the
  toggles were spelled out. The environment-type defaults ran after the schema defaults had already
  filled those variables in, so every `${VAR:-1}` deriving them was unreachable.
- **A restored volume came back owned by root, so Elasticsearch could not start.** `roll restore`
  creates each volume with `docker volume create` and then extracts into it as root with
  `--strip-components=1`, which discards the archive's top-level entry — the only one carrying the
  data directory's own ownership. Docker's copy-up did not compensate, because it fires only for an
  empty volume and the restore populates this one before any service mounts it. Services that start
  as root chown their data directory themselves; Elasticsearch and OpenSearch run as uid 1000 and
  died at boot with `AccessDeniedException: .../data/.es_temp_file` while the restore reported
  success. The owner is now derived from the restored content after each extraction.
- `roll db` works against MariaDB 11, which ships only `mariadb-dump`/`mariadb`.
- `roll registry categories` no longer dies on macOS — bash 4 syntax under a bash 3.2 shell.
- `roll backup --help` and `roll status --help` no longer exit 2 on macOS. bash 3.2 mis-parses a lone
  apostrophe inside a heredoc nested in `$( )`; Ubuntu-only CI could not see it.
- `roll db/env/redis/svc/restore/restore-full/duplicate --help` no longer fork until killed. Those
  commands take arbitrary flags, so roll hands `--help` to them directly, and each re-invoked itself.
- `roll redis --help` was unreachable rather than recursive, and now renders.
- `roll restore` with no backups reports it instead of dying on an internal error.
- `roll env up` no longer does a redundant compose pass every time: the network-existence check was
  single-quoted, so the command substitution inside it never ran and the filter never matched.
- `roll env describe` back to ~1s from ~9s, and it no longer builds container names by string
  concatenation, which broke whenever Compose named them differently. Same fix in `roll vnc`.
- `roll fixowns` and `roll fixperms` accept more than one path.
- `isOnline` no longer always reports offline on Linux — `ping -t` is a timeout on BSD and a TTL on
  GNU — so `roll svc up` refreshes images there.
- WSL environments get the `.linux.yml` compose fragments.
- The Portainer and Startpage service defaults are read from configuration rather than from literals
  that disagreed with the schema.
- An unsupported Linux distribution now warns with the CA path instead of silently skipping the
  trust-store step during `roll install`.
- `roll env-init x vuejs` produces a valid project; the `vuejs` and `local` types had no `init.env`.
- `box` no longer aborts under `set -u` on bash 4.4 and later: it declared its width variable
  without initialising it, and those versions apply `set -u` inside arithmetic contexts where bash
  3.2 substitutes 0. Only reachable from a caller that sets `-u`, which is why it surfaced in the
  prompt harness rather than in `roll` itself.

### Security

- The TablePlus connection URI, which carries the database password, is no longer passed as a
  process argument where anything able to read `ps` could see it.
- The ssh-agent socket is `chmod 600` and owned by `www-data`, rather than `chmod 777`, and the
  fixup only runs when there is an agent socket to fix.
- Traefik's docker socket is mounted read-only.
- Six `eval "$(cat ~/.roll/.env …)"` sites are replaced with schema-validated config loading.
- `--format json` output carries no credentials, and values are escaped rather than concatenated.

### Internal

- ShellCheck runs on macOS as well as Ubuntu, over `commands/**`, the help files, `utils/` and the
  CI scripts, and passes on both. The Ubuntu leg had been red for most of the cycle: Ubuntu ships
  ShellCheck 0.9.0, which reports four findings (SC2002, SC2015, SC2236) that the 0.11.0 on macOS
  no longer raises, so a green local run said nothing about CI. Those four are fixed in code rather
  than silenced in `.shellcheckrc`.
- A smoke suite runs on both platforms: the Docker-free command set, a prompt-contract harness, and
  a parse check that catches the bash 3.2 heredoc trap and any command re-invoking its own help.
- New shared libraries: `utils/interact.sh` (prompts and styled output), `utils/backup.sh` (the
  backup/restore/duplicate primitives, replacing eleven byte-identical copies) and
  `utils/magento2-init.sh` (re-runnable install phases). `restore-full` is now `restore
  --include-source` with the old name kept as an alias, so existing scripts keep working; those two
  files drop from 2 087 lines to 625.

### Known issue

- A restored Elasticsearch volume comes back unwritable — the volume root is owned by uid 0 while the
  image runs as uid 1000 — so the service will not start after `roll restore`. The database restores
  correctly. This predates the release; it is newly visible because `env up --wait` and the
  healthchecks now catch it, where `env up` previously returned success.

## [0.7.2](https://github.com/epartment/rolldev/releases/tag/0.7.2) — 2026-08-31

> - Fixes for Linux CMD

- Linux cmd fixes and added feature request list

## [0.7.1](https://github.com/epartment/rolldev/releases/tag/0.7.1) — 2026-08-28

> - Generalized the backup command by adding a directory path argument

- Address review feedback on the backup output flags
- Fix infinite recursion in roll backup --help
- Add --output-dir, --archive-name and --keep-dir to roll backup
- Made some fixes for the restore commands related to the search containers

## [0.7.0.5](https://github.com/epartment/rolldev/releases/tag/0.7.0.5) — 2026-07-02

> - Made changes to how params are passed to myloader in the wrapper command

## [0.7.0.4](https://github.com/epartment/rolldev/releases/tag/0.7.0.4) — 2026-06-26

> - My dumper fixes

- Added epartment-init to allow any argument for mydumper support
- Fixes for my dumper

## [0.7.0.3](https://github.com/epartment/rolldev/releases/tag/0.7.0.3) — 2026-06-04

> - Added support for mydumper and myloader

- Added a CLAUDE.md

## [0.7.0.2](https://github.com/epartment/rolldev/releases/tag/0.7.0.2) — 2026-04-29

> Changed fallback NGINX version to one thats being build

- Updated the default NGINX version to a supported version (1.27)

## [0.7.0.1](https://github.com/epartment/rolldev/releases/tag/0.7.0.1) — 2026-04-21

> Changed an image repo path to epartment repo

## [0.7.0.0](https://github.com/epartment/rolldev/releases/tag/0.7.0.0) — 2026-04-20

> Updated the Epartment roll with the latest changes from dockergiant/rolldev

- Updated README.md
- update: simplify archive extraction for cross-platform compatibility in restore commands
- update: improve logging in restore/restore-full commands for better process visibility
- add: enhance Magento multi-store support with extended docs, `multistore` usage details, and example setups
- update: refine Traefik rules for host matching v3 and add Traefik configuration regeneration in restore commands v3
- add: automated SSL certificate signing for environment domains in restore and restore-full commands
- update: remove Traefik version pinning in docker-compose and fix indentation in svc.cmd for traefik v3
- add: verbose logging support for restore and restore-full commands + fix issue with restoring full backup for first time
- fix: handle help flag to properly support commands with arguments
- add: describe subcommand to env.cmd and enhance multistore documentation with improved clarity and structure
- add: describe command to display RollDev environment details, including service status, URLs, and configurations
- add: multistore command for managing Magento multi-store configurations with automated config generation and SSL support
- update: refine New Relic PHP agent documentation and add environment configuration support
- add: documentation for enabling New Relic monitoring with configuration examples and troubleshooting steps
- remove: Blackfire profiling documentation from roll-docker-stack
- add: New Relic monitoring configuration to all environment init files
- fix: handle empty projectNetworkList in status.cmd to avoid errors
- Update README
- update: switch elasticvue to official image and adjust configuration
- fix: resolve Magento 2.4.8+ 2FA configuration bug in magento2-init
- add comprehensive README to roll-docker-stack with installation steps, feature overview, supported environments, and contribution guide
- add RedisInsight support to roll-docker-stack with configuration, environment updates, and service definition
- add extensive documentation for magento2-init command, including a quick reference guide, usage examples, compatibility matrix, and troubleshooting steps
- add magento2-init command for project initialization with dynamic configuration and compatibility checks
- add magento2-init command, improve usage loading with dynamic paths, and enhance global/environment-specific config handling
- add restore-full command to ROLL_CMD_ANYARGS list
- improve backup ID extraction logic to handle warnings in command output
- use passphrase-fd for gpg decryption to handle password escaping and add support for multiple archive formats
- remove redundant exclude patterns from backup command
- Fix restore-full argument handling
- Require explicit archive path for restore-full
- Fix last network lookup in status command
- Fix status command for macOS compatibility
- Show running services in status
- docs: add decrypt examples for restore-full
- add duplication docs
- fixed issues with backup and restoring + full duplication command working
- Add shellcheck workflow
- Fix comment typo
- Fix mongodb env vars
- docs: fix typo in redis usage
- Fix parsing newline in status and correct install doc url
- Add environment duplication command
- fix in parameters in printf
- fixes in backup / restore commands
- fix encryption for backups
- fix issue with user permissions
- update backup and restore commands docs
- update backup and restore commands
- update to new workflows
- added docs for new registry system
- Added new system for better command registry and auto discovery on many places
- Added help files of version and install commands
- Refactored config loading with more dynamic loading of config files
- Enable manually run build documentation in github actions

## [0.6.3.1](https://github.com/epartment/rolldev/releases/tag/0.6.3.1) — 2026-02-23

> - Fixed a bash error handling issue with the code change

## [0.6.3](https://github.com/epartment/rolldev/releases/tag/0.6.3) — 2026-02-23

> - Added a check to make sure tput is available before setting its values to prevent error when run by cron

## [0.6.2](https://github.com/epartment/rolldev/releases/tag/0.6.2) — 2025-08-14

- remove xdebug mode env
- enable trace and profiler

## [0.6.1](https://github.com/epartment/rolldev/releases/tag/0.6.1) — 2025-07-03

- Updated base versions of the packages

## [0.6.0](https://github.com/epartment/rolldev/releases/tag/0.6.0) — 2025-07-03

- Updated actions
- Version 0.6.0 for moving images to ghcr.io/epartment/roll
- opensearch opts
- Updated default versions of packages for new Magento and Laravel projects

## [0.4.3](https://github.com/epartment/rolldev/releases/tag/0.4.3) — 2024-12-16

- ssh-agent perms and host key mount
- fix compose
- fix: darwin ssh agent

## [0.4.2](https://github.com/epartment/rolldev/releases/tag/0.4.2) — 2024-12-03

- fix compose

## [0.4.1](https://github.com/epartment/rolldev/releases/tag/0.4.1) — 2024-12-02

_No changes recorded beyond the tag itself._

## [0.4.0](https://github.com/epartment/rolldev/releases/tag/0.4.0) — 2024-12-02

> Made improvements in the debug agent and known_host forwarding

- fix: darwin ssh agent
- set correct xdebug modes

## [0.3.0](https://github.com/epartment/rolldev/releases/tag/0.3.0) — 2024-09-19

> Added support for forwarding SSH agents to Roll Shell

- Added support for forwarding SSH agent to roll shell

## [0.2.6.6](https://github.com/epartment/rolldev/releases/tag/0.2.6.6) — 2024-08-26

- Replace dockergiant with epartment
- Update svc.cmd
- Update env.cmd
- Renamed dockergiant references to Epartment

## [0.2.6.5](https://github.com/epartment/rolldev/releases/tag/0.2.6.5) — 2024-05-22  *(tag only, no GitHub release)*

- correct permissions when restoring a build

## [0.2.6.4](https://github.com/epartment/rolldev/releases/tag/0.2.6.4) — 2024-05-06  *(tag only, no GitHub release)*

- Remove version: from docker-compose.yml: https://github.com/docker/compose/issues/11628

## [0.2.6.3](https://github.com/epartment/rolldev/releases/tag/0.2.6.3) — 2024-04-25  *(tag only, no GitHub release)*

- Remove version: from docker-compose.yml: https://github.com/docker/compose/issues/11628
- minor bugfix asking for tty when its not available
- removed unused variables

## [0.2.6.2](https://github.com/epartment/rolldev/releases/tag/0.2.6.2) — 2024-04-18  *(tag only, no GitHub release)*

- set id_field_data to enabled which is disabled by default from Elasticsearch 8

## [0.2.6.1](https://github.com/epartment/rolldev/releases/tag/0.2.6.1) — 2024-04-10  *(tag only, no GitHub release)*

- Refactored the auto login script with checks if 2fa module is installed or not

## [0.2.6](https://github.com/epartment/rolldev/releases/tag/0.2.6) — 2024-04-09  *(tag only, no GitHub release)*

- Fix auto login command
- Added magento 2 auto admin login feature
- Refactor init env for akeneo environment type
- Add Akeneo environment type to docs.
- Fix python TFA SECRET generating in docs

## [0.2.4](https://github.com/epartment/rolldev/releases/tag/0.2.4) — 2024-03-27  *(tag only, no GitHub release)*

- Added MongoDB
- fix magento2 admin user creation script in documentation

## [0.2.3](https://github.com/epartment/rolldev/releases/tag/0.2.3) — 2024-03-06  *(tag only, no GitHub release)*

- add doc for setup varnish cache
- Fix online check command
- Make browsersync command work with ssl in other projects types
- Fix php config mapping in documentation example
- Move browsersync command from magento2 to global comamnds

## [0.2.2](https://github.com/epartment/rolldev/releases/tag/0.2.2) — 2023-10-12  *(tag only, no GitHub release)*

- Fixed issue Unsupported flag on extra parameters on grunt and magento command

## [0.2.1](https://github.com/epartment/rolldev/releases/tag/0.2.1) — 2023-09-12  *(tag only, no GitHub release)*

- Online network events only when active network and custom php ext

## [0.2.0](https://github.com/epartment/rolldev/releases/tag/0.2.0) — 2023-08-31  *(tag only, no GitHub release)*

- change to mailpit

## [0.1.1-beta13](https://github.com/epartment/rolldev/releases/tag/0.1.1-beta13) — 2023-07-18  *(tag only, no GitHub release)*

_No changes recorded beyond the tag itself._

## [0.1.0-beta14](https://github.com/epartment/rolldev/releases/tag/0.1.0-beta14) — 2023-08-29  *(tag only, no GitHub release)*

- change to mailpit
- fix project url in status command

## [0.1.0-beta13](https://github.com/epartment/rolldev/releases/tag/0.1.0-beta13) — 2023-07-18  *(tag only, no GitHub release)*

- Add a status command to view all running projects
- Adding Mailhog SMTP configuration documentation
- Remove unavailable command for public
- fix startpage image

## [0.1.0-beta12](https://github.com/epartment/rolldev/releases/tag/0.1.0-beta12) — 2023-05-24  *(tag only, no GitHub release)*

- Add dragonfly db as drop-in replacement of redis

## [0.1.0-beta11](https://github.com/epartment/rolldev/releases/tag/0.1.0-beta11) — 2023-04-24  *(tag only, no GitHub release)*

- add backup and restore commands
- docs change + url change

## [0.1.0-beta10](https://github.com/epartment/rolldev/releases/tag/0.1.0-beta10) — 2023-03-23  *(tag only, no GitHub release)*

- Update tag-release.yml
- error when downing all containers after upgrade fix.

## [0.1.0-beta9](https://github.com/epartment/rolldev/releases/tag/0.1.0-beta9) — 2023-03-22  *(tag only, no GitHub release)*

- added wordpress cli command + usage
- added reclu env help files usage
- change some non existing files and updated usage files
- add magepack cmd
- Small typo fix
- added magepack environment
- removed split files from adobe commerce
- Change some init values for magento 1 and 2
- Added reclu env type commands
- Changed .env to .env.roll
- Fix naming for images.
- fix typo
- Updated init versions
- Fix check installing ssh config for local user
- Moved env type commands to separate folder
- check for ssh config conflict
- Make Portainer and startpage optional
- moved images + added docs
- Cleanup apt files after build
- replace left over alpine builder with debian
- typo
- trigger php build
- update workflows
- fix mcrypt php8.2
- Bump golang from 1.19-alpine to 1.20-alpine in /images/mailhog
- add akeneo env

## [0.1.0-beta8](https://github.com/epartment/rolldev/releases/tag/0.1.0-beta8) — 2023-01-19  *(tag only, no GitHub release)*

- Bump golang from 1.18-alpine to 1.19-alpine in /images/mailhog
- move repo to github
- release new version
- Temporarily switch buildkit, instability github packages.
- Install extra php ext on env up if ROLL_EXTRA_PHP_EXT is defined
- Add ImageMagick and GraphicsMagick
- Install extra php extensions when configured
- start from port 3005
- fix typo
- Dynamic port allocation
- Added browsersync dynamic port option with cli info tool
- added include git env
- Fix gulp + grunt cli + add chrome-sandbox
- ADD chromium
- add PhantomJs
- add phantom
- Fix xdebug loading
- Add more caching
- Small fixes + xdebug hard path
- Added dnsmasq image to workflow
- Updated profiles
- Upgrade envs + seperated some processes
- fix
- Update some configs and github actions
- Fixed node binaries
- update workflows
- small fix in gitlab actions
- Fix not available packages debian
- Fix in github actions
- Temp disable image loading
- Reworked github actions + build pipeline
- Reworked github actions
- roll out php 7.2
- increase query size + retrigger image build
- set default database charset to utf8 as of requirements for typo3
- small fix for already enabled opcache extension
- redis 6.2 dev add
- use elasticsearch old
- fix images
- rebuild test
- add old mariadb version
- add testing data + images
- restore temp user 1000
- update fpm image with user 1000 fix
- refactor project type specific commands & startpage
- fix missing crucial part of routing nginx traffic
- fix owning uid on linux wrong user uid

## [0.1.0-beta7](https://github.com/epartment/rolldev/releases/tag/0.1.0-beta7) — 2022-11-03  *(tag only, no GitHub release)*

- change .env to .env.roll
- add more verbose logging to ownership when starting container
- add legacy php7.1

## [0.1.0-beta6](https://github.com/epartment/rolldev/releases/tag/0.1.0-beta6) — 2022-10-24  *(tag only, no GitHub release)*

- add placeholder for disabling static content on init
- add no static caching nginx conf magento 1
- make nginx template and public path configurable
- add rick to usage section
- typo wordpress
- update ci new versions
- add wordpress type images
- add wordpress ci
- move yarn npm to main and add wordpress image
- small fix + auto update images
- add vuejs project type + other fixes
- add laravel en vuejs nginx configs
- trigger
- fix fixperms command and add clinotty command for argument whitelist
- change xdebug and typo3 env to local
- add option for disabling static content caching
- change context to Development
- make all certs available in fpm container
- add typo3 configuration
- update all to version 3.9 and fix issue var compare
- fix typo
- add npm and node commands
- change order of command execution
- restore caching on files magento 2 config
- fix new line for status command  mutagen
- change xdebug configuration files
- fix build name
- add small start page for service domain
- add little progress to initial sync
- add grunt commands + fix param whitelist rootshell
- update elasticvue automatic resolver name
- update nginx config
- do not delete the production builded elasticvue files

## [0.1.0-beta5](https://github.com/epartment/rolldev/releases/tag/0.1.0-beta5) — 2022-08-22  *(tag only, no GitHub release)*

- new version
- add timeout for slow network building
- change elastichq to elasticvue

## [0.1.0-beta4](https://github.com/epartment/rolldev/releases/tag/0.1.0-beta4) — 2022-08-22  *(tag only, no GitHub release)*

- new version
- Update images + fix xdebug3
- changes to xdebug3 and magento 2 not working
- fix xdebug images not routing to 9000
- temp disable php8.2 because of xdebug 3 pickle bug
- change php compare function
- remove magerun older than php7.2
- make mhsendmail multiarch
- fix php image and add restart command
- updated images
- refactor images and commands
- remove old elastic version
- update elastic images
- change xdebug images
- add corn
- change docker entry point
- add version
- change builds

## [0.1.0-beta3](https://github.com/epartment/rolldev/releases/tag/0.1.0-beta3) — 2022-07-11  *(tag only, no GitHub release)*

- tag version
- xdebug 2 for 7.4 or lower
- change fpm config path
- change default shell to bash
- change alpine to debian cli images
- change typo

## [0.1.0-beta2](https://github.com/epartment/rolldev/releases/tag/0.1.0-beta2) — 2022-07-10  *(tag only, no GitHub release)*

- change in action triggers
- added multiarch version

## [0.1.0-beta1](https://github.com/epartment/rolldev/releases/tag/0.1.0-beta1) — 2022-07-10  *(tag only, no GitHub release)*

- change version
- update tools
- add build tag to buildx
- trigger build
- initial commit
