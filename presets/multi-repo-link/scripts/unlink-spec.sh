#!/usr/bin/env bash
# Usage: unlink-spec.sh <module>/<usecase> [--target server|app|both]
#
# Replace impl-repo (server / app) spec.md / user-journey.md symlinks with
# materialized file copies. Used at archival time to detach an impl repo from
# the meta-canonical for that use case (so the impl repo becomes self-contained).
#
# Ships as part of `multi-repo-link` preset from michael-speckit-presets.
# See link-spec.sh header for the three-repo layout assumption.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
META_ROOT="${META_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

REL_PATH=""
TARGET="both"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) TARGET="$2"; shift 2 ;;
        --*) echo "Unknown flag: $1" >&2; exit 2 ;;
        *)   [[ -z "$REL_PATH" ]] && REL_PATH="$1"; shift ;;
    esac
done
[[ -n "$REL_PATH" ]] || { echo "Usage: unlink-spec.sh <module>/<usecase> [--target server|app|both]" >&2; exit 2; }

unlink_one() {
    local repo="$1" prefix="$2"
    local impl_dir="${META_ROOT}/${repo}/${prefix}specs/${REL_PATH}"
    for f in spec.md user-journey.md; do
        local target="${impl_dir}/${f}"
        if [[ -L "$target" ]]; then
            local resolved
            resolved=$(readlink -f "$target")
            rm "$target"
            cp "$resolved" "$target"
            echo "✅ unlink (now copy): $target → $resolved"
        elif [[ -e "$target" ]]; then
            echo "ℹ️  already file (not symlink): $target"
        fi
    done
}

case "$TARGET" in
    server) unlink_one "my-beloved-server" "" ;;
    app)    unlink_one "no-vain-years-app" "apps/native/" ;;
    both)
        unlink_one "my-beloved-server" ""
        unlink_one "no-vain-years-app" "apps/native/"
        ;;
    *) echo "Unknown --target: $TARGET (must be server|app|both)" >&2; exit 2 ;;
esac
