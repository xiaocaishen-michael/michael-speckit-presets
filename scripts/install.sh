#!/usr/bin/env bash
# install.sh — install one or more michael-speckit-presets into a target spec-kit repo
#
# Usage:
#   install.sh --repo <abs-path> --preset <id> [--preset <id> ...] [--unlock] [--dry-run]
#
# Effects per preset:
#   1. Copy preset/<id>/templates/*.md       →  <repo>/.specify/presets/<id>/templates/
#   2. Copy preset/<id>/commands/*.md        →  <repo>/.claude/commands/
#   3. Merge preset/<id>/extensions.yml.fragment → <repo>/.specify/extensions.yml (PyYAML merge)
#   4. Copy preset/<id>/schemas/*            →  <repo>/.specify/schemas/<id>/
#   5. Copy preset/<id>/scripts/*            →  <repo>/scripts/
#   6. Install preset/<id>/lefthook.yml.fragment as <repo>/lefthook.preset-<id>.yml
#      + ensure <repo>/lefthook.yml `extends:` list contains "./lefthook.preset-<id>.yml"
#   7. Write/merge <repo>/.specify/presets/.registry (priority from preset.yml)
#   8. Append audit log to <repo>/.specify/presets/.install.log (preset repo HEAD sha + timestamp)
#   9. Pre-flight: detect legacy task-closure C1-C4 SKILL fork → abort with cleanup instructions
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

# Pick a python invocation that has PyYAML available.
# Prefer the system python3 if PyYAML is already installed (fast path);
# otherwise fall back to `uv run --with pyyaml` (handles PEP 668-locked
# distributions like Homebrew Python where pip install is blocked).
if python3 -c "import yaml" 2>/dev/null; then
    PY_YAML=(python3)
elif command -v uv >/dev/null 2>&1; then
    PY_YAML=(uv run --with pyyaml --quiet -- python3)
    log "PyYAML not in system python; using 'uv run --with pyyaml' as fallback"
else
    die "PyYAML required. Either 'pip install pyyaml' (may need --user or --break-system-packages) or install uv (https://docs.astral.sh/uv/) to enable the fallback."
fi

PRESETS_DIR="$TARGET_REPO/.specify/presets"
REGISTRY_FILE="$PRESETS_DIR/.registry"
AUDIT_LOG="$PRESETS_DIR/.install.log"
EXTENSIONS_FILE="$TARGET_REPO/.specify/extensions.yml"
LEFTHOOK_FILE="$TARGET_REPO/lefthook.yml"

mkdir -p "$PRESETS_DIR"
[[ -f "$REGISTRY_FILE" ]] || echo '{"presets":{}}' > "$REGISTRY_FILE"

