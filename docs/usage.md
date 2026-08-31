# RollDev Usage

## Common Commands

### Project Initialization

Create a new Magento 2 project (automated setup):

    roll magento2-init myproject 2.4.7

Launch a shell session within the project environment's `php-fpm` container:

    roll shell

For use with alternative shells, see the
[Alternative Shells](configuration/alternative-shells.md) page

Stopping a running environment:

    roll env stop

Starting a stopped environment:

    roll env start

Import a database (if you don't have `pv` installed, use `cat` instead):

    pv /path/to/dump.sql.gz | gunzip -c | roll db import

Monitor database processlist:

    watch -n 3 "roll db connect -A -e 'show processlist'"

Tail environment nginx and php logs:

    roll env logs --tail 0 -f nginx php-fpm php-debug

Tail the varnish activity log:

    roll env exec -T varnish varnishlog

Flush varnish:

     roll env exec -T varnish varnishadm 'ban req.url ~ .' 

Run a shell command inside a container (with proper redirect handling):

    roll env sh php-fpm 'cat app/etc/env.php | grep MODE'

Copy a file from the container to the host, or the whole project back in after a rebuild (see the
[Copying files between host and container](configuration/copy-container.md) page for the full flag
list, including cachegrind/trace profile pickup):

    roll copyfromcontainer vendor/autoload.php
    roll copytocontainer --all

Connect to redis:

    roll redis

Flush redis completely:

    roll redis flushall

Run redis continuous stat mode

    roll redis --stat

Remove volumes completely:

    roll env down -v

Build every Magento 2 frontend theme found under `app/design/frontend`:

    roll theme all

Build or watch one theme directly, without the interactive picker:

    roll theme Vendor/theme build
    roll theme Vendor/theme watch

## Converting a Warden Project

Run from the root of a Warden project to convert it to RollDev: renames `WARDEN_*` variables to
`ROLL_*`, moves `.env` to `.env.roll` and `.warden` to `.roll`, validates the result, then signs a
certificate and starts the environment.

    roll convert

Existing service version pins (including `ELASTICSEARCH_VERSION`) are left as the project had
them. If a pin is missing afterwards, `roll config validate` reports a warning; run
`roll config fix-pins` to write one in. `roll convert` does nothing if `.env.roll` already exists
or `.env` does not reference `WARDEN`.

## Environment Duplication

Duplicate the current environment to create a new environment with a different name:

    roll duplicate new-environment-name

Create an encrypted duplicate:

    roll duplicate staging-env --encrypt

Preview what would be duplicated without executing:

    roll duplicate test-env --dry-run

For detailed duplication documentation, see the [Environment Duplication](duplicate.md) page.

## Backup and Restore Commands

Create a backup of all enabled services:

    roll backup

Create a backup of specific services:

    roll backup db
    roll backup redis

List available backups:

    roll backup list

Show backup information:

    roll backup info 1672531200

Restore the latest backup:

    roll restore

Restore a specific backup:

    roll restore 1672531200

Preview what would be restored:

    roll restore --dry-run

For detailed backup and restore documentation, see the [Backup and Restore](backup-restore.md) page.

## Further Information

Run `roll help` and `roll env -h` for more details and useful command information.
