#!/usr/bin/env bash
# cleanup-task-closure-legacy.sh — restore vanilla speckit-implement SKILL.md
# Removes the legacy C1-C4 fork artifacts at <repo>/.claude/skills/speckit-implement/
# so the target repo can adopt the task-closure preset (which uses spec-kit native composition).
#
# Usage:
#   cleanup-task-closure-legacy.sh --repo <abs-path> [--spec-kit-version v0.8.7] [--yes]
#
# Effects:
#   1. Fetch vanilla `templates/commands/implement.md` from spec-kit at <version>
#   2. Write it to <repo>/.claude/skills/speckit-implement/SKILL.md
#      (preserving spec-kit's standard frontmatter; removing `localCustomized: true`)
#   3. Delete CUSTOMIZATIONS.md and _upstream-snapshot.md
#   4. Print git diff for user review (caller commits)
set -euo pipefail

TARGET_REPO=""
SPECKIT_VERSION="v0.8.7"
AUTO_YES=false

die() { echo "❌ $*" >&2; exit 1; }
log() { echo "[cleanup-task-closure-legacy.sh] $*"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo) TARGET_REPO="$2"; shift 2 ;;
        --spec-kit-version) SPECKIT_VERSION="$2"; shift 2 ;;
        --yes) AUTO_YES=true; shift ;;
        -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "Unknown flag: $1" ;;
    esac
done

[[ -n "$TARGET_REPO" ]] || die "Missing --repo"
[[ -d "$TARGET_REPO" ]] || die "Target repo not found: $TARGET_REPO"

SKILL_DIR="$TARGET_REPO/.claude/skills/speckit-implement"
[[ -d "$SKILL_DIR" ]] || die "No speckit-implement skill at $SKILL_DIR (nothing to clean)"

SKILL="$SKILL_DIR/SKILL.md"
CUSTOM="$SKILL_DIR/CUSTOMIZATIONS.md"
SNAP="$SKILL_DIR/_upstream-snapshot.md"

if ! grep -q 'localCustomized:[[:space:]]*true' "$SKILL" 2>/dev/null; then
    log "No legacy fork detected (SKILL.md has no localCustomized: true). Nothing to do."
    exit 0
fi

log "Legacy fork detected. Restoring vanilla spec-kit $SPECKIT_VERSION implement SKILL..."

if [[ "$AUTO_YES" != true ]]; then
    read -r -p "Proceed? This rewrites $SKILL and deletes CUSTOMIZATIONS.md + _upstream-snapshot.md. (y/N) " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { log "Aborted by user."; exit 1; }
fi

TMP=$(mktemp)
trap "rm -f $TMP" EXIT

# Fetch upstream vanilla implement.md
UPSTREAM_URL="https://raw.githubusercontent.com/github/spec-kit/$SPECKIT_VERSION/templates/commands/implement.md"
if ! curl -fsSL "$UPSTREAM_URL" -o "$TMP"; then
    die "Failed to fetch upstream implement.md at $SPECKIT_VERSION from $UPSTREAM_URL"
fi

# Compose vanilla SKILL.md = standard frontmatter + upstream body
cat > "$SKILL" <<EOF
---
name: "speckit-implement"
description: "Execute the implementation plan by processing and executing all tasks defined in tasks.md"
argument-hint: "Optional implementation guidance or task filter"
compatibility: "Requires spec-kit project structure with .specify/ directory"
metadata:
  author: "github-spec-kit"
  source: "templates/commands/implement.md"
user-invocable: true
disable-model-invocation: false
---

EOF
cat "$TMP" >> "$SKILL"
log "✅ Restored vanilla SKILL.md at $SKILL"

# Delete fork artifacts
for f in "$CUSTOM" "$SNAP"; do
    if [[ -f "$f" ]]; then
        rm "$f"
        log "✅ Deleted $f"
    fi
done

# Show diff for user review
if git -C "$TARGET_REPO" rev-parse --git-dir >/dev/null 2>&1; then
    log ""
    log "Git diff (please review and commit):"
    log "----------------------------------------"
    git -C "$TARGET_REPO" diff --stat -- ".claude/skills/speckit-implement/" || true
fi

log ""
log "Next: install task-closure preset"
log "  <preset-repo>/scripts/install.sh --repo $TARGET_REPO --preset task-closure"
