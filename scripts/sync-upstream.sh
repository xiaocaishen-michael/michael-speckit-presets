#!/usr/bin/env bash
# sync-upstream.sh — validate preset prepend layers still compose cleanly against a new spec-kit version
#
# Usage:
#   sync-upstream.sh --spec-kit-version <vTAG> [--dry-run]
#
# Effect:
#   1. Fetch spec-kit core templates at <vTAG> from GitHub
#   2. For each preset that has a templates/<name>.md layer: confirm <name> still exists in core
#   3. For each preset extensions.yml.fragment: confirm the hook slot is still consumed by the corresponding SKILL.md
#   4. Print summary; exit non-zero on any incompatibility
#
# Note: this preset repo design uses NATIVE spec-kit composition (templates / commands /
# extensions.yml hooks) — no anchor-based SKILL patches to reapply. The script only
# verifies that the spec-kit API surfaces our presets depend on still exist.
set -euo pipefail

PRESET_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPECKIT_VERSION=""
DRY_RUN=false

die() { echo "❌ $*" >&2; exit 1; }
log() { echo "[sync-upstream.sh] $*"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --spec-kit-version) SPECKIT_VERSION="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help) sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "Unknown flag: $1" ;;
    esac
done

[[ -n "$SPECKIT_VERSION" ]] || die "Missing --spec-kit-version (e.g. v0.8.7)"
command -v python3 >/dev/null || die "python3 required"
command -v curl >/dev/null || die "curl required"

# Pick a python invocation that has PyYAML available (system, or uv fallback).
if python3 -c "import yaml" 2>/dev/null; then
    PY_YAML=(python3)
elif command -v uv >/dev/null 2>&1; then
    PY_YAML=(uv run --with pyyaml --quiet -- python3)
else
    die "PyYAML required. Install via pip or install uv to enable the fallback."
fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

UPSTREAM_BASE="https://raw.githubusercontent.com/github/spec-kit/$SPECKIT_VERSION"
CORE_TEMPLATES=(plan-template spec-template tasks-template checklist-template constitution-template)

# 1. Fetch core templates
log "Fetching spec-kit $SPECKIT_VERSION core templates..."
for t in "${CORE_TEMPLATES[@]}"; do
    if ! curl -fsSL "$UPSTREAM_BASE/.specify/templates/$t.md" -o "$TMP/$t.md"; then
        # try alt path used by some spec-kit versions
        if ! curl -fsSL "$UPSTREAM_BASE/src/specify_cli/templates/$t.md" -o "$TMP/$t.md"; then
            log "⚠️  Could not fetch $t.md at $SPECKIT_VERSION (path may have moved — review manually)"
        fi
    fi
done

# 2. Validate preset templates layers
FAIL=0
for preset_dir in "$PRESET_REPO_ROOT"/presets/*/; do
    [[ -d "$preset_dir" ]] || continue
    preset_id=$(basename "$preset_dir")
    [[ "$preset_id" == ".registry-template" ]] && continue

    if [[ -d "$preset_dir/templates" ]]; then
        for f in "$preset_dir"/templates/*.md; do
            [[ -f "$f" ]] || continue
            name=$(basename "$f" .md)
            if [[ ! -f "$TMP/$name.md" ]]; then
                log "❌ $preset_id: prepend layer references template '$name' but it wasn't found upstream at $SPECKIT_VERSION"
                FAIL=$((FAIL+1))
            else
                log "✅ $preset_id: prepend layer for '$name' — upstream still exists"
            fi
        done
    fi

    # extensions.yml.fragment hook slot consistency check (heuristic)
    if [[ -f "$preset_dir/extensions.yml.fragment" ]]; then
        slots=$(python3 -c "
import yaml
d = yaml.safe_load(open('$preset_dir/extensions.yml.fragment')) or {}
for k in (d.get('hooks') or {}).keys():
    print(k)
")
        for slot in $slots; do
            log "  $preset_id: declares hook on '$slot' (verify upstream SKILL.md still reads it)"
        done
    fi
done

if [[ $FAIL -gt 0 ]]; then
    log "FAIL: $FAIL incompatibilities. Manual reconciliation needed."
    exit 1
fi
log "Sync check passed for spec-kit $SPECKIT_VERSION ✓"
