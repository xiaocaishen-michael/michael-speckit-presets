#!/usr/bin/env bash
# Usage: link-all-specs.sh
#
# Batch-link all use cases under meta-canonical specs/ to impl repos.
# Use for first-time setup, fresh checkout on a new machine, or recovery.
#
# Ships as part of `multi-repo-link` preset from michael-speckit-presets.
# See link-spec.sh header for the three-repo layout assumption.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
META_ROOT="${META_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

[[ -d "${META_ROOT}/specs" ]] || { echo "❌ ${META_ROOT}/specs not found" >&2; exit 1; }

count=0
for usecase_dir in "${META_ROOT}"/specs/*/*/; do
    [[ -d "$usecase_dir" ]] || continue
    rel="${usecase_dir#"${META_ROOT}/specs/"}"
    rel="${rel%/}"
    if [[ -f "${usecase_dir}/spec.md" ]]; then
        "${SCRIPT_DIR}/link-spec.sh" "$rel" --target both
        ((count++))
    else
        echo "⚠️  skip ${rel}: no spec.md"
    fi
done

echo
echo "✅ linked $count use case(s) to server + app"
