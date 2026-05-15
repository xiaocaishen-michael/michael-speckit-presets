#!/usr/bin/env bash
# install.sh — install one or more michael-speckit-presets into a target spec-kit repo
#
# Usage:
#   install.sh --repo <abs-path> --preset <id> [--preset <id> ...] [--unlock] [--dry-run]
#
# Effects per preset:
#   1. Copy preset/<id>/templates/*.md  →  <repo>/.specify/presets/<id>/templates/
#   2. Copy preset/<id>/commands/*.md   →  <repo>/.claude/commands/
#   3. Merge preset/<id>/extensions.yml.fragment → <repo>/.specify/extensions.yml (PyYAML merge)
#   4. Copy preset/<id>/scripts/*       →  <repo>/scripts/
#   5. Write/merge <repo>/.specify/presets/.registry (priority from preset.yml)
#   6. Append audit log to <repo>/.specify/presets/.install.log (preset repo HEAD sha + timestamp)
#   7. Pre-flight: detect legacy task-closure C1-C4 SKILL fork → abort with cleanup instructions
#
# Concurrency: `flock` on <repo>/.specify/presets/.registry to avoid race.
set -euo pipefail

PRESET_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_REPO=""
PRESETS=()
UNLOCK=false
DRY_RUN=false

usage() {
    sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 2
}

die() { echo "❌ $*" >&2; exit 1; }
log() { echo "[install.sh] $*"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo) TARGET_REPO="$2"; shift 2 ;;
        --preset) PRESETS+=("$2"); shift 2 ;;
        --unlock) UNLOCK=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help) usage ;;
        *) die "Unknown flag: $1 (use --help)" ;;
    esac
done

