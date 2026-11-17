#!/usr/bin/env bash
# Syncs with EVerest main: rebuilds `upstream` from the sources, checks that it only adds commits, and merges it
# into a new sync/<date>-<sha> branch made from esp32/main. Pushes nothing: the workflow pushes and opens the PR.
#
# usage: sync.sh <sources dir> [everest ref]
#   <sources dir> holds bare clones EVerest.git libiso15118.git libcbv2g.git libslac.git; missing ones are cloned.
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

for repo in EVerest libiso15118 libcbv2g libslac; do
    if [[ -d $src/$repo.git ]]; then
        git -C "$src/$repo.git" fetch -q --prune origin '+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*'
    else
        git clone -q --bare "https://github.com/EVerest/$repo.git" "$src/$repo.git"
    fi
done
everest=$(git -C "$src/EVerest.git" rev-parse "$ref")

# New moves into the four libraries change the paths file, and that rewrites the whole history: a person decides.
if ! diff -u "$here/paths.txt" <(python3 "$here/trace_paths.py" "$src/EVerest.git" "$ref") >"$src/paths.diff"; then
    echo "status=paths-changed" >>"$env_file"
    echo "The history sources changed (see paths.diff). Updating paths.txt rewrites every commit hash:" \
        "review it, regenerate upstream and push it by hand."
    cat "$src/paths.diff"
    exit 2
fi

"$here/build_upstream.sh" "$src" "$here/paths.txt" "$src/upstream.git" "$ref"
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
branch="sync/$(date -u +%Y-%m-%d)-${everest:0:9}"
git checkout -q -B "$branch" esp32/main
{
    echo "branch=$branch"
    echo "upstream=$new"
    echo "everest=$everest"
} >>"$env_file"

{
    echo "Merges EVerest main [\`${everest:0:9}\`](https://github.com/EVerest/EVerest/commit/$everest) into \`esp32/main\`."
    echo
    echo "Upstream commits ($(git rev-list --count "$old..$new")):"
    echo
    git log --format='- %s (%an)' "$old..$new"
    echo
} >>"$pr_file"

if git merge -q --no-ff --no-edit -m "Merge EVerest main ${everest:0:9} into esp32/main" upstream; then
    if verify=$("$here/verify.sh" upstream HEAD 2>&1); then
        echo "status=merged" >>"$env_file"
    else
        echo "status=verify-failed" >>"$env_file"
    fi
    {
        echo "Deviation check:"
        echo
        echo '```'
        echo "$verify"
        echo '```'
    } >>"$pr_file"
else
    conflicts=$(git diff --name-only --diff-filter=U)
    git merge --abort
    echo "status=conflict" >>"$env_file"
    {
        echo "**The merge has conflicts.** This branch is \`esp32/main\` without the merge. To finish it:"
        echo
        echo '```'
        echo "git fetch origin && git checkout $branch && git merge origin/upstream"
        echo "# resolve, then: git commit && .github/sync/verify.sh upstream HEAD && git push"
        echo '```'
        echo
        echo "Conflicting files:"
        echo
        sed 's/^/- /' <<<"$conflicts"
    } >>"$pr_file"
fi
cat "$env_file"
