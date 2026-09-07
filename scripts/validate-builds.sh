#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
container_image="${CONTAINER_IMAGE:-archlinux:base-devel}"

if [[ -n "${CONTAINER_ENGINE:-}" ]]; then
    container_engine="$CONTAINER_ENGINE"
elif command -v podman >/dev/null 2>&1; then
    container_engine=podman
elif command -v docker >/dev/null 2>&1; then
    container_engine=docker
else
    printf 'Podman or Docker is required.\n' >&2
    exit 1
fi

"$container_engine" run --rm \
    --network host \
    --volume "$repo_root:/workspace:ro" \
    --volume "$repo_root/.makepkg-src-cache:/var/cache/makepkg/src" \
    --volume "$repo_root/.stack-cache:/var/cache/makepkg/stack" \
    "$container_image" \
    bash -c '
        set -euo pipefail
        pacman -Sy --noconfirm git sudo
        install -d -m 777 /var/cache/makepkg/src
        install -d -m 777 /var/cache/makepkg/stack
        export STACK_ROOT=/var/cache/makepkg/stack
        install -d /etc/makepkg.conf.d
        printf "SRCDEST=/var/cache/makepkg/src\n" > /etc/makepkg.conf.d/source-cache.conf
        mkdir /build
        cp -a /workspace/. /build/
        cd /build
        git config --global --add safe.directory /build
        git clean -dffX
        useradd --create-home builder
        printf "builder ALL=(ALL) NOPASSWD: ALL\n" > /etc/sudoers.d/builder
        chown -R builder:builder /build
        sudo -H -u builder ./scripts/build-packages.sh "$@"
    ' bash "$@"