# Preset Mechanism — 修改 Preset 前必读

> 这是 [github/spec-kit](https://github.com/github/spec-kit) preset 系统的权威说明。本仓的 preset 在此机制下运行，理解它是修改任何 preset 内容的前置条件。如果你只想消费 preset（install + 用），看 [README](README.md) 即可。

## 1. Spec-kit 模板四层 resolver

任何 spec-kit slash command（`/speckit-plan` / `/speckit-tasks` 等）需要模板时，调用 `PresetResolver.resolve_template(<name>)`，按下表**从高到低**遍历，**首层命中即返回**：

| Priority | Path | 用途 |
|---|---|---|
| **1** (最高) | `.specify/templates/overrides/` | 项目本地一次性覆盖 |
| **2** | `.specify/presets/<preset-id>/templates/` | **本仓 preset 全部落在这层** |
| **3** | `.specify/extensions/<ext-id>/templates/` | extension 提供的模板 |
| **4** (最低) | `.specify/templates/` | spec-kit 默认 / fallback |

权威源：spec-kit 仓 [`presets/ARCHITECTURE.md`](https://github.com/github/spec-kit/blob/main/presets/ARCHITECTURE.md) + Python 实现 [`src/specify_cli/presets.py`](https://github.com/github/spec-kit/blob/main/src/specify_cli/presets.py) + Bash 对等实现 `scripts/bash/common.sh: resolve_template()` + PowerShell 对等 `scripts/powershell/common.ps1: Resolve-Template`。三处一致。

多 preset 同时声明同一模板时按 `.specify/presets/.registry` 的 `priority` 字段排序，**数字越小优先级越高**（与本仓 README "Composition order" 表对齐）。

## 2. `strategy:` 字段的真正语义

`preset.yml` 里每个 template / command / script 条目可以声明 `strategy:`，控制**当前层与更低层如何组合**：

| Strategy | 行为 |
|---|---|
| `replace` (default) | resolver 命中此层后**直接返回**，不下穿到 Priority 4。不是"物理覆盖文件" |
| `prepend` | 用本层内容 + 空行 + 低层内容 |
| `append` | 用低层内容 + 空行 + 本层内容 |
| `wrap` | 本层内容含 `{CORE_TEMPLATE}` 占位符（templates/commands）或 `$CORE_SCRIPT`（scripts），resolver 把低层内容填进去 |

权威源：spec-kit `presets/ARCHITECTURE.md` § Composition Strategies + `PresetResolver.resolve_content()` 递归 bottom-up 实现。

**常见误解纠正**：「`strategy: replace` 会用 preset 模板**物理替换** `.specify/templates/` 下的默认模板」——**错**。`replace` 是 resolver 优先级语义，**不动文件**。Priority 4 的 `.specify/templates/*.md` 在 install 后**仍是 spec-kit 默认裸模板**，因为 resolver 在 Priority 2 命中就停了，永远走不到 Priority 4。这是设计如此，不是 bug。

## 3. `install.sh` vs Resolver 的分工

| 阶段 | 谁负责 | 干什么 |
|---|---|---|
| 安装期 | `scripts/install.sh`（本仓） | 把 `presets/<id>/templates/*` 复制到目标仓 `.specify/presets/<id>/templates/`；把 `schemas/*` 复制到 `.specify/schemas/<id>/`；写 `.registry` + `.install.log` |
| 运行期 | spec-kit `PresetResolver` | slash command 触发时按四层优先级 resolve，命中即返回 |

`install.sh` **不**触碰 Priority 4 的 `.specify/templates/*`，**不**做物理替换。运行期由 resolver 选层。

## 3.5 命令接 resolver 不对称：`specify` 是例外（重要）

§1 的 resolver 只有命令**真去调它**才生效。spec-kit 各 slash command 接 resolver 的方式**不一致**：

| 命令 | 取模板路径 | 命中层 |
|---|---|---|
| `/speckit-plan` | 命令 frontmatter `scripts:` → `setup-plan.sh` → `resolve_template` | 经 resolver（命中 P1-P4 最高层）|
| `/speckit-tasks` | 命令 frontmatter `scripts:` → `setup-tasks.sh` → `resolve_template` | 经 resolver |
| `/speckit-specify` | 命令 body **硬编码 `cp .specify/templates/spec-template.md`**，无 `scripts:` 键、不调 `create-new-feature.sh` | **永远 Priority 4 core / vanilla**，不经 resolver |

即 `/speckit-specify` 的 spec 创建**绕过整个 resolver 栈** —— 任何 P1-P3 的 preset/extension `spec-template` 覆盖**对它静默无效**（但 `/speckit-plan`·`/speckit-tasks` 会照单全收）。

**这是上游 spec-kit v0.8+ 的故意设计**：core `specify` 被做成 script-free（默认不自动建 git branch）。resolver-aware 的 spec 创建挪到了 opt-in 的 `scaffold` preset / `git` extension —— 它们提供一份带 `scripts: create-new-feature.sh` 的 **specify 命令覆盖**（`create-new-feature.sh` 本身 resolver-aware，会 `resolve_template "spec-template"`）。

**推论**：想让 `/speckit-specify` 产出 preset 的 orchestrator-friendly spec（frontmatter + 机读 marker），**只改 preset 的 `spec-template` 没用** —— 必须**覆盖 specify 命令本身**（装 `scaffold` preset / `git` extension，或自建 command 覆盖）。否则它永远产 vanilla spec。

> 实证：`no-vain-years-mono` 2026-05-26 —— 实跑 `resolve_template` 三模板全命中 P2、`create-new-feature.sh` 的 resolve+cp 产出带 frontmatter+us-meta，而 `cp .specify/templates/spec-template.md`（specify SKILL 字面）产出 vanilla 零 metadata；交叉核对 github/spec-kit `main` 的 `templates/commands/{specify,plan,tasks}.md` + `scripts/bash/{common,create-new-feature,setup-*}.sh`。

## 4. 修改 preset 内容的正确流程

`mono-orchestrator-ready` 等 preset 一旦 install 进了下游仓（如 `no-vain-years-mono`），下游会有 `.specify/presets/<id>/` 下的 vendored 副本。**禁止直接改下游的 vendored 副本**——下次 install 会按本仓 main 内容静默覆盖，把直接改的内容擦掉。

正确流程：

1. 在本仓 (`michael-speckit-presets`) 的 `presets/<id>/` 下改文件
2. 在 `preset.yml` 顶部 `version:` 字段 bump（patch / minor / major 看 backward-compat）
3. 在 `preset.yml` `description:` 末尾追加该版本的"增量"段，chronological 记录变化
4. 开 PR + merge
5. 在下游仓跑 `scripts/install.sh --repo <target> --preset <id>` re-install，让下游 vendored 同步到 main

下游仓那边对应的 commit 应是"install `<id>` X.Y.Z 同步"性质的，**不**包含 ad-hoc 编辑。

## 5. 反例：2026-05-22 实证 drift

下游仓 `no-vain-years-mono` 在 PR #80 / #82 / #84 三次直接改了 `.specify/presets/mono-orchestrator-ready/templates/*`，没回流到本仓。结果本仓 main 停在 0.2.1，下游 vendored 飞到 0.3.1。修复要回流 5 个文件 +109/-5 行（本仓 PR #14）。下游 `.claude/rules/preset-modification.md` 加 path-triggered rule 阻止未来重犯。

## 6. 进一步阅读

- spec-kit 仓 `presets/ARCHITECTURE.md` —— 上游权威说明（template resolution / command registration / catalog system / extension safety）
- 本仓 [README](README.md) —— preset 用法
- 本仓 [scripts/install.sh](scripts/install.sh) —— 安装期实际复制逻辑
- 本仓 [presets/*/preset.yml](presets/) —— 每个 preset 的 strategy 声明
