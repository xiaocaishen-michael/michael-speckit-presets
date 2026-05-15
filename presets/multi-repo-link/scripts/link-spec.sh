#!/usr/bin/env bash
# Usage: link-spec.sh <module>/<usecase> [--target server|app|both]
#
# Auto-symlink meta-canonical spec.md → sibling impl repos using relative paths
# (symlinks portable inside the git tree; safe across main / secondary worktrees).
# META_ROOT derived from the script's location (override with env var).
#
# Ships as part of `multi-repo-link` preset from michael-speckit-presets.
# Currently hardcoded for the project's three-repo layout:
#   meta   = META_ROOT
#   server = META_ROOT/my-beloved-server         (no prefix)
#   app    = META_ROOT/no-vain-years-app         (prefix: apps/native/)
# To adapt for a different layout, edit the case "$TARGET" block below
# and the matching repo paths.

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
[[ -n "$REL_PATH" ]] || { echo "Usage: link-spec.sh <module>/<usecase> [--target server|app|both]" >&2; exit 2; }

CANONICAL_DIR="${META_ROOT}/specs/${REL_PATH}"
[[ -d "$CANONICAL_DIR" ]] || { echo "❌ canonical dir missing: $CANONICAL_DIR" >&2; exit 1; }
[[ -f "${CANONICAL_DIR}/spec.md" ]] || { echo "❌ spec.md missing in canonical: ${CANONICAL_DIR}/spec.md" >&2; exit 1; }

relpath() {
    local from_dir="$1" to_path="$2"
    python3 -c "import os.path,sys; print(os.path.relpath(sys.argv[2], sys.argv[1]))" "$from_dir" "$to_path"
}

link_one() {
    local repo="$1" prefix="$2"
    local impl_dir="${META_ROOT}/${repo}/${prefix}specs/${REL_PATH}"
    mkdir -p "$impl_dir"
    if [[ -L "${impl_dir}/spec.md" || ! -e "${impl_dir}/spec.md" ]]; then
        local rel
        rel=$(relpath "$impl_dir" "${CANONICAL_DIR}/spec.md")
        ln -sfn "$rel" "${impl_dir}/spec.md"
    fi
    # clarify/Clarifications stay inline inside spec.md — no separate symlink needed
    if [[ -f "${CANONICAL_DIR}/user-journey.md" ]]; then
        local rel
        rel=$(relpath "$impl_dir" "${CANONICAL_DIR}/user-journey.md")
        ln -sfn "$rel" "${impl_dir}/user-journey.md"
    fi
    # contracts/ intentionally NOT linked — assumes code-first OpenAPI (e.g. springdoc).
    echo "✅ linked: ${impl_dir}"
}

case "$TARGET" in
    server) link_one "my-beloved-server" "" ;;
    app)    link_one "no-vain-years-app" "apps/native/" ;;
    both)
        link_one "my-beloved-server" ""
        link_one "no-vain-years-app" "apps/native/"
        ;;
    *) echo "Unknown --target: $TARGET (must be server|app|both)" >&2; exit 2 ;;
esac
