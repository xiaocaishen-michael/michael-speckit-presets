#!/usr/bin/env bash
# verify.sh — check installed presets in a target repo match the preset repo canonical
#
# Usage:
#   verify.sh --repo <abs-path> [--preset <id> ...]
#
# Effect: per installed preset
#   - sha256 of <target>/.specify/presets/<id>/templates/*  vs  <preset-repo>/presets/<id>/templates/*
#   - sha256 of <target>/.claude/commands/<file>            vs  <preset-repo>/presets/<id>/commands/<file>
#   - priority in <target>/.specify/presets/.registry       vs  <preset-repo>/presets/<id>/preset.yml
# Exit non-zero on any mismatch.
set -euo pipefail

PRESET_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_REPO=""
ONLY_PRESETS=()

die() { echo "❌ $*" >&2; exit 1; }
log() { echo "[verify.sh] $*"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo) TARGET_REPO="$2"; shift 2 ;;
        --preset) ONLY_PRESETS+=("$2"); shift 2 ;;
        -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "Unknown flag: $1" ;;
    esac
done

[[ -n "$TARGET_REPO" ]] || die "Missing --repo"
[[ -d "$TARGET_REPO/.specify/presets" ]] || { log "No installed presets at $TARGET_REPO"; exit 0; }

command -v python3 >/dev/null || die "python3 required"

# Pick a python invocation that has PyYAML available (system, or uv fallback).
if python3 -c "import yaml" 2>/dev/null; then
    PY_YAML=(python3)
elif command -v uv >/dev/null 2>&1; then
    PY_YAML=(uv run --with pyyaml --quiet -- python3)
else
    die "PyYAML required. Install via pip or install uv to enable the fallback."
fi

REGISTRY="$TARGET_REPO/.specify/presets/.registry"
[[ -f "$REGISTRY" ]] || die "Missing .registry at $REGISTRY"

# discover installed presets
mapfile -t INSTALLED < <(python3 -c "
import json
with open('$REGISTRY') as f:
    data = json.load(f)
for pid in sorted((data.get('presets') or {}).keys()):
    print(pid)
")

[[ ${#INSTALLED[@]} -gt 0 ]] || { log "No presets registered"; exit 0; }

FAIL=0
for id in "${INSTALLED[@]}"; do
    if [[ ${#ONLY_PRESETS[@]} -gt 0 ]]; then
        skip=true
        for w in "${ONLY_PRESETS[@]}"; do [[ "$w" == "$id" ]] && skip=false; done
        $skip && continue
    fi

    src="$PRESET_REPO_ROOT/presets/$id"
    if [[ ! -d "$src" ]]; then
        log "❌ $id installed but not in preset repo (orphan)"
        FAIL=$((FAIL+1))
        continue
    fi

    # priority check
    declared_prio=$("${PY_YAML[@]}" -c "import yaml; print(yaml.safe_load(open('$src/preset.yml')).get('priority', 10))")
    installed_prio=$(python3 -c "import json; print(json.load(open('$REGISTRY'))['presets']['$id'].get('priority'))")
    if [[ "$declared_prio" != "$installed_prio" ]]; then
        log "❌ $id priority mismatch: registry=$installed_prio canonical=$declared_prio"
        FAIL=$((FAIL+1))
    fi

    # templates checksum
    if [[ -d "$src/templates" ]]; then
        for f in "$src/templates"/*; do
            [[ -f "$f" ]] || continue
            rel=$(basename "$f")
            tgt="$TARGET_REPO/.specify/presets/$id/templates/$rel"
            if [[ ! -f "$tgt" ]]; then
                log "❌ $id missing installed template: $rel"
                FAIL=$((FAIL+1))
                continue
            fi
            if ! diff -q "$f" "$tgt" >/dev/null 2>&1; then
                log "❌ $id template drift: $rel"
                FAIL=$((FAIL+1))
            fi
        done
    fi

    # commands checksum
    if [[ -d "$src/commands" ]]; then
        for f in "$src/commands"/*; do
            [[ -f "$f" ]] || continue
            rel=$(basename "$f")
            tgt="$TARGET_REPO/.claude/commands/$rel"
            if [[ ! -f "$tgt" ]]; then
                log "❌ $id missing installed command: $rel"
                FAIL=$((FAIL+1))
                continue
            fi
            if ! diff -q "$f" "$tgt" >/dev/null 2>&1; then
                log "❌ $id command drift: $rel"
                FAIL=$((FAIL+1))
            fi
        done
    fi

    [[ $FAIL -eq 0 ]] && log "✅ $id ok"
done

if [[ $FAIL -gt 0 ]]; then
    log "FAIL: $FAIL mismatch(es). Re-run: $PRESET_REPO_ROOT/scripts/install.sh --repo $TARGET_REPO --preset <id>"
    exit 1
fi
log "All installed presets verified ✓"
