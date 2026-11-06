#!/bin/sh
# Builds the Brine's Hollow native extension into ../bin.
#   ./build.sh            debug template (used by editor + dev runs)
#   ./build.sh release    release template (exports, Steam Deck builds)
set -e
cd "$(dirname "$0")"
TARGET=template_debug
[ "$1" = "release" ] && TARGET=template_release
cmake -S . -B "build-$TARGET" -DGODOTCPP_TARGET=$TARGET -DCMAKE_BUILD_TYPE=Release
cmake --build "build-$TARGET" -j"$(nproc)"
