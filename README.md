# michael-speckit-presets

Composable presets for [github/spec-kit](https://github.com/github/spec-kit) ≥ 0.8.5, built on its native composition system (`templates` / `commands` / `extensions.yml` hooks) — no SKILL fork.

Focus: **mono-repo spec-kit automated orchestration + execution**. Tracks spec-kit upstream long-term and never forks spec-core.

## Presets

All presets are **mono-repo only** (`applies_to: [mono]`). Earlier `meta` / `server` / `app` repo-type targeting was retired together with the obsolete `multi-repo-link` and `api-types-sync` presets — this repo no longer supports a split meta / server / app workflow.

| Preset | Effect |
|---|---|
| `mono-orchestrator-ready` | `spec-template` + `plan-template` + `tasks-template` `replace` → upgrade all three to orchestrator-friendly form (YAML frontmatter + JSON fenced blocks + HTML marker JSON, validated by Zod schemas in `scripts/orchestrator/`) |
| `task-closure` | `tasks-template` prepend + `after_implement` hook → `tasks.md` `[X]` state stays in sync with implementation commits |
| `user-journey-mermaid` | `spec-template` prepend → adds `## User Journey Diagram` (mermaid sequenceDiagram) placeholder to every new spec |
| `context7-injection` | `plan-template` + `tasks-template` prepend → instructs Claude to call `mcp__context7__query-docs` before drafting third-party library decisions / API usage |

Composition order: `mono-orchestrator-ready` (priority `4`) forms the base layer; the `prepend`-strategy presets (`context7-injection` `5`, `user-journey-mermaid` `6`, `task-closure` `10`) compose on top.

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
│   ├── mono-orchestrator-ready/
│   ├── task-closure/
│   ├── user-journey-mermaid/
│   └── context7-injection/
├── scripts/
│   ├── install.sh                       # install preset(s) into a target repo
│   ├── verify.sh                        # check installed presets are in sync
│   └── sync-upstream.sh                 # validate prepend layers vs new spec-kit version
├── .registry-template                   # default priorities for installed presets
└── .github/workflows/
    └── verify-presets.yml               # CI: schema lint + dry-run install
```

## License

[MIT](./LICENSE)
