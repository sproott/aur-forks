# Pacman package registry

## Validate packages locally

Build every package in a disposable Arch Linux container:

```sh
./scripts/validate-builds.sh
```

Pass package directories to validate a subset:

```sh
./scripts/validate-builds.sh awscurl-git awsd-git
```

The script uses Podman when available, otherwise Docker. Override the engine or
image with `CONTAINER_ENGINE` and `CONTAINER_IMAGE`.

GitHub Actions and the container validator both call
`scripts/build-packages.sh`. That script discovers package directories when none
are supplied, builds unresolved local dependencies in retry passes, and installs
successful packages before continuing.