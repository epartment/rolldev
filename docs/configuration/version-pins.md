# Service version pins

Every service RollDev starts runs a specific image tag — `nginx:1.27`, `mariadb:10.4`,
`elasticsearch:7.17`. Those versions come from your project's `.env.roll`.

## What changed in 0.8.0

Before 0.8.0, a version you did not set fell back to a default built into RollDev itself. That made
the version a property of *your installed RollDev* rather than of your project: upgrading RollDev
could change which PHP or database image a project ran, without the project changing at all. Two
people on the same branch could be running different images.

From 0.8.0, RollDev warns when an enabled service has no version pinned:

```
WARNING: This magento2 environment enables services whose versions are not pinned.
WARNING: Roll is falling back to a built-in version, which means upgrading roll can silently
WARNING: change which image this project runs. From 0.9.0 this will be an error.
WARNING: These are the versions the project is running right now - run `roll config fix-pins`
WARNING: to write them into .env.roll, or add them by hand:

    NGINX_VERSION=1.27
```

**Nothing breaks in 0.8.0.** The fallback still applies, and it is deliberately the version your
project was already running — so the warning never comes with a change in behaviour. In 0.9.0 the
fallback is removed and a missing pin becomes an error.

## Fixing it

```bash
roll config fix-pins
```

This appends the missing pins to `.env.roll`, using the versions the project runs today, after
taking a timestamped backup. Because the values are the ones already in effect, running it never
changes which images come up — verify with `roll env config` before and after if you want to see
that for yourself.

To see what is missing without writing anything:

```bash
roll config check-pins
```

It lists the missing pins and exits `1` when there are any, so a script or CI job can gate on it.

## Which versions are required

`PHP_VERSION` and `NODE_VERSION` are required for every environment type except `local`, which
never starts a PHP container. Beyond that, a version is required only when its service is switched
on:

| Service toggle | Version variable |
|---|---|
| `ROLL_NGINX` | `NGINX_VERSION` |
| `ROLL_DB` | `DB_DISTRIBUTION_VERSION` |
| `ROLL_REDIS` | `REDIS_VERSION` |
| `ROLL_DRAGONFLY` | `DRAGONFLY_VERSION` |
| `ROLL_VARNISH` | `VARNISH_VERSION` |
| `ROLL_ELASTICSEARCH` | `ELASTICSEARCH_VERSION` |
| `ROLL_OPENSEARCH` | `OPENSEARCH_VERSION` |
| `ROLL_RABBITMQ` | `RABBITMQ_VERSION` |
| `ROLL_MONGODB` | `MONGO_VERSION` |
| `ROLL_MAGEPACK` | `MAGEPACK_VERSION` |
| `ROLL_SELENIUM` | `ROLL_SELENIUM_VERSION` |

Turning a service off removes its pin requirement.

## Global config does not count as a pin

A version set in `~/.roll/.env` or `~/.roll/.env.roll` is loaded before your project's `.env.roll`,
so it resolves — but it pins nothing. It lives on your machine, not in the repository, so a
colleague who does not have that line gets a different image from the same branch, which is exactly
what pinning exists to prevent. `check-pins` therefore still reports such a version as missing.

`fix-pins` writes the value you are inheriting, not RollDev's built-in default, so pinning it does
not change the image your environment comes up with:

```bash
# ~/.roll/.env carries PHP_VERSION=8.3, the project pins nothing
roll config fix-pins     # writes PHP_VERSION=8.3 into .env.roll
```

## New projects

`roll env-init` seeds `.env.roll` from the environment type's `init.env`, which pins everything that
type enables. Projects created with 0.8.0 or later start out fully pinned and never see the warning.

## Seeing what you pin today

```bash
roll config versions
```

```
  SERVICE        KEY                        VERSION      STATUS
  php            PHP_VERSION                8.3          enabled
  node           NODE_VERSION               22           enabled
  mariadb        DB_DISTRIBUTION_VERSION    10.4         enabled
  mysql          DB_DISTRIBUTION_VERSION    <unpinned>   not selected (DB_DISTRIBUTION=mariadb)
  elasticsearch  ELASTICSEARCH_VERSION      8.11         enabled
  opensearch     OPENSEARCH_VERSION         <unpinned>   disabled (ROLL_OPENSEARCH=0)
  ...
```

One row per service RollDev can run: the key that holds its version, the version this project
pins, and whether the service is switched on. An `<unpinned>` row for an enabled service is what
`check-pins` reports.

## Upgrading a version deliberately

```bash
roll config version
```

This asks which service to change, then offers the versions that service's image actually has, and
writes your choice into `.env.roll` after taking a timestamped backup. The version list is read
from the registry RollDev pulls from, so it is never a list someone has to keep up to date — a
version that exists is offered, and one that does not is not.

Skip either prompt by naming the service, or the service and the version:

```bash
roll config version php              # choose from the PHP versions the image is built for
roll config version php 8.3          # set PHP_VERSION=8.3 without prompting
```

To see the choices without changing anything:

```bash
roll config versions php
```

The list comes back newest first, one version per line, so it can be piped. It is cached for an
hour per image; `ROLL_TAG_CACHE_TTL=0 roll config versions php` refetches.

Three services need a word of explanation:

- **Node** ships inside the PHP image, as a `-nodeNN` suffix on its tag, so the Node versions on
  offer are the ones built for the PHP version you have pinned. `NODE_VERSION=0` is offered too,
  and means an image with no Node at all.
- **The database** has one version key for two engines. Picking `mysql` on a MariaDB project (or
  the reverse) switches `DB_DISTRIBUTION` as well, and asks first — the existing database volume
  was written by the other engine and will not be readable. Dump the database, recreate the volume
  with `roll env down -v`, then import it again.
- **Selenium** is the one image not published under `$ROLL_IMAGE_REPOSITORY`, and Docker Hub's
  `selenium/standalone-chrome` carries thousands of tags in several shapes, so RollDev asks you to
  type the version rather than offering a list.

Either way the command only edits `.env.roll`. Bring the environment back up to apply it:

```bash
roll env down
roll env up
```

Changing a database or search-engine version usually means the existing data volume was written by
the old version. Check that engine's upgrade path first — RollDev only selects the image, it does
not migrate data.

You can still edit `.env.roll` by hand; nothing about the file has changed.
