#!/usr/bin/env bash
# Builds the `upstream` branch: EVerest's lib/everest/{cbv2g,iso15118,slac,util} and LICENSE at the repo root, with
# their full history, the old standalone repos (libiso15118, libcbv2g, libslac) joined at the commits that
# integrated them. PR and issue references (#123) are qualified with the repo they belong to (EVerest/EVerest#123,
# EVerest/libiso15118#45, ...), so that GitHub links them there and not to this repo's PRs. Deterministic: the same
# inputs always give the same commit hashes.
#
# usage: build_upstream.sh <sources dir with EVerest.git libiso15118.git libcbv2g.git libslac.git> <paths.txt> <out.git> [everest ref]
set -euo pipefail
src=$(cd "$1" && pwd)
paths=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
out=$3
ref=${4:-main}

# Old repo, release that EVerest integrated, library folder, EVerest commit that integrated it.
joins=(
    "libiso15118 v0.9.1 iso15118 494b327d46b2e94cb4cbee002f654cdfeb893d19"
    "libcbv2g v0.3.2 cbv2g 61e97863fd2fc9f429f9cd2e4b689139e7d46981"
    "libslac v0.3.1 slac 4f8c3f192eb0c2b47e030ce3c4663ca74988a0bb"
)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A bare #123 (not already qualified like EVerest/libslac#12, not part of a word) -> <repo>#123.
qualify_refs() {
    printf 'regex:(?<![\\w/#])#([0-9]+)\\b==>EVerest/%s#\\1\n' "$1" >"$tmp/refs-$1.txt"
    echo "$tmp/refs-$1.txt"
}

git clone -q --bare --no-local --single-branch --branch "$ref" --no-tags "$src/EVerest.git" "$tmp/mirror.git"
for join in "${joins[@]}"; do
    read -r repo tag lib commit <<<"$join"
    git clone -q --bare --no-local "$src/$repo.git" "$tmp/$repo.git"
    git -C "$tmp/$repo.git" filter-repo --quiet --force --refs "$tag" --to-subdirectory-filter "lib/everest/$lib" \
        --replace-message "$(qualify_refs "$repo")"
    git -C "$tmp/mirror.git" fetch -q --no-tags "$tmp/$repo.git" "refs/tags/$tag:refs/tags/$repo-$tag"
    # shellcheck disable=SC2046
    git -C "$tmp/mirror.git" replace --graft "$commit" $(git -C "$tmp/mirror.git" rev-parse "$commit^@") \
        "$(git -C "$tmp/mirror.git" rev-parse "refs/tags/$repo-$tag^{commit}")" 2>/dev/null
done

git -C "$tmp/mirror.git" filter-repo --quiet --force --paths-from-file "$paths" \
    --replace-message "$(qualify_refs EVerest)"

rm -rf "$out"
mv "$tmp/mirror.git" "$out"
git -C "$out" branch -m "$ref" upstream
echo "upstream: $(git -C "$out" rev-parse upstream) ($(git -C "$out" rev-list --count upstream) commits)"
