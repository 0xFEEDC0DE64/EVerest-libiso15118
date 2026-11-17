#!/usr/bin/env bash
# The deviations from EVerest are the patch files in patches/, applied in order onto `upstream`. esp32/main's library
# folders are exactly that result; nobody edits them by hand.
#
#   patches.sh build [base]             applies the patches onto <base> (default upstream) in a throwaway worktree and
#                                       prints the resulting commit. On failure it names the patch, and the files
#                                       that conflict, or that a patch is already in <base>.
#   patches.sh apply [base]             sets the library folders of the working tree to <base> + patches (staged).
#   patches.sh edit [base]              opens a worktree (path printed) on the branch patches/edit = <base> + one
#                                       commit per patch, keeping authors. Change it like any branch (commit, amend,
#                                       rebase -i); a patch that stops with a conflict is resolved there as in
#                                       `git am` (git add, git am --continue). Then run export from this checkout.
#   patches.sh export                   writes patches/ from patches/edit (one patch per commit on top of its base,
#                                       library folders only) and removes the worktree.
#   patches.sh verify [base] [head]     checks that <head> (default HEAD) is exactly <base> + the patches <head> has:
#                                       every file outside README.md, .github/ and patches/ must match, so a library
#                                       file changed without its patch fails.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
cd "$root"
libs=(cbv2g iso15118 slac util)
patch_dir=$root/patches
edit_branch=patches/edit
edit_dir=$(git rev-parse --absolute-git-dir)/patches-edit

patches() {
    find "$patch_dir" -maxdepth 1 -name '*.patch' | sort
}

# Applies the patches onto $1 in a throwaway worktree. Prints the resulting commit; on failure prints the reason to
# stderr and returns 1.
build() {
    local base=$1 work commit patch
    work=$(mktemp -d)
    git worktree add -q --detach "$work" "$base"
    for patch in $(patches); do
        # git am -3 would skip a patch whose change is already there without a word.
        if git -C "$work" apply -R --check "$patch" >/dev/null 2>&1; then
            echo "already-upstream $(basename "$patch")" >&2
            git worktree remove --force "$work"
            return 1
        fi
        # The commits only exist in this throwaway worktree: a fixed committer, so that it runs without a git
        # identity (CI). The author comes from the patch.
        if ! git -C "$work" -c user.name=patches.sh -c user.email=patches.sh@localhost \
            am -q -3 --whitespace=nowarn "$patch" >"$work.am.log" 2>&1; then
            local name conflicts
            name=$(basename "$patch")
            conflicts=$(git -C "$work" diff --name-only --diff-filter=U)
            git -C "$work" am --abort >/dev/null 2>&1 || true
            if [[ -n $conflicts ]]; then
                echo "conflict $name" >&2
                sed 's/^/  /' <<<"$conflicts" >&2
            else
                echo "error $name" >&2
                sed 's/^/  /' "$work.am.log" >&2
            fi
            rm -f "$work.am.log"
            git worktree remove --force "$work"
            return 1
        fi
    done
    commit=$(git -C "$work" rev-parse HEAD)
    rm -f "$work.am.log"
    git worktree remove --force "$work"
    echo "$commit"
}

# Checks that $2 is exactly $1 + the patches $2 has.
verify() {
    local base=$1 head=$2 work count expected differ
    work=$(mktemp -d)
    mkdir -p "$work/patches"
    if git cat-file -e "$head:patches" 2>/dev/null; then
        git archive "$head" patches | tar -x -C "$work"
    fi
    patch_dir=$work/patches
    count=$(patches | wc -l | tr -d ' ')
    if ! expected=$(build "$base" 2>"$work/build.err"); then
        echo "FAILED: the patches of $head do not apply onto $base:"
        cat "$work/build.err"
        rm -rf "$work"
        return 1
    fi
    rm -rf "$work"
    differ=$(git diff --no-renames --name-only "$expected" "$head" -- . ':!README.md' ':!.github' ':!patches')
    if [[ -n $differ ]]; then
        echo "FAILED: $head differs from $base + $count patches in:"
        sed 's/^/  /' <<<"$differ"
        return 1
    fi
    echo "OK: $head = $base + $count patches"
}

case ${1:-} in
verify)
    verify "${2:-upstream}" "${3:-HEAD}"
    ;;
build)
    build "${2:-upstream}"
    ;;
apply)
    commit=$(build "${2:-upstream}")
    git rm -r -q --cached --ignore-unmatch -- "${libs[@]}" LICENSE
    git checkout "$commit" -- "${libs[@]}" LICENSE
    # Files the patches delete must not stay behind in the working tree.
    git clean -q -f -d -- "${libs[@]}"
    echo "library folders = ${2:-upstream} + $(patches | wc -l | tr -d ' ') patches (staged)"
    ;;
edit)
    base=${2:-upstream}
    if [[ -d $edit_dir ]]; then
        git worktree remove --force "$edit_dir"
    fi
    git worktree add -q -B "$edit_branch" "$edit_dir" "$base"
    for patch in $(patches); do
        if git -C "$edit_dir" apply -R --check "$patch" >/dev/null 2>&1; then
            echo "$(basename "$patch") is already in $base: skipped. Delete it from patches/." >&2
            continue
        fi
        if ! git -C "$edit_dir" am -q -3 --whitespace=nowarn "$patch"; then
            echo
            echo "$(basename "$patch") stops with a conflict in $edit_dir:"
            git -C "$edit_dir" diff --name-only --diff-filter=U | sed 's/^/  /'
            echo "Resolve it there (git add, git am --continue; git am --skip drops the patch), then run" \
                ".github/sync/patches.sh export here."
            exit 1
        fi
    done
    echo "$edit_dir: $edit_branch = $base + $(patches | wc -l | tr -d ' ') patches."
    echo "Change it there, then run .github/sync/patches.sh export here."
    ;;
export)
    if [[ -e $edit_dir/.git ]] && [[ -d $(git -C "$edit_dir" rev-parse --git-path rebase-apply) ]]; then
        echo "$edit_dir: git am is still in progress; finish it first (git am --continue)." >&2
        exit 1
    fi
    base=$(git merge-base upstream "$edit_branch")
    out=$(mktemp -d)
    git format-patch -q --zero-commit --no-signature --no-stat -N -o "$out" "$base..$edit_branch" -- "${libs[@]}"
    git rm -q --ignore-unmatch -- "$patch_dir"/*.patch >/dev/null
    rm -f "$patch_dir"/*.patch
    mkdir -p "$patch_dir"
    cp "$out"/*.patch "$patch_dir"/ 2>/dev/null || true
    rm -rf "$out"
    git add "$patch_dir"
    [[ -d $edit_dir ]] && git worktree remove --force "$edit_dir"
    git branch -q -D "$edit_branch"
    echo "patches/ = $(patches | wc -l | tr -d ' ') patches from $base..$edit_branch (staged)."
    echo "Then: .github/sync/patches.sh apply"
    ;;
*)
    sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
