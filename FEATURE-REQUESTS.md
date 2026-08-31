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

None outstanding.

### Medium

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

**L3. `local` environment type fails compose render when service toggles are at default** — `environments/local/local.base.yml`, `commands/env.cmd:51,112`

- *What:* The `local` environment type skips the `php-fpm` partial but still appends nginx, db, and
  redis partials when their toggles are on. Since those toggles default to `1`, a bare
  `roll env-init x local && roll env config` fails with `service "php-fpm" has neither an image
  nor a build context specified`, because an appended fragment declares a dependency on php-fpm.
  **Verified** against a throwaway project pre-milestone-4. The failure predates this release.
- *Why it matters:* The `local` type advertises itself as usable without providing services, yet it
  fails unless the user disables toggles or provides services in `.roll/roll-env.yml` — the contract
  is unclear from the error message, and a user exploring the type hits a confusing failure.
- *Suggested fix:* No change to code or behaviour; this is documented in `docs/environments/types.md`
  and the local environment type's default init.env with clear instructions. The type should stay
  (per decision D7) because users may have existing projects using it. Closing this as Low because
  the workaround is documented and the type is niche (most environments are magento2/laravel/etc.).

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
