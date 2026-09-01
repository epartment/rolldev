# RollDev 0.8.0 — draft release notes

Draft for the GitHub release. Not published; `docs/changelog.md` points at the releases page rather
than carrying a changelog, so this is the text to paste there when tagging.

---

## Upgrade notes — read these two first

### Unpinned service versions now warn, and will be an error in 0.9.0

Until now, a service version you did not set in `.env.roll` fell back to a default built into
RollDev. That made the version a property of *your installed RollDev* rather than of the project:
upgrading RollDev could change which PHP or database image a project ran, and two people on the same
branch could be running different images.

From 0.8.0 an enabled service with no version pinned prints a warning. **Nothing breaks** — the
fallback still applies, and it is deliberately the version the project was already running, so the
warning never comes with a change in behaviour. In 0.9.0 the fallback is removed.

```bash
roll config check-pins    # list what is missing; exits 1 if any
roll config fix-pins      # write them, after taking a backup
```

`fix-pins` writes the versions the project runs today, so running it never changes which images come
up. Measured across 48 local projects while developing this release, 34 needed at least one pin —
most commonly `NGINX_VERSION`, which no environment type had ever pinned.

A version set in global config (`~/.roll/.env` or `~/.roll/.env.roll`) resolves, but does **not**
count as a pin: it lives on your machine rather than in the repository, so a colleague without that
line still gets a different image from the same branch. Such a version is reported as missing, and
`fix-pins` writes the value you are inheriting rather than RollDev's built-in default — so pinning it
does not change what comes up either. If you keep versions in global config, expect `check-pins` to
have something to say about every project.

### gum is now a dependency

Every interactive prompt goes through [gum](https://github.com/charmbracelet/gum) (≥ 0.14.0). The
Homebrew formula declares it, so `brew upgrade` pulls it in.

gum is needed **only for prompts**. Every prompt is also reachable by flag, environment variable or
positional argument, so scripted and CI use works without it, and `roll install` warns rather than
failing when it is absent.

---

## Environments come up correctly for magento2

A `magento2` project whose `.env.roll` did not spell out the toggles resolved `ROLL_VARNISH=0`,
`ROLL_ELASTICSEARCH=0` and `ROLL_RABBITMQ=0`, so those services never started. The environment-type
defaults ran *after* the schema defaults had already filled the variables in, which made every
`${VAR:-1}` in that code unreachable. Configuration loading is reordered so the type defaults apply
first, and `commands/env.cmd` no longer keeps a second copy of the same logic.

## Driving RollDev without a terminal

New in this release, documented in [docs/machine-interface.md](docs/machine-interface.md):

- `--format json` on `roll status`, `roll env describe`, `roll registry list` and `roll env doctor`.
  No ANSI, no credentials, values properly escaped.
- `roll has-command <name>` — exit 0/1, no output, for feature detection.
- `roll env up --wait` — returns only once services report healthy. Healthchecks are defined for db,
  redis, elasticsearch, opensearch, rabbitmq, varnish and nginx; the search engines are probed
  through `/_cluster/health` rather than a port, because those containers can hold a port open while
  the cluster inside them is dead.
- `roll env doctor` — seventeen checks, exit 0/1, human or JSON.
- Every prompt resolves flag/env first, uses gum only on a TTY, and otherwise fails naming the flag
  that would have answered it. A prompt can no longer hang an unattended run.

Note that containers created before this release report no health status, so `--wait` has nothing to
wait on for them. Recreate an environment once after upgrading.

## New and moved commands

- `roll env sh <service> '<command>'` — runs the command through `sh -c` inside the container, so
  redirects and pipes apply there instead of on the host.
- `roll config check-pins` / `roll config fix-pins`.
- `roll env doctor`, `roll has-command`.
- `copyfromcontainer`, `copytocontainer`, `magento2/theme` and `convert` move in from the internal
  command pack, each with its outstanding bugs fixed in transit — among them `copytocontainer
  <folder>` copying the whole project root into the destination, `copyfromcontainer --realpath`
  building a destination path that could not exist, `theme` forcing one build tool across every
  theme in the project, and `convert` writing a static-caching key no schema defines.

## Fixes worth calling out

- `roll db` works against MariaDB 11, which ships only `mariadb-dump`/`mariadb` and dropped the
  `mysql*` compatibility symlinks.
- `roll registry categories` no longer dies on macOS — it used a bash 4 expansion under a bash 3.2
  shell.
- `roll backup --help` and `roll status --help` no longer exit 2 on macOS. bash 3.2 mis-parses a lone
  apostrophe inside a heredoc nested in `$( )`, and CI ran Ubuntu only, where it parses fine.
- `roll db/env/redis/svc/restore/restore-full/duplicate --help` no longer fork until killed. Those
  commands take arbitrary flags, so roll hands `--help` straight to them, and each re-invoked itself.
- `roll restore` prints "No backups found" instead of dying on an internal error.
- `roll env describe` is back to ~1s; resolving each service separately had made it ~9s.
- `isOnline` no longer always reports offline on Linux (`ping -t` is a timeout on BSD and a TTL on
  GNU), so `roll svc up` refreshes images there.
- WSL environments now get the `.linux.yml` compose fragments.
- `roll fixowns`/`roll fixperms` accept more than one path.
- Traefik's docker socket is mounted read-only.

## Known issue

**A restored Elasticsearch volume is unwritable.** After `roll restore`, the volume root comes back
owned by uid 0 while the image runs as uid 1000, so Elasticsearch exits at boot with
`failed to test writes in data directory`. The database restores correctly. This predates 0.8.0; it
is newly *visible* because `env up --wait` and the healthchecks now catch it instead of the
environment appearing to come up fine. Tracked as H1 in the README.

## For contributors

- ShellCheck runs on macOS as well as Ubuntu, over `commands/**`, the help files, `utils/` and the
  CI scripts, and it passes on both. Note that Ubuntu ships ShellCheck 0.9.0 while Homebrew has
  0.11.0, and the older version raises four findings the newer one does not, so a clean local run
  is not proof the gate is green.
- A smoke suite runs on both platforms: the Docker-free command set, a prompt-contract harness, and
  a parse check that catches the bash 3.2 heredoc trap and any command that re-invokes its own help.
- `utils/interact.sh`, `utils/backup.sh` and `utils/magento2-init.sh` are new shared libraries.
