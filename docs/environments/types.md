# Environment Types

RollDev currently supports three environment types. These types are passed to `env-init` when configuring a project for local development for the first time. This list of environment types can also be seen by running `roll env-init --help` on your command line. The `docker-compose` configuration used to assemble each environment type can be found in the [environments directory](https://github.com/epartment/rolldev/tree/master/environments) on Github.

`roll env-init` follows RollDev's flag/env-first prompt convention: if you pass a project name and type as arguments (`roll env-init myproject magento2`), it runs non-interactively and never prompts. Leave either out on a terminal and it prompts for the missing value; leave either out with no terminal attached (CI, a script) and it errors naming the argument you need to supply instead of hanging. Re-running `env-init` where a `.env.roll` already exists normally asks whether to overwrite it; set `ROLL_ENV_INIT_FORCE=1` to overwrite without prompting.

## Local

The `local` environment type is a network-only container — it provides no services of its own. Use it when you need RollDev's networking layer (Traefik, dnsmasq, the shared tunnel) but want to define your own services in a `.roll/roll-env.yml` file.

**Required:** Every usable `local` project must provide its own `.roll/roll-env.yml` defining which containers to run. If you use the default service toggles (which default to enabled), `roll env config` will fail because it expects those services to be defined in your custom compose fragment.

**To use the `local` type:**

1. Run `roll env-init myproject local`
2. Create `.roll/roll-env.yml` in your project root with your desired services (nginx, php-fpm, db, etc.)
3. Set service toggles to 0 in `.env.roll` for any services you are NOT providing in your custom fragment: `ROLL_NGINX=0`, `ROLL_DB=0`, etc.
4. Run `roll env up`

**Platform-specific overrides:** RollDev supports `roll-env.darwin.yml` and `roll-env.linux.yml` for macOS/Linux differences, following the same pattern as other environment types.

For an example, see the [m2demo project](https://github.com/davidalger/m2demo).

## Magento 2

The `magento2` environment type provides necessary containerized services for running Magento 2 in a local development context including:

* Nginx
* Varnish
* PHP-FPM (7.0+)
* MariaDB
* Elasticsearch
* RabbitMQ
* Redis

In order to achieve a well performing experience on macOS, files in the webroot are synced into the container using a Mutagen sync session with the exception of `pub/media` which remains mounted using a delegated mount.

## Magento Cloud

The `magento-cloud` environment type uses `magento2` as a base and adds the versions of the services used by your Magento Cloud project.

## Magento 1

The `magento1` environment type supports development of Magento 1 projects, launching containers including:

* Nginx
* PHP-FPM (5.5, 5.6 or 7.0+)
* MariaDB
* Redis

Files are currently mounted using a delegated mount on macOS and natively on Linux.

## Laravel

The `laravel` environment type supports development of Laravel projects, launching containers including:

* Nginx
* PHP-FPM
* MariaDB
* Redis

Files are currently mounted using a delegated mount on macOS and natively on Linux.

## Symfony

The `symfony` environment type supports development of Symfony 4+ projects, launching containers including:

* Nginx
* PHP-FPM
* MariaDB
* Redis
* RabbitMQ (disabled by default)
* Varnish (disabled by default)
* Elasticsearch (disabled by default)

Files are currently mounted using a delegated mount on macOS and natively on Linux.

## Shopware

The `shopware` environment type supports development of Shopware 6 projects, launching containers including:

* Nginx
* PHP-FPM
* MariaDB
* Redis
* RabbitMQ (disabled by default)
* Varnish (disabled by default)
* Elasticsearch (disabled by default)

In order to achieve a well performing experience on macOS, files in the webroot are synced into the container using a Mutagen sync session with the exception of `public/media` which remains mounted using a delegated mount.

## WordPress

The `wordpress` environment type supports development of WordPress projects, launching containers including:

* Nginx
* PHP-FPM
* MariaDB

Files are currently mounted using a delegated mount on macOS and natively on Linux.

## Akeneo

The `akeneo` environment type supports development of Akeneo projects, launching containers including:

* Nginx
* PHP-FPM
* MySQL

Files are currently mounted using a delegated mount on macOS and natively on Linux.

## Commonalities

In addition to the above, each environment type (with the exception of the `local` type) come with PHP setup to use `mhsendmail` to ensure outbound email does not inadvertently leave your network and to support simpler testing of email functionality. Mailhog may be accessed by navigating to [https://mailhog.roll.test/](https://mailhog.roll.test/) in a browser.

Where PHP is specified in the above list, there should be two `fpm` containers, `php-fpm` and `php-debug` in order to provide Xdebug support. Use of Xdebug is enabled by setting the `XDEBUG_SESSION` cookie in your browser to direct the request to the `php-debug` container. Shell sessions opened in the debug container via `roll debug` will also connect PHP process for commands on the CLI to Xdebug.

The configuration of each environment leverages a `base` configuration YAML file, and optionally a `darwin` and `linux` file to add to `base` configuration anything which may be specific to a given host architecture (this is, for example, how the `magento2` environment type works seamlessly on macOS with Mutagen sync sessions while using native filesystem mounts on Linux hosts).

## Rolling your own environment type

If an environment type is missing above, you might want to create your own. This is completely supported. Just like RollDev's environments are defined in `/opt/roll/environments`, it is possible to define your own in your user home, namely `~/.roll/environments` and in your project directory as well, namely `<project_dir>/.roll/environments`.