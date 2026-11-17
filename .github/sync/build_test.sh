#!/bin/bash
# Builds and tests the four libraries of this repo inside EVerest: run in EVerest's CI build kit
# (.ci/build-kit/docker) on an EVerest checkout whose lib/everest/{cbv2g,iso15118,slac,util} were replaced by this
# repo's. Uses the CI options of .ci/build-kit/scripts/compile.sh and runs ctest -j as run_unit_tests.sh does.
#
# usage: build_test.sh <EVerest source> <build dir> <log dir>
set -o pipefail
source_dir=$1
build_dir=$2
log_dir=$3
mkdir -p "$log_dir"
libs="cbv2g iso15118 slac util"

if [ ! -f "$build_dir/build.ninja" ]; then
    cmake -S "$source_dir" -B "$build_dir" -G Ninja \
        -DCMAKE_BUILD_TYPE=Debug \
        -DEVC_ENABLE_CCACHE=1 \
        -DISO15118_2_GENERATE_AND_INSTALL_CERTIFICATES=OFF \
        -DBUILD_TESTING=ON \
        -DEVEREST_ENABLE_COMPILE_WARNINGS=ON \
        -DEVEREST_BUILD_APPLICATIONS=OFF \
        -DEVEREST_ENABLE_RUN_SCRIPT_GENERATION=OFF \
        >"$log_dir/configure.log" 2>&1 || { echo "configure failed"; tail -40 "$log_dir/configure.log"; exit 1; }
fi

targets=""
for lib in $libs; do
    targets="$targets lib/everest/$lib/all"
done
command -v ccache >/dev/null && ccache --zero-stats >/dev/null
# shellcheck disable=SC2086
ninja -C "$build_dir" -k 0 $targets >"$log_dir/build.log" 2>&1
build=$?
command -v ccache >/dev/null && ccache --show-stats | grep -iE "hits|misses|cache size" | head -4
grep -E "warning:|error:" "$log_dir/build.log" | sort -u | head -40
echo "build exit=$build"

result=$build
for lib in $libs; do
    (cd "$build_dir/lib/everest/$lib" && ctest -j "$(nproc)" --output-on-failure) >"$log_dir/ctest-$lib.log" 2>&1
    code=$?
    summary=$(grep -E "tests passed|No tests were found" "$log_dir/ctest-$lib.log" | tail -1)
    echo "$lib: ${summary:-no ctest summary} (exit=$code)"
    grep -E "\(Failed\)|\(Timeout\)|\(SEGFAULT\)|\(Subprocess aborted\)|Not Run" "$log_dir/ctest-$lib.log" | head -40
    [ $code -eq 0 ] || result=1
done
exit $result
