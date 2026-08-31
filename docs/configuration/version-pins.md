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

## New projects

`roll env-init` seeds `.env.roll` from the environment type's `init.env`, which pins everything that
type enables. Projects created with 0.8.0 or later start out fully pinned and never see the warning.

## Upgrading a version deliberately

Edit the value in `.env.roll` and bring the environment back up:

```bash
roll env down
roll env up
```

Changing a database or search-engine version usually means the existing data volume was written by
the old version. Check that engine's upgrade path first — RollDev only selects the image, it does
not migrate data.
