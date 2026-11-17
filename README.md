# EVerest-libiso15118

The ISO 15118 libraries of [EVerest](https://github.com/EVerest/EVerest), on their own, with their full history:

| Folder | Library | In EVerest |
|---|---|---|
| [`iso15118/`](iso15118) | libiso15118: SDP, the ISO 15118-20, ISO 15118-2 and DIN 70121 sessions | `lib/everest/iso15118` |
| [`cbv2g/`](cbv2g) | libcbv2g: EXI encoders and decoders | `lib/everest/cbv2g` |
| [`slac/`](slac) | libslac: SLAC (ISO 15118-3) | `lib/everest/slac` |
| [`util/`](util) | everest-util: helpers the libraries above use | `lib/everest/util` |

This is an unofficial mirror, not a project of LF Energy or EVerest. Bugs in the libraries belong upstream:
[EVerest/EVerest](https://github.com/EVerest/EVerest). It exists for firmware that uses these four libraries without
the rest of EVerest, for example on a microcontroller: a small repo to pin as a git submodule, with every change from
upstream reviewed in a pull request.

The folders are EVerest's, file for file. The few deviations are listed below and checked on every pull request.

## Branches and tags

| Ref | Content |
|---|---|
| `upstream` | EVerest main, reduced to the four libraries and `LICENSE`. Generated, never edited by hand. |
| `esp32/main` (default) | `upstream` plus the deviations below, this README and the CI. |
| `esp32-YYYY.MM.DD` | Releases of `esp32/main`. Pin these. |
| `libiso15118-v0.9.1`, `libcbv2g-v0.3.2`, `libslac-v0.3.1` | The standalone releases EVerest integrated. |

All deviations at once: `git diff upstream esp32/main`, or
[compare `upstream...esp32/main`](https://github.com/vampirebyte/EVerest-libiso15118/compare/upstream...esp32/main) (append `.diff` for plain text).

## Deviations from EVerest main

| Deviation | Files | Why |
|---|---|---|
| libslac's state machines on `fsm::v2` instead of Boost.MSM ([EVerest/EVerest#3106](https://github.com/EVerest/EVerest/pull/3106)) | `slac/` (see [`deviations.txt`](.github/sync/deviations.txt)), `util/include/everest/util/fsm/fsm.hpp` | No Boost.MSM templates: plain state classes that build on embedded toolchains with less code. EVerest main's later fixes to the EVSE machine (EVerest/EVerest#3133, EVerest/EVerest#3166, EVerest/EVerest#3328, EVerest/EVerest#3334) are ported onto it. |
| No `SO_REUSEPORT` on lwIP | `iso15118/src/iso15118/io/sdp_server.cpp` | lwIP (ESP-IDF) does not implement the option; the SDP server would not start. To be removed once ESP-IDF has the lwIP fix. |

Everything else is identical to EVerest main, including the README, `THIRD_PARTY.md` and `LICENSE` files of the
libraries. [`.github/sync/verify.sh`](.github/sync/verify.sh) fails any change outside
[`deviations.txt`](.github/sync/deviations.txt).

## Using it

As a submodule, pinned to a release tag:

```bash
git submodule add https://github.com/vampirebyte/EVerest-libiso15118.git third_party/everest
git -C third_party/everest checkout esp32-YYYY.MM.DD
git config -f .gitmodules submodule.third_party/everest.shallow true
```

The include paths are `iso15118/include`, `cbv2g/include`, `slac/include` and `util/include`; the sources are under
`src/` (`cbv2g/lib/` for cbv2g).

## History

The history goes back to the first commit of each library, with every original author, date and message:

- `iso15118/`, `cbv2g/`: the standalone repos [EVerest/libiso15118](https://github.com/EVerest/libiso15118) up to
  v0.9.1 and [EVerest/libcbv2g](https://github.com/EVerest/libcbv2g) up to v0.3.2, then EVerest. The commit that
  integrated each one into EVerest is a merge with the standalone history as its second parent.
- `slac/`: EVerest's SLAC module (from 2020), `lib/staging/slac`, then `lib/everest/slac`; plus
  [EVerest/libslac](https://github.com/EVerest/libslac) up to v0.3.1, joined at the commit that integrated it.
- `util/`: EVerest's `lib/staging/util`, then `lib/everest/util`, plus files moved in from elsewhere.

Rewriting the history to four folders gives new commit hashes, so:

- PR and issue references name their repo, for example `EVerest/EVerest#3385` or `EVerest/libiso15118#45`, so that
  they link there and not to this repo's pull requests.
- References to other commits in messages ("This reverts commit ...") point to the new hashes.
- GPG signatures of the original commits do not carry over. The originals stay verifiable in EVerest.

Some files were rewritten so heavily in one commit that git's default rename detection loses them. Lower the
threshold to follow them back, for example:

```bash
git log --follow -M10% -- slac/src/fsm/evse/context.cpp
```

## Syncing with EVerest

[`sync.yml`](.github/workflows/sync.yml) runs every Monday and on demand:

1. Rebuilds `upstream` from EVerest main and the standalone repos with
   [`build_upstream.sh`](.github/sync/build_upstream.sh) (git filter-repo). The result is deterministic: the same
   inputs give the same hashes, so a sync only adds commits to `upstream`.
2. Merges it into a `sync/<date>-<sha>` branch made from `esp32/main`, runs the deviation check, and opens a pull
   request with the list of upstream commits. On conflicts the pull request says how to finish the merge.
3. A person reviews and merges it, then tags a release.

It stops for a person when EVerest moves another folder into the four libraries
([`trace_paths.py`](.github/sync/trace_paths.py) finds new history sources), because updating
[`paths.txt`](.github/sync/paths.txt) rewrites every hash.

Locally: `pip install git-filter-repo==2.47.0`, then `.github/sync/sync.sh /tmp/sources` in a checkout with the
branches `upstream` and `esp32/main`.

Pull requests the workflow opens do not trigger other workflows (a GitHub rule for its token); their text includes
the result of the deviation check.

## License

Apache-2.0, like EVerest: see [`LICENSE`](LICENSE). Third-party code and its licenses are listed in
[`iso15118/THIRD_PARTY.md`](iso15118/THIRD_PARTY.md) and [`cbv2g/THIRD_PARTY.md`](cbv2g/THIRD_PARTY.md).

The libraries are the work of the EVerest contributors; see the history and
[EVerest](https://github.com/EVerest/EVerest).