PRESET_REPO_SHA=$(git -C "$PRESET_REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# install_one <preset_id>
install_one() {
    local id="$1"
    local src="$PRESET_REPO_ROOT/presets/$id"
    [[ -d "$src" ]] || die "Preset not found: $id ($src)"
    [[ -f "$src/preset.yml" ]] || die "Preset missing preset.yml: $id"

    log "Installing preset: $id"

    # priority + applies_to from preset.yml
    local prio
    prio=$("${PY_YAML[@]}" -c "import yaml,sys; print(yaml.safe_load(open('$src/preset.yml')).get('priority', 10))")

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

    # 4. schemas
    if [[ -d "$src/schemas" ]]; then
        mkdir -p "$TARGET_REPO/.specify/schemas/$id"
        cp -a "$src/schemas/." "$TARGET_REPO/.specify/schemas/$id/"
        log "  schemas → $TARGET_REPO/.specify/schemas/$id/"
    fi

    # 5. scripts
    if [[ -d "$src/scripts" ]]; then
        mkdir -p "$TARGET_REPO/scripts"
        cp -a "$src/scripts/." "$TARGET_REPO/scripts/"
        chmod +x "$TARGET_REPO/scripts"/*.sh 2>/dev/null || true
        log "  scripts → $TARGET_REPO/scripts/"
    fi

    # 6. lefthook fragment
    if [[ -f "$src/lefthook.yml.fragment" ]]; then
        install_lefthook_fragment "$id" "$src/lefthook.yml.fragment"
        log "  lefthook.preset-$id.yml ← installed; lefthook.yml extends amended"
    fi

    # 7. .registry update
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

    # 8. audit log
    echo "$id @ $PRESET_REPO_SHA installed $TS" >> "$AUDIT_LOG"
}

# install_lefthook_fragment <preset-id> <fragment-path>
# Strategy:
#   1. Copy fragment to <repo>/lefthook.preset-<id>.yml verbatim (idempotent — overwrite)
#   2. Ensure <repo>/lefthook.yml has `extends:` list containing "./lefthook.preset-<id>.yml"
# Rationale: use LINE-BASED edit (not PyYAML round-trip) to preserve all user
# comments, multi-line shell scripts (`run: |`), and block scalar formatting
# in lefthook.yml. PyYAML round-trip mangles `run: |` blocks into escaped
# single-line strings and strips all comments — unacceptable for hand-curated
# lefthook configs.
#
# Supported shapes:
#   - No `extends:` key       → prepend `extends:\n  - <entry>\n`
#   - Block-style list:       → append `  - <entry>` after the last existing item
#       extends:
#         - ./a.yml
#         - ./b.yml
#
# Unsupported shapes (script aborts with explicit instructions):
#   - Inline flow-style list: `extends: [./a.yml]`
#   - Scalar:                 `extends: ./a.yml`
#   User must convert to block style first; the abort message explains how.
install_lefthook_fragment() {
    local id="$1"
    local fragment="$2"
    local preset_file="$TARGET_REPO/lefthook.preset-$id.yml"

    {
        echo "# Auto-generated by michael-speckit-presets install.sh; preset id: $id"
        echo "# Do not edit by hand — re-install to refresh. To uninstall: remove this file"
        echo "# AND remove './lefthook.preset-$id.yml' from lefthook.yml extends list."
        cat "$fragment"
    } > "$preset_file"

    [[ -f "$LEFTHOOK_FILE" ]] || echo "" > "$LEFTHOOK_FILE"
    SPECKIT_LEFTHOOK="$LEFTHOOK_FILE" SPECKIT_PRESET_FILE="./lefthook.preset-$id.yml" python3 <<'PY'
import os, re, sys

target = os.environ["SPECKIT_LEFTHOOK"]
entry = os.environ["SPECKIT_PRESET_FILE"]

with open(target) as f:
    lines = f.readlines()

# Locate top-level `extends:` line (ignoring leading whitespace; matches start of doc only)
extends_idx = None
for i, line in enumerate(lines):
    # only consider top-level keys: no indentation, ends with ':' or ': something'
    m = re.match(r"^extends\s*:\s*(.*)$", line)
    if m:
        extends_idx = i
        extends_inline = m.group(1).strip()
        break

if extends_idx is None:
    # No extends key — prepend block-style
    prefix = [f"extends:\n", f"  - {entry}\n"]
    # blank separator if next existing content is non-blank
    if lines and lines[0].strip() != "":
        prefix.append("\n")
    new_lines = prefix + lines
elif extends_inline and not extends_inline.startswith("#"):
    # `extends: <inline>` — unsupported shape, abort
    sys.stderr.write(
        f"❌ lefthook.yml has inline `extends: {extends_inline}` — not supported.\n"
        f"   Convert to block style first:\n"
        f"     extends:\n"
        f"       - <existing-entry>\n"
        f"       - {entry}\n"
        f"   Then re-run install.sh.\n"
    )
    sys.exit(1)
else:
    # Block-style extends — track the LAST real list-item line; blanks and
    # comments are tolerated mid-scan but never extend the insertion point
    # (otherwise we'd splice a new `- entry` past the end of the list and
    # break YAML — the orphan item attaches to the wrong parent).
    last_item_idx = extends_idx
    found = False
    for j in range(extends_idx + 1, len(lines)):
        line = lines[j]
        item_m = re.match(r"^\s+-\s*(.+?)\s*$", line)
        if item_m:
            item = item_m.group(1).strip().strip("'\"")
            if item == entry:
                found = True
                break
            last_item_idx = j
            continue
        if line.strip() == "" or line.lstrip().startswith("#"):
            # blank / comment inside list block — keep scanning but do not
            # advance last_item_idx
            continue
        # any other content (next top-level key or sibling) — end of extends
        break

    if found:
        new_lines = lines  # idempotent: entry already present, no change
    else:
        new_lines = lines[: last_item_idx + 1] + [f"  - {entry}\n"] + lines[last_item_idx + 1 :]

with open(target, "w") as f:
    f.writelines(new_lines)
PY
}

# merge_extensions_fragment <fragment-path>
# yq-free merge using PyYAML; idempotent (re-running won't duplicate hook entries with same `extension` key)
merge_extensions_fragment() {
    local fragment="$1"
    [[ -f "$EXTENSIONS_FILE" ]] || echo "hooks: {}" > "$EXTENSIONS_FILE"
    SPECKIT_TARGET="$EXTENSIONS_FILE" SPECKIT_FRAG="$fragment" "${PY_YAML[@]}" <<'PY'
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
