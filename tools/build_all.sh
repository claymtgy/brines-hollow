#!/usr/bin/env bash
# =====================================================================
# Brine's Hollow Multi-Platform Build Script (Linux / CI / Steam Deck)
# Usage:
#   ./tools/build_all.sh [target] [mode]
# Examples:
#   ./tools/build_all.sh all debug
#   ./tools/build_all.sh windows release
#   ./tools/build_all.sh server debug
# =====================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

TARGET="${1:-all}"
MODE="${2:-debug}"

# Resolve Godot binary
GODOT="${GODOT_BIN:-$(which godot 2>/dev/null || true)}"
if [ -z "$GODOT" ]; then
    echo "ERROR: 'godot' command not found in PATH and GODOT_BIN not set."
    exit 1
fi

echo "=================================================="
echo " Brine's Hollow Build Pipeline (Linux / CI)"
echo " Engine : $GODOT"
echo " Target : $TARGET"
echo " Mode   : $MODE"
echo "=================================================="

EXPORT_FLAG="--export-debug"
if [ "$MODE" = "release" ]; then
    EXPORT_FLAG="--export-release"
fi

build_target() {
    local preset="$1"
    local out_dir="$2"
    local out_file="$3"
    local full_path="$out_dir/$out_file"

    echo ""
    echo ">>> Building: $preset -> $full_path"
    mkdir -p "$out_dir"

    "$GODOT" --headless --path "$PROJECT_ROOT" "$EXPORT_FLAG" "$preset" "$full_path"
    echo "  [PASS] $preset created successfully."
}

case "$TARGET" in
    windows)
        build_target "Windows Desktop" "builds/windows" "BrinesHollow.exe"
        ;;
    linux)
        build_target "Linux Desktop" "builds/linux" "BrinesHollow.x86_64"
        ;;
    server)
        build_target "Dedicated Server" "builds/server" "BrinesHollowServer.x86_64"
        ;;
    server_win)
        build_target "Windows Dedicated Server" "builds/server_windows" "BrinesHollowServer.exe"
        ;;
    all)
        build_target "Windows Desktop" "builds/windows" "BrinesHollow.exe"
        build_target "Linux Desktop" "builds/linux" "BrinesHollow.x86_64"
        build_target "Dedicated Server" "builds/server" "BrinesHollowServer.x86_64"
        build_target "Windows Dedicated Server" "builds/server_windows" "BrinesHollowServer.exe"
        ;;
    *)
        echo "Unknown target: $TARGET (Valid: all, windows, linux, server, server_win)"
        exit 1
        ;;
esac

echo ""
echo "=================================================="
echo " All specified builds completed successfully!"
echo "=================================================="
