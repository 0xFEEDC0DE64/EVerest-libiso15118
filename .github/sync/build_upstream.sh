#!/usr/bin/env bash
# Builds the `upstream` branch: EVerest's lib/everest/{cbv2g,iso15118,slac,util} and LICENSE at the repo root, with
# their full history, the old standalone repos (libiso15118, libcbv2g, libslac) joined at the commits that
# integrated them. PR and issue references (#123) are qualified with the repo they belong to (EVerest/EVerest#123,
# EVerest/libiso15118#45, ...), so that GitHub links them there and not to this repo's PRs. Deterministic: the same
# inputs always give the same commit hashes.
#
# An old repo that is missing from the sources, or lacks its release tag, is rebuilt from this repo's own copy of its
# history (tags libiso15118-v0.9.1, ...), given as [fallback repo]; the result is the same.
#
# usage: build_upstream.sh <sources dir with EVerest.git and the old repos of upstream.conf> <paths.txt> <out.git>
#                          [everest ref] [fallback repo]
set -euo pipefail
src=$(cd "$1" && pwd)
paths=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
out=$3
ref=${4:-main}
fallback=${5:-}

conf=$(dirname "$paths")/upstream.conf

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A bare #123 (not already qualified like EVerest/libslac#12, not part of a word) -> <repo>#123.
qualify_refs() {
    printf 'regex:(?<![\\w/#])#([0-9]+)\\b==>EVerest/%s#\\1\n' "$1" >"$tmp/refs-$1.txt"
    echo "$tmp/refs-$1.txt"
}

git clone -q --bare --no-local --single-branch --branch "$ref" --no-tags "$src/EVerest.git" "$tmp/mirror.git"
while read -r kind repo tag lib commit; do
    [[ $kind == join ]] || continue
    if git -C "$src/$repo.git" rev-parse -q --verify "refs/tags/$tag^{commit}" >/dev/null 2>&1; then
        git clone -q --bare --no-local "$src/$repo.git" "$tmp/$repo.git"
    elif [[ -n $fallback ]] && git -C "$fallback" rev-parse -q --verify "refs/tags/$repo-$tag^{commit}" >/dev/null; then
        # This repo's copy has the folder prefix and qualified references; stripping the prefix gives the original
        # layout, and qualifying again changes nothing.
        echo "$repo $tag: not in the sources, rebuilt from tag $repo-$tag of $fallback"
        git init -q --bare "$tmp/$repo.git"
        git -C "$tmp/$repo.git" fetch -q --no-tags "$fallback" "refs/tags/$repo-$tag:refs/tags/$tag"
        git -C "$tmp/$repo.git" filter-repo --quiet --force --refs "$tag" --path-rename "$lib/:"
    else
        echo "$repo $tag: missing from the sources and no fallback" >&2
        exit 1
    fi
    git -C "$tmp/$repo.git" filter-repo --quiet --force --refs "$tag" --to-subdirectory-filter "lib/everest/$lib" \
        --replace-message "$(qualify_refs "$repo")"
    git -C "$tmp/mirror.git" fetch -q --no-tags "$tmp/$repo.git" "refs/tags/$tag:refs/tags/$repo-$tag"
    # shellcheck disable=SC2046
    git -C "$tmp/mirror.git" replace --graft "$commit" $(git -C "$tmp/mirror.git" rev-parse "$commit^@") \
        "$(git -C "$tmp/mirror.git" rev-parse "refs/tags/$repo-$tag^{commit}")" 2>/dev/null
done <"$conf"

git -C "$tmp/mirror.git" filter-repo --quiet --force --paths-from-file "$paths" \
    --replace-message "$(qualify_refs EVerest)"

rm -rf "$out"
mv "$tmp/mirror.git" "$out"
git -C "$out" branch -m "$ref" upstream
echo "upstream: $(git -C "$out" rev-parse upstream) ($(git -C "$out" rev-list --count upstream) commits)"
