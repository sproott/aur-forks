#!/usr/bin/env bash
# Prints the contents of a pacman package archive without build-time metadata
# (build date, packager, .BUILDINFO, .MTREE), so two builds of identical
# content produce identical output.

set -euo pipefail

archive=$(realpath "$1")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

bsdtar -xf "$archive" -C "$work"
cd "$work"

grep -Ev '^(builddate|packager|size) = ' .PKGINFO
find . -mindepth 1 ! -path ./.PKGINFO ! -path ./.BUILDINFO ! -path ./.MTREE \
    -printf '%y %m %p %l\n' | LC_ALL=C sort
find . -type f ! -path ./.PKGINFO ! -path ./.BUILDINFO ! -path ./.MTREE \
    -exec sha256sum {} + | LC_ALL=C sort -k2
