# michael-speckit-presets

Composable presets for [github/spec-kit](https://github.com/github/spec-kit) ≥ 0.8.5, built on its native composition system (`templates` / `commands` / `extensions.yml` hooks) — no SKILL fork.

Focus: **mono-repo spec-kit automated orchestration + execution**. Tracks spec-kit upstream long-term and never forks spec-core.

## Presets

All presets are **mono-repo only** (`applies_to: [mono]`). Earlier `meta` / `server` / `app` repo-type targeting was retired together with the obsolete `multi-repo-link` and `api-types-sync` presets — this repo no longer supports a split meta / server / app workflow.

| Preset | Effect |
|---|---|
| `mono-orchestrator-ready` (0.2.0) | `spec-template` + `plan-template` + `tasks-template` `replace` → upgrade all three to orchestrator-friendly form (YAML frontmatter + JSON fenced blocks + HTML marker JSON). 0.2.0 adds spec frontmatter v2 fields (`web_compat` / `agent_friction_observed` / `agent_friction_notes` / `perf_budgets[]`), `schemas/spec.zod.ts`, `scripts/check-spec-frontmatters.ts`, and a `lefthook.yml.fragment` registering `pre-commit/spec-frontmatter-check`. |
| `adr-governance` | ADR frontmatter governance: `templates/adr-template.md` + `schemas/adr.zod.ts` (4 mandatory fields: `adr_id` / `status` / `applies_to` / `sunset_trigger`) + `scripts/check-adr-frontmatters.ts` (also cross-checks `adr_id` ↔ filename NNNN) + `lefthook.yml.fragment` registering `pre-commit/adr-frontmatter-check`. |
| `task-closure` | `tasks-template` prepend + `after_implement` hook → `tasks.md` `[X]` state stays in sync with implementation commits |
| `user-journey-mermaid` | `spec-template` prepend → adds `## User Journey Diagram` (mermaid sequenceDiagram) placeholder to every new spec |
| `context7-injection` | `plan-template` + `tasks-template` prepend → instructs Claude to call `mcp__context7__query-docs` before drafting third-party library decisions / API usage |

Composition order (priority): `mono-orchestrator-ready` `4` base layer · `context7-injection` `5` · `user-journey-mermaid` `6` · `adr-governance` `7` · `task-closure` `10` (later = higher).

### Schemas + lefthook fragment extension points (0.2.0)

Two new install-side resource types were added so presets can carry runtime
validation logic without forking SKILLs:

- **`<preset>/schemas/*.ts`** — Zod schemas, installed to `<repo>/.specify/schemas/<preset-id>/`. Per-preset namespaced so multiple presets can ship schemas without collision.
- **`<preset>/scripts/*.ts`** — Node scripts (typically tsx-run), installed to `<repo>/scripts/`. Shared flat directory; preset authors should name files distinctively (e.g. `check-spec-frontmatters.ts`, not `check.ts`).
- **`<preset>/lefthook.yml.fragment`** — lefthook hook definitions, installed as a standalone file `<repo>/lefthook.preset-<id>.yml`. `install.sh` ensures the target's `lefthook.yml` `extends:` array references it. This preserves the target repo's hand-curated `lefthook.yml` comments — only the `extends:` key is touched.

Mono target repos must have `zod`, `gray-matter`, and `tsx` installed as root devDeps for the checker scripts to run.

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
- `python3` ≥ 3.9 + `PyYAML` (used by `install.sh` to merge `extensions.yml` and edit `lefthook.yml` `extends:`)
- `lefthook` (target repo, for presets shipping `lefthook.yml.fragment`)
- Node 22+ + `pnpm` + root devDeps `zod ^3` + `gray-matter ^4` + `tsx ^4` (for `mono-orchestrator-ready` 0.2.0 / `adr-governance` checker scripts)
- For `context7-injection`: target repo's Claude Code config registers `context7` MCP server

## Layout

```text
michael-speckit-presets/
├── presets/
│   ├── mono-orchestrator-ready/         # 0.2.0+: templates + schemas + scripts + lefthook fragment
│   │   ├── preset.yml
│   │   ├── templates/                   # spec / plan / tasks (replace)
│   │   ├── schemas/                     # spec.zod.ts
│   │   ├── scripts/                     # check-spec-frontmatters.ts
│   │   └── lefthook.yml.fragment        # pre-commit/spec-frontmatter-check
│   ├── adr-governance/
│   │   ├── preset.yml
│   │   ├── templates/                   # adr-template.md (replace)
│   │   ├── schemas/                     # adr.zod.ts
│   │   ├── scripts/                     # check-adr-frontmatters.ts
│   │   └── lefthook.yml.fragment        # pre-commit/adr-frontmatter-check
│   ├── task-closure/
│   ├── user-journey-mermaid/
│   └── context7-injection/
├── scripts/
│   ├── install.sh                       # install preset(s) into a target repo
│   ├── verify.sh                        # check installed presets are in sync (templates+commands+schemas+scripts+lefthook fragment)
│   └── sync-upstream.sh                 # validate prepend layers vs new spec-kit version
├── .registry-template                   # default priorities for installed presets
└── .github/workflows/
    └── verify-presets.yml               # CI: schema lint + dry-run install
```

## License

[MIT](./LICENSE)
