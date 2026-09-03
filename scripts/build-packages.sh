#!/usr/bin/env bash

set -uo pipefail

output_dir=""
dry_run=false
package_dirs=()

while (($# > 0)); do
    case "$1" in
        --output)
            output_dir="$2"
            shift 2
            ;;
        --dry-run)
            dry_run=true
            shift
            ;;
        --help)
            printf 'Usage: %s [--output DIR] [--dry-run] [PACKAGE_DIR ...]\n' "$0"
            exit 0
            ;;
        --*)
            printf 'Unknown option: %s\n' "$1" >&2
            exit 2
            ;;
        *)
            package_dirs+=("$1")
            shift
            ;;
    esac
done

if ((${#package_dirs[@]} == 0)); then
    mapfile -t package_dirs < <(
        find . -name PKGBUILD -not -path './.git/*' -exec dirname {} \; \
            | sed 's|^\./||' \
            | sort -u
    )
fi

if "$dry_run"; then
    printf '%s\n' "${package_dirs[@]}"
    exit 0
fi

if [[ -n "$output_dir" ]]; then
    mkdir -p "$output_dir"
    output_dir="$(realpath "$output_dir")"
fi

pending=("${package_dirs[@]}")
while ((${#pending[@]} > 0)); do
    progress=false
    deferred=()

    for package_dir in "${pending[@]}"; do
        [[ -n "$package_dir" ]] || continue
        printf '==> Building %s\n' "$package_dir"
        rm -f -- "$package_dir"/*.pkg.tar.zst

        if (cd "$package_dir" && makepkg --syncdeps --noconfirm --needed --force); then
            package_files=("$package_dir"/*.pkg.tar.zst)

            if [[ -n "$output_dir" ]]; then
                cp -- "${package_files[@]}" "$output_dir/"
            fi

            sudo pacman -U --noconfirm --needed -- "${package_files[@]}"
            progress=true
        else
            deferred+=("$package_dir")
        fi
    done

    if [[ "$progress" != true ]]; then
        printf 'Unable to build: %s\n' "${deferred[*]}" >&2
        exit 1
    fi

    pending=("${deferred[@]}")
done