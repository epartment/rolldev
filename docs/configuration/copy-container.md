# Copying files between host and container

`roll copyfromcontainer` and `roll copytocontainer` copy files between the project directory on the
host and `/var/www/html` inside the `php-fpm` container, without going through a bind mount.

## copyfromcontainer

```
roll copyfromcontainer vendor/autoload.php
```

Copies the given file or folder from the container to the same relative path on the host.

```
roll copyfromcontainer --all
```

Copies the entire project source from the container to the host.

```
roll copyfromcontainer --cachegrind [file]
roll copyfromcontainer --traces [file]
```

Copies a cachegrind profile or xdebug trace from `/tmp` inside the `php-debug` container into
`tmp/profiles` or `tmp/traces` in the project directory. Without a file argument this prompts
interactively for which file to copy (requires a terminal); non-interactively, pass the filename
explicitly.

```
roll copyfromcontainer --realpath <file>
```

Copies an absolute container path into the project `tmp` folder, instead of the default
`/var/www/html`-relative path.

## copytocontainer

```
roll copytocontainer vendor
```

Copies the given file or folder from the host into the container, then runs `roll fixowns` and
`roll fixperms` on that path.

```
roll copytocontainer --all
```

Copies the entire project source from the host into the container, then runs `roll fixowns` and
`roll fixperms` for the whole project. Useful after a container rebuild to restore files that only
existed inside the previous container.
