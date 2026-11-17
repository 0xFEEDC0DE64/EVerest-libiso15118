#!/usr/bin/env bash
# Syncs with EVerest main: rebuilds `upstream` from the sources, checks that it only adds commits, applies patches/ on
# it, and commits the result on the branch sync/everest-main made from esp32/main, with upstream as second parent.
# Pushes nothing: the workflow pushes and opens the PR.
#
# usage: sync.sh <sources dir> [everest ref]
#   <sources dir> holds bare clones of EVerest and of the old repos in upstream.conf (their release tag only); missing
#   ones are cloned.
# Run inside a checkout of this repo with the branches upstream and esp32/main.
# Writes sync.env (status, branch, ...) and sync-pr.md (PR text) to the sources dir.
# Exit codes: 0 synced or up to date, 1 error, 2 needs a person (paths changed, not a fast-forward).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
src=$(mkdir -p "$1" && cd "$1" && pwd)
ref=${2:-main}
env_file=$src/sync.env
pr_file=$src/sync-pr.md
: >"$env_file"
: >"$pr_file"

if [[ -d $src/EVerest.git ]]; then
    git -C "$src/EVerest.git" fetch -q --prune origin '+refs/heads/*:refs/heads/*'
else
    git clone -q --bare --no-tags "https://github.com/EVerest/EVerest.git" "$src/EVerest.git"
fi
# Only the release each old repo was integrated at. If GitHub no longer has it, build_upstream.sh rebuilds it from
# this repo's own tags (fallback below).
while read -r kind repo tag _; do
    [[ $kind == join ]] || continue
    [[ -d $src/$repo.git ]] || git init -q --bare "$src/$repo.git"
    git -C "$src/$repo.git" fetch -q --no-tags "https://github.com/EVerest/$repo.git" "+refs/tags/$tag:refs/tags/$tag" \
        || echo "warning: could not fetch $repo $tag from GitHub, using this repo's copy"
done <"$here/upstream.conf"
everest=$(git -C "$src/EVerest.git" rev-parse "$ref")

# New moves into the four libraries change the paths file, and that rewrites the whole history: a person decides.
if ! diff -u "$here/paths.txt" <(python3 "$here/trace_paths.py" "$src/EVerest.git" "$ref") >"$src/paths.diff"; then
    echo "status=paths-changed" >>"$env_file"
    echo "The history sources changed (see paths.diff). Updating paths.txt rewrites every commit hash:" \
        "review it, regenerate upstream and push it by hand."
    cat "$src/paths.diff"
    exit 2
fi

"$here/build_upstream.sh" "$src" "$here/paths.txt" "$src/upstream.git" "$ref" "$(git rev-parse --show-toplevel)"
git fetch -q --no-tags "$src/upstream.git" "+upstream:refs/sync/upstream"
old=$(git rev-parse upstream)
new=$(git rev-parse refs/sync/upstream)

if [[ $old == "$new" ]]; then
    echo "status=up-to-date" >>"$env_file"
    echo "Up to date with EVerest $ref ${everest:0:9}."
    exit 0
fi
if ! git merge-base --is-ancestor "$old" "$new"; then
    echo "status=not-fast-forward" >>"$env_file"
    echo "The rebuilt upstream ${new:0:9} does not contain the current ${old:0:9}: not a fast-forward."
    exit 2
fi

git branch -f upstream "$new"
# One sync branch: sync.yml updates an open sync pull request instead of opening another.
branch=sync/everest-main
git checkout -q -B "$branch" esp32/main
{
    echo "branch=$branch"
    echo "upstream=$new"
    echo "everest=$everest"
} >>"$env_file"

{
    echo "Syncs \`esp32/main\` with EVerest main [\`${everest:0:9}\`](https://github.com/EVerest/EVerest/commit/$everest)."
    echo
    echo "Upstream commits ($(git rev-list --count "$old..$new")):"
    echo
    git log --format='- %s (%an)' "$old..$new"
    echo
} >>"$pr_file"

libs=(cbv2g iso15118 slac util)
if patched=$("$here/patches.sh" build upstream 2>"$src/patches.err"); then
    # The library folders become the new upstream + patches; README.md, .github/ and patches/ stay as they are. The
    # sync commit has upstream as second parent, so esp32/main carries its whole history.
    git rm -r -q --cached --ignore-unmatch -- "${libs[@]}" LICENSE
    git checkout "$patched" -- "${libs[@]}" LICENSE
    git clean -q -f -d -- "${libs[@]}"
    # build.yml builds the libraries inside EVerest at this commit.
    sed -i.bak "s/^everest .*/everest $everest/" "$here/upstream.conf" && rm "$here/upstream.conf.bak"
    git add "$here/upstream.conf"
    commit=$(git commit-tree "$(git write-tree)" -p HEAD -p upstream -m "Sync with EVerest main ${everest:0:9}")
    git reset -q --hard "$commit"
    if verify=$("$here/patches.sh" verify upstream HEAD 2>&1); then
        echo "status=synced" >>"$env_file"
    else
        echo "status=verify-failed" >>"$env_file"
    fi
    {
        echo "Patch check:"
        echo
        echo '```'
        echo "$verify"
        echo '```'
    } >>"$pr_file"
else
    read -r kind patch <"$src/patches.err"
    if [[ $kind == already-upstream ]]; then
        echo "status=patch-upstream" >>"$env_file"
        {
            echo "**\`patches/$patch\` is in EVerest now.** This branch is \`esp32/main\` without the sync. Drop the"
            echo "patch and finish the sync:"
        } >>"$pr_file"
        fix="git rm -q patches/$patch"
    else
        echo "status=patch-conflict" >>"$env_file"
        {
            echo "**\`patches/$patch\` does not apply to the new upstream.** This branch is \`esp32/main\` without"
            echo "the sync. Conflicting files:"
            echo
            tail -n +2 "$src/patches.err" | sed 's/^ */- /'
            echo
            echo "Update the patch and finish the sync:"
        } >>"$pr_file"
        fix=".github/sync/patches.sh edit   # resolve in the printed worktree: git add, git am --continue
.github/sync/patches.sh export"
    fi
    {
        echo
        echo '```'
        echo "git fetch origin && git switch $branch && git branch -f upstream origin/upstream"
        echo "git merge -s ours --no-commit upstream   # upstream becomes the second parent"
        echo "$fix"
        echo ".github/sync/patches.sh apply"
        echo "sed -i.bak 's/^everest .*/everest $everest/' .github/sync/upstream.conf && rm .github/sync/upstream.conf.bak"
        echo "git add -A"
        echo "git commit -s -m \"Sync with EVerest main ${everest:0:9}\""
        echo ".github/sync/patches.sh verify upstream HEAD && git push"
        echo '```'
    } >>"$pr_file"
fi
cat "$env_file"
