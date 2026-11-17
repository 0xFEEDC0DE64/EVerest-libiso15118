#!/usr/bin/env bash
# Checks that <head> differs from <upstream> only in the paths listed in deviations.txt. Every other file must be
# identical to EVerest main. Listed paths that no longer differ are reported, so the list can be trimmed.
#
# usage: verify.sh [upstream ref] [head ref]
set -euo pipefail
base=${1:-upstream}
head=${2:-HEAD}
list=$(dirname "$0")/deviations.txt

allowed=()
while IFS= read -r line; do
    [[ -z $line || $line == \#* ]] && continue
    allowed+=("$line")
done <"$list"

covered() {
    local path=$1 entry
    for entry in "${allowed[@]}"; do
        if [[ $entry == */ ]]; then
            [[ $path == "$entry"* ]] && return 0
        else
            [[ $path == "$entry" ]] && return 0
        fi
    done
    return 1
}

changed=$(git diff --no-renames --name-only "$base" "$head")
fail=0
while IFS= read -r path; do
    [[ -z $path ]] && continue
    if ! covered "$path"; then
        echo "NOT ALLOWED: $path differs from $base"
        fail=1
    fi
done <<<"$changed"

for entry in "${allowed[@]}"; do
    if ! grep -q -- "^${entry//./\\.}" <<<"$changed"; then
        echo "note: $entry no longer differs from $base (can be removed from deviations.txt)"
    fi
done

count=$(grep -c . <<<"$changed" || true)
if [[ $fail -ne 0 ]]; then
    echo "FAILED: $head has changes outside deviations.txt"
    exit 1
fi
echo "OK: $count paths differ from $base, all listed in deviations.txt"
