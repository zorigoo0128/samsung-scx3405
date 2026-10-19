#!/bin/bash
# Build the SpliX print filters (arm64) from the vendored source.
#
# Output: third_party/splix/optimized/{rastertoqpdl,pstoqpdl}
#
# Requires only the Xcode command line tools: build-tools/pkg-config pins the
# CUPS flags to the system SDK, so the filters link against /usr/lib/libcups*
# and have no third-party runtime dependency.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/third_party/splix"

[ -d "$SRC/src" ] || { echo "error: vendored SpliX source not found at $SRC" >&2; exit 1; }

chmod +x "$HERE/build-tools/pkg-config"
cd "$SRC" || exit 1

make clean >/dev/null 2>&1
PATH="$HERE/build-tools:$PATH" make DISABLE_JBIG=1 CC=clang CXX=clang++ -j"$(sysctl -n hw.ncpu)"
status=$?

if [ "$status" -eq 0 ]; then
  ls -l "$SRC/optimized/rastertoqpdl" "$SRC/optimized/pstoqpdl"
fi
exit "$status"
