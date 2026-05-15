---
description: Auto-link meta canonical spec.md to sibling impl repos (triggered by after_specify hook)
allowed-tools: Bash
---

You have been triggered by the spec-kit `after_specify` hook in the meta repo.
The hook context provides `FEATURE_DIR` (absolute path to the just-created
feature directory under `specs/<module>/<usecase>/`).

## Steps

1. **Compute relative path** from meta repo root to FEATURE_DIR:

   ```bash
   META_ROOT=$(git rev-parse --show-toplevel)
   REL_PATH=$(realpath --relative-to="$META_ROOT/specs" "$FEATURE_DIR")
   ```

   This yields `<module>/<usecase>` form (e.g. `auth/register-by-phone`).

2. **Run the link script** in `--target both` mode:

   ```bash
   "$META_ROOT/scripts/link-spec.sh" "$REL_PATH" --target both
   ```

3. **Report** the symlink paths created (script's stdout).

## Failure handling

- If `./scripts/link-spec.sh` exits non-zero, surface the stderr and ask the user to fix manually.
- If `FEATURE_DIR` is not under `specs/<module>/<usecase>/` form, abort with explanation (this command only supports the project's 2-level module/usecase layout, not spec-kit default flat `<NNN>-<feature>/`).

## Notes

- Slash command name `/speckit-link-spec` ↔ hook command name `speckit.link-spec`
  (per spec-kit dot → hyphen convention; see speckit-specify SKILL.md "Pre-Execution Checks" section).
- Ships as part of `multi-repo-link` preset from michael-speckit-presets.
- Together with `extensions.yml.fragment` (registering the after_specify hook)
  and the vendored `scripts/link-*.sh` (the actual symlink driver).
