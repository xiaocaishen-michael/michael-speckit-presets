# michael-speckit-presets

Composable presets for [github/spec-kit](https://github.com/github/spec-kit) ≥ 0.8.5, built on its native composition system (`templates` / `commands` / `extensions.yml` hooks) — no SKILL fork.

## Presets

| Preset | Effect | Applies to |
|---|---|---|
| `task-closure` | `tasks-template` prepend + `after_implement` hook → `tasks.md` `[X]` state stays in sync with implementation commits | impl repos (back-end / front-end) |
| `user-journey-mermaid` | `spec-template` prepend → adds `## User Journey Diagram` (mermaid sequenceDiagram) placeholder to every new spec | spec canonical / meta repos |
| `context7-injection` | `plan-template` + `tasks-template` prepend → instructs Claude to call `mcp__context7__query-docs` before drafting third-party library decisions / API usage | impl repos |
| `multi-repo-link` | `after_specify` hook + `link-spec.sh` → auto-symlinks meta-canonical `spec.md` into sibling impl repos | meta repos (driver) |
| `api-types-sync` | `after_implement` hook → if HTTP-layer task (`[Web]` / `[Contract]`) just completed, cross-cwd run sibling app `pnpm api:gen:dev` + typecheck (no auto-commit) | server back-end repo |

Designed for a three-repo layout (`meta` driver + `server` back-end + `app` front-end) or a single mono-repo (`mono`) where spec canonical and impl live in the same tree. Each preset declares `applies_to: [meta]` / `[server, app]` / `[meta, mono]` / etc. — concrete repo-type names only, no abstract `impl` alias.

## Quick start

```bash
# 1. Clone this repo somewhere stable (independent of target project layout)
git clone https://github.com/xiaocaishen-michael/michael-speckit-presets.git ~/Documents/projects/michael-speckit-presets

# 2. Install a preset into a spec-kit-initialised target repo
~/Documents/projects/michael-speckit-presets/scripts/install.sh \
    --repo /path/to/target-repo \
    --preset task-closure
```

`install.sh --preset <id>` can be repeated to install multiple presets in one invocation.

## Requirements

- Target repo has `.specify/` initialised (`uvx --from git+https://github.com/github/spec-kit.git@v0.8.7 specify init . --ai claude --ai-skills --here`)
- `python3` ≥ 3.9 + `PyYAML` (used by `install.sh` to merge `extensions.yml`)
- `yq` v4 (used by `verify.sh`)
- For `context7-injection`: target repo's Claude Code config registers `context7` MCP server

## Layout

```text
michael-speckit-presets/
├── presets/
│   ├── task-closure/
│   ├── user-journey-mermaid/
│   ├── context7-injection/
│   ├── multi-repo-link/
│   └── api-types-sync/
├── scripts/
│   ├── install.sh                       # install preset(s) into a target repo
│   ├── verify.sh                        # check installed presets are in sync
│   ├── sync-upstream.sh                 # validate prepend layers vs new spec-kit version
│   └── cleanup-task-closure-legacy.sh   # restore vanilla SKILL.md for repos with legacy C1-C4 fork
├── .registry-template                   # default priorities for installed presets
└── .github/workflows/
    └── verify-presets.yml               # CI: schema lint + dry-run install
```

## License

[MIT](./LICENSE)