[[ -n "$TARGET_REPO" ]] || die "Missing --repo <abs-path>"
[[ -d "$TARGET_REPO" ]] || die "Target repo not found: $TARGET_REPO"
[[ -d "$TARGET_REPO/.specify" ]] || die "Target is not a spec-kit project (no .specify/): $TARGET_REPO"
[[ ${#PRESETS[@]} -gt 0 ]] || die "At least one --preset required"

command -v python3 >/dev/null || die "python3 required"
python3 -c "import yaml" 2>/dev/null || die "PyYAML required (pip install pyyaml)"

PRESETS_DIR="$TARGET_REPO/.specify/presets"
REGISTRY_FILE="$PRESETS_DIR/.registry"
AUDIT_LOG="$PRESETS_DIR/.install.log"
EXTENSIONS_FILE="$TARGET_REPO/.specify/extensions.yml"

mkdir -p "$PRESETS_DIR"
[[ -f "$REGISTRY_FILE" ]] || echo '{"presets":{}}' > "$REGISTRY_FILE"

PRESET_REPO_SHA=$(git -C "$PRESET_REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Pre-flight: legacy task-closure SKILL fork detection
preflight_task_closure_legacy() {
    local skill_path="$TARGET_REPO/.claude/skills/speckit-implement/SKILL.md"
    [[ -f "$skill_path" ]] || return 0
    if grep -q 'localCustomized:[[:space:]]*true' "$skill_path"; then
        cat >&2 <<EOF

⚠️  Detected legacy task-closure C1-C4 SKILL fork at:
    $skill_path

The task-closure preset uses spec-kit 0.8.7 native composition (templates +
hooks + slash command) instead. Restore vanilla SKILL.md and remove fork
artifacts first:

    $PRESET_REPO_ROOT/scripts/cleanup-task-closure-legacy.sh --repo "$TARGET_REPO"

Skipping preset install until legacy fork is cleaned up.
EOF
        exit 1
    fi
}

for p in "${PRESETS[@]}"; do
    [[ "$p" == "task-closure" ]] && preflight_task_closure_legacy
done

# install_one <preset_id>
install_one() {
    local id="$1"
    local src="$PRESET_REPO_ROOT/presets/$id"
    [[ -d "$src" ]] || die "Preset not found: $id ($src)"
    [[ -f "$src/preset.yml" ]] || die "Preset missing preset.yml: $id"

    log "Installing preset: $id"

    # priority + applies_to from preset.yml
    local prio
    prio=$(python3 -c "import yaml,sys; print(yaml.safe_load(open('$src/preset.yml')).get('priority', 10))")

    if [[ "$DRY_RUN" == true ]]; then
        log "  (dry-run) would install $id with priority=$prio"
        return 0
    fi

    # 1. templates
    if [[ -d "$src/templates" ]]; then
        mkdir -p "$PRESETS_DIR/$id/templates"
        cp -a "$src/templates/." "$PRESETS_DIR/$id/templates/"
        # copy preset.yml as manifest
        cp "$src/preset.yml" "$PRESETS_DIR/$id/preset.yml"
        log "  templates → $PRESETS_DIR/$id/templates/"
    fi

    # 2. commands
    if [[ -d "$src/commands" ]]; then
        mkdir -p "$TARGET_REPO/.claude/commands"
        cp -a "$src/commands/." "$TARGET_REPO/.claude/commands/"
        log "  commands → $TARGET_REPO/.claude/commands/"
    fi

    # 3. extensions.yml.fragment → merge into target extensions.yml
    if [[ -f "$src/extensions.yml.fragment" ]]; then
        merge_extensions_fragment "$src/extensions.yml.fragment"
        log "  extensions.yml ← merged $id fragment"
    fi

    # 4. scripts
    if [[ -d "$src/scripts" ]]; then
        mkdir -p "$TARGET_REPO/scripts"
        cp -a "$src/scripts/." "$TARGET_REPO/scripts/"
        chmod +x "$TARGET_REPO/scripts"/*.sh 2>/dev/null || true
        log "  scripts → $TARGET_REPO/scripts/"
    fi

    # 5. .registry update
    SPECKIT_REGISTRY="$REGISTRY_FILE" SPECKIT_PID="$id" SPECKIT_PRIO="$prio" python3 <<'PY'
import json, os
reg = os.environ["SPECKIT_REGISTRY"]
with open(reg) as f:
    data = json.load(f)
data.setdefault("presets", {})
data["presets"][os.environ["SPECKIT_PID"]] = {
    "priority": int(os.environ["SPECKIT_PRIO"]),
    "enabled": True,
}
with open(reg, "w") as f:
    json.dump(data, f, indent=2, sort_keys=True)
    f.write("\n")
PY
    log "  .registry ← $id (priority=$prio)"

    # 6. audit log
    echo "$id @ $PRESET_REPO_SHA installed $TS" >> "$AUDIT_LOG"
}

# merge_extensions_fragment <fragment-path>
# yq-free merge using PyYAML; idempotent (re-running won't duplicate hook entries with same `extension` key)
merge_extensions_fragment() {
    local fragment="$1"
    [[ -f "$EXTENSIONS_FILE" ]] || echo "hooks: {}" > "$EXTENSIONS_FILE"
    SPECKIT_TARGET="$EXTENSIONS_FILE" SPECKIT_FRAG="$fragment" python3 <<'PY'
import yaml, os, sys
with open(os.environ["SPECKIT_TARGET"]) as f:
    tgt = yaml.safe_load(f) or {}
with open(os.environ["SPECKIT_FRAG"]) as f:
    frag = yaml.safe_load(f) or {}
tgt.setdefault("hooks", {})
for hook_slot, entries in (frag.get("hooks") or {}).items():
    tgt["hooks"].setdefault(hook_slot, [])
    existing_keys = {e.get("extension") for e in tgt["hooks"][hook_slot] if isinstance(e, dict)}
    for entry in entries:
        if isinstance(entry, dict) and entry.get("extension") in existing_keys:
            continue  # idempotent
        tgt["hooks"][hook_slot].append(entry)
with open(os.environ["SPECKIT_TARGET"], "w") as f:
    yaml.safe_dump(tgt, f, sort_keys=False, allow_unicode=True)
PY
}

if [[ "$UNLOCK" == true ]]; then
    for p in "${PRESETS[@]}"; do install_one "$p"; done
else
    # flock on .registry (linux/mac)
    if command -v flock >/dev/null 2>&1; then
        exec 9>"$REGISTRY_FILE.lock"
        flock 9
        for p in "${PRESETS[@]}"; do install_one "$p"; done
        flock -u 9
    else
        # macOS without GNU flock — fall back; warn user
        echo "⚠️  flock not available; running without lock (set up GNU coreutils or use --unlock)" >&2
        for p in "${PRESETS[@]}"; do install_one "$p"; done
    fi
fi

log "Done. Audit log: $AUDIT_LOG"
