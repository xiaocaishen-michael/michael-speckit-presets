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
