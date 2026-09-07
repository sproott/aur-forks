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

mapfile -t all_package_dirs < <(
    find . -name PKGBUILD -not -path './.git/*' -exec dirname {} \; \
        | sed 's|^\./||' \
        | sort -u
)

declare -A package_dirs_by_name selected visiting visited
for package_dir in "${all_package_dirs[@]}"; do
    while read -r package_name; do
        [[ -n "$package_name" ]] || continue
        package_dirs_by_name["$package_name"]=$package_dir
    done < <(awk '$1 == "pkgname" { print $3 }' "$package_dir/.SRCINFO")
done

local_dependency_dirs() {
    local package_dir=$1
    local dependency dependency_dir

    while read -r dependency; do
        dependency=${dependency%%[<>=]*}
        dependency_dir=${package_dirs_by_name[$dependency]:-}
        [[ -n "$dependency_dir" ]] && printf '%s\n' "$dependency_dir"
    done < <(
        awk '$1 == "depends" || $1 == "makedepends" || $1 == "checkdepends" { print $3 }' \
            "$package_dir/.SRCINFO"
    )
}

for package_dir in "${package_dirs[@]}"; do
    selected["$package_dir"]=1
done

added=true
while [[ "$added" == true ]]; do
    added=false

    for package_dir in "${!selected[@]}"; do
        while read -r dependency_dir; do
            if [[ -z "${selected[$dependency_dir]:-}" ]]; then
                selected["$dependency_dir"]=1
                added=true
            fi
        done < <(local_dependency_dirs "$package_dir")
    done
done

ordered_package_dirs=()
visit_package_dir() {
    local package_dir=$1
    local dependency_dir

    [[ -n "${visited[$package_dir]:-}" ]] && return 0

    if [[ -n "${visiting[$package_dir]:-}" ]]; then
        printf 'Circular local package dependency involving %s\n' "$package_dir" >&2
        exit 1
    fi

    visiting["$package_dir"]=1
    while read -r dependency_dir; do
        [[ -n "${selected[$dependency_dir]:-}" ]] && visit_package_dir "$dependency_dir"
    done < <(local_dependency_dirs "$package_dir")
    unset 'visiting[$package_dir]'
    visited["$package_dir"]=1
    ordered_package_dirs+=("$package_dir")
}

for package_dir in "${package_dirs[@]}"; do
    visit_package_dir "$package_dir"
done

package_dirs=("${ordered_package_dirs[@]}")

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

            if ! sudo pacman -U --noconfirm --needed -- "${package_files[@]}"; then
                printf 'Unable to install built package files for %s\n' "$package_dir" >&2
                exit 1
            fi
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