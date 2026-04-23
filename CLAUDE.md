# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

这是一个 Claude Code 插件工具集（DevFlow），包含多个开发流程插件。通过 marketplace.json 统一管理。

## 架构

工具集采用多插件结构，每个插件独立在 `plugins/` 子目录下：

```
.claude-plugin/marketplace.json     # 工具集清单，注册所有插件
plugins/
├── req/                            # 需求管理插件
│   ├── .claude-plugin/plugin.json  # 插件清单
│   ├── commands/                   # 命令定义（Markdown 文件）
│   ├── skills/                     # 自动触发的 AI 技能（SKILL.md 文件）
│   ├── hooks/hooks.json            # 工具拦截的事件钩子
│   ├── scripts/                    # 验证和工具脚本
│   └── templates/                  # 需求文档模板
├── api/                            # API 对接插件
│   ├── .claude-plugin/plugin.json  # 插件清单
│   ├── commands/                   # 命令定义
│   ├── skills/                     # 自动触发技能
│   └── scripts/                    # Python 解析脚本
├── pm/                             # 项目管理助手插件
│   ├── .claude-plugin/plugin.json  # 插件清单
│   ├── commands/                   # 命令定义（汇报/统计/方案等）
│   ├── skills/                     # 自动触发技能
│   └── scripts/                    # Git 统计采集脚本
└── diag/                           # 生产诊断插件
    ├── .claude-plugin/plugin.json  # 插件清单
    ├── commands/                   # 命令定义（init/diagnose/audit）
    ├── hooks/hooks.json            # 5 类风控 Hook 注册
    ├── scripts/                    # SSH 解析 + 配置校验 + 命令白名单
    ├── skills/                     # stack-analyzer 堆栈识别
    └── templates/                  # services.yaml 配置模板
```

### 存储架构（本地优先 + 缓存同步）

需求采用**双存储**架构，本地为主、缓存为辅：

**1. 项目本地存储（主存储）**
- 存储目录：`docs/requirements/`
- 模块文档：`docs/requirements/modules/`
- 规范文档：`docs/requirements/specs/`（数据类型、接口契约等，跨仓库共享）
- 进行中的需求：`docs/requirements/active/`
- 已完成的需求：`docs/requirements/completed/`
- 需求索引：`docs/requirements/INDEX.md`（自动生成）
- 模板目录：`docs/requirements/templates/`
- 优势：纳入 git 版本控制，团队可审查

**2. 全局缓存（同步副本）**
- 缓存目录：`~/.claude-requirements/`
- 项目缓存路径：`~/.claude-requirements/projects/<project-name>/`
- 仓库绑定配置：`.claude/settings.local.json` 中的 `requirementProject` 和 `requirementRole`
- 优势：支持跨仓库共享同一套需求

**仓库角色**（`requirementRole` 字段）：
- `primary`：主仓库，拥有本地 `docs/requirements/`，可读写，修改后自动同步到缓存
- `readonly`：只读仓库，无本地存储，仅从缓存读取需求，不可创建/编辑/变更状态

**更新策略（强制自动同步）：**
1. 创建/修改需求 → 先写入本地 `docs/requirements/`（仅 `primary` 角色）
2. 本地写入成功 → **强制自动同步**到全局缓存（通过 PostToolUse Hook，无需用户确认）
3. 读取需求 → `primary` 优先读本地，`readonly` 直接读缓存
4. **只读仓库禁止写操作**：`readonly` 仓库不执行创建、编辑、状态更新、缓存同步
5. **以本地为准**：同步时直接用本地版本覆盖缓存，不进行冲突检测
6. **触发工具**：Write 和 Edit 工具都会触发缓存同步（包括 active/ 和 completed/ 目录，仅 `primary`）

### 命令结构

每个命令文件（`commands/*.md`）通过 YAML frontmatter 声明元信息：

```yaml
---
description: 命令简介
argument-hint: "[参数] [--选项=值]"   # 斜杠菜单中显示的用法提示
allowed-tools: Read, Glob, Grep       # 命令可用的工具白名单
model: claude-sonnet-4-6              # 命令使用的模型
---
```

**模型分级策略**：按命令实际工作复杂度显式降级。Haiku 用于纯展示和规则驱动的机械操作，复杂推理/内容生成类保持默认（跟随用户会话模型）。

| 策略 | 适用场景 | 做法 |
|------|---------|------|
| **显式 haiku** | 纯读取、列表展示、机械操作、规则明确的文档编辑/Git/状态流转 | `model: claude-haiku-4-5-20251001` |
| **不指定**（继承默认） | 深度代码理解、架构设计、需求从零生成、内容创作、启发式分析 | 省略 `model` 字段 |

**为什么避免显式 sonnet**：
- Sonnet 有 1M context 变体，在启用 1M 的会话中会触发 extra-usage 付费墙（未订阅用户直接报错）
- Haiku 全系仅 200K，不会触发 1M 付费墙，对机械类命令足够
- 复杂命令留空 model 字段跟随用户会话模型，由用户自行决定档位，不被命令强行拉高或锁死

**显式 haiku 的命令清单**：
- 查看类：`/req`、`/req:status`、`/req:show`、`/req:prd`、`/req:projects`、`/req:cache`、`/req:use`
- 归档/同步：`/req:done`、`/req:update-template`
- 生成类（规则明确）：`/req:changelog`
- 帮助：`/req:help`、`/api:help`、`/pm:help`
- 展示入口：`/pm:pm`、`/pm:standup`、`/pm:export`
- 检索：`/api:api`、`/api:search`
- Git/状态流转：`/req:commit`、`/req:review`、`/req:upgrade`、`/req:branch`
- 文档/项目 CRUD：`/req:modules`、`/req:specs`、`/req:init`、`/req:migrate`
- 测试编排：`/req:test_regression`

**保持默认的命令**：`/req:new`、`/req:do`、`/req:fix`、`/req:dev`、`/req:test`、`/req:test_new`、`/req:review-pr`、`/req:prd-edit`、`/req:release`、`/req:edit`、`/req:new-quick`、`/req:pr`、`/req:issue`、`/req:split`。

**allowed-tools 约束**：每个命令仅允许其必需的工具集，只读命令不能触发 Write/Edit/Bash，防止误操作。

**Token 节约**：新增/修改命令前，参考 [`docs/design/token-optimization.md`](./docs/design/token-optimization.md)。重点规则：单命令文件 < 30 KB；> 50 KB 必须拆主+rationale（参考 `release.md` / `release-rationale.md`）；引用共享 `_*.md` 时尽量指向具体章节而非整个 `_common.md`。

命令通过 `/req` 子命令模式调用：

**需求管理命令（编号可选，自动识别当前需求）：**
- `/req` - 列出所有需求
- `/req:new [标题] [--type=后端|前端|全栈] [--from-issue=#N]` - 创建新需求，支持从 GitHub/Gitea issue 导入
- `/req:new-quick [标题] [--from-issue=#N]` - 创建快速修复（小bug/小功能，有文档记录）
- `/req:fix <问题描述> [--from-issue=#N] [--auto]` - 轻量修复（无文档，AI 辅助定位 bug，创建修复分支，支持从 GitHub/Gitea issue 导入；`--auto` 跳过方案确认并自动串联 commit + PR）
- `/req:do <描述> [--from-issue=#N]` - 智能开发（无文档，AI 分析意图，自动选择流程和分支前缀）
- `/req:split [需求描述]` - 需求拆分分析（只读，给出粒度和拆分建议）
- `/req:upgrade <QUICK-XXX>` - 将快速修复升级为正式需求
- `/req:edit` - 编辑需求
- `/req:review [pass|reject]` - 提交/通过评审
- `/req:dev` - 启动开发
- `/req:test` - 综合测试（回归 + 新测试）
- `/req:test_regression` - 运行已有自动化测试用例
- `/req:test_new` - 为新功能创建测试用例（UT/API/E2E）
- `/req:done` - 完成需求
- `/req:status` - 查看需求状态
- `/req:show` - 查看需求详情（完整业务内容，纯只读）
- `/req --type=后端` - 按类型筛选需求列表

**模块管理命令：**
- `/req:modules` - 列出所有模块及其需求概览
- `/req:modules new <模块名>` - 创建新模块文档
- `/req:modules show <模块名>` - 查看模块详情
- `/req --module=<模块名>` - 按模块筛选需求列表

**规范文档命令（跨仓库共享）：**
- `/req:specs` - 列出所有规范文档
- `/req:specs new <名称>` - 创建规范文档（仅 primary）
- `/req:specs show <名称>` - 查看规范文档详情
- `/req:specs edit <名称>` - 编辑规范文档（仅 primary）

**PRD 管理命令：**
- `/req:prd [--section=章节名]` - 查看 PRD 状态概览和章节填充分析
- `/req:prd-edit [章节名或编号]` - 编辑/完善 PRD 文档（支持 AI 智能补充）

**分支管理命令：**
- `/req:branch` - 查看当前分支策略和状态（等同于 `status`）
- `/req:branch init` - 交互式配置分支策略（GitHub Flow / Git Flow / Trunk-Based）+ 仓库类型
- `/req:branch status` - 查看策略配置和各需求分支状态
- `/req:branch hotfix [描述]` - 从主分支创建紧急修复分支
- `/req:pr [REQ-XXX]` - 创建 PR，根据仓库类型自动调用 Gitea API / gh CLI（readonly 可用）
- `/req:review-pr` - 查看 PR 状态
- `/req:review-pr review` - AI 代码审查，提交评论到 Gitea/GitHub
- `/req:review-pr fetch-comments` - 拉取 PR 评论，AI 生成修改清单并应用到代码
- `/req:review-pr merge` - 合并 PR，自动清理分支

**Issue 命令（readonly 可用，不触发缓存同步）：**
- `/req:issue new <标题> [--body] [--labels=a,b] [--assignees=u1] [--req=REQ-XXX]` - 创建 issue，fuzzy match 仓库真实标签，自动附关联需求上下文
- `/req:issue edit #N [--title] [--body] [--add-labels] [--remove-labels] [--assignees]` - 修改 issue 字段（Gitea 标签走独立端点）
- `/req:issue close #N [--comment=] [--reason=]` - 关闭 issue，可附告别留言；`--reason` 仅 GitHub 支持
- `/req:issue reopen #N` - 重开 issue
- `/req:issue list [--state=] [--labels=] [--assignee=@me|user] [--limit=20] [--page=1]` - 列出 issue（自动过滤 PR）
- `/req:issue show #N` - 查看 issue 详情和所有评论
- `/req:issue comment #N <文本>` / `--list` - 添加评论或列出评论

**版本管理命令：**
- `/req:commit [消息]` - 规范提交，自动关联需求编号，检查分支合规性（readonly 可用）
- `/req:changelog <version> [--from=<tag|commit>] [--to=<tag|commit>]` - 生成版本升级说明（readonly 可用）
- `/req:release <version> [--from=<tag>] [--to=<ref>]` - 颁布版本：合并 SQL、生成回滚、调用 changelog、打 tag、创建 Gitea/GitHub Release（readonly 可用）

**Migration SQL 约定**：
- 开发过程中产生的 migration SQL 统一放在 `docs/migrations/` 目录下，文件名包含对应需求编号（如 `feat-REQ-001-add-points.sql`）
- `/req:dev` 在生成数据库变更时应将 SQL 文件写入此目录
- `/req:release` 会按文件名中的 `REQ-XXX` / `QUICK-XXX` 自动关联需求并合并到 `docs/migrations/released/<version>.sql`
- `docs/migrations/released/` 为已发布版本归档目录，不会被再次扫描

**项目管理命令（全局缓存模式）：**
- `/req:init <project-name>` - 初始化项目，创建全局缓存
- `/req:use <project-name>` - 切换当前仓库绑定的项目
- `/req:projects` - 列出所有项目
- `/req:migrate <project-name>` - 将本地需求迁移到全局缓存
- `/req:cache <action>` - 缓存管理（info/clear/clear-all/rebuild/export）
- `/req:update-template [模板名] [--force]` - 将插件最新模板同步到项目本地

### 技能（自动触发）

- `requirement-analyzer` - 创建/编辑需求时触发，帮助完善文档各章节
- `dev-guide` - 执行 `/req:dev` 时触发，按分层架构引导代码实现
- `prd-analyzer` - 执行 `/req:prd-edit` 时触发，辅助完善 PRD 文档各章节
- `code-impact-analyzer` - 需求变更时触发，分析受影响的代码
- `test-guide` - 执行测试命令时触发，支持两种模式：
  - `/req:test_regression` - 运行已有自动化测试，生成回归报告
  - `/req:test_new` - 创建新测试用例（UT/API/E2E）
- `changelog-generator` - 执行 `/req:changelog` 时触发，根据 Git 记录生成版本说明
- `natural-language-dispatcher` - 用户用自然语言描述操作时触发，映射到对应 `/req:*` 命令（需求新增/修改、修 bug、优化/重构、状态流转、PR 操作等），并识别 issue/PR URL（如 `owner/repo/issues/169`）

### 钩子

在 `plugins/req/hooks/hooks.json` 中配置的事件钩子：

- **SessionStart（会话启动时）**：
  - `session-context.sh` - 自动注入当前需求上下文（项目绑定、分支对应的 REQ/QUICK 编号、需求状态、进行中需求总数），省去每次开场手动查询
    - **未初始化仓库**：输出欢迎引导，提示新用户两步启动（`/req:init` + `/req:branch init`）
    - **已绑定但未配置分支策略**：在上下文末尾追加 ⚠️ 提示，引导执行 `/req:branch init`

- **PreToolUse（工具调用前）**：
  - `confirm-before-commit.sh` - 默认**直通不弹确认**；仅当项目内存在 `.claude/.req-confirm-commit` marker 文件时，才拦截 git commit / mv / rm 需求文件（timeout: 120s）。marker 由 Claude 按用户自然语言意图维护，同时在 memory 中落 feedback，无需手动编辑配置文件
  - 文档写入（Write/Edit）始终不走 Hook 拦截，由命令自身的讨论与参数流程保证意图确认

- **PostToolUse（Write/Edit 后）**：
  - `validate-requirement.sh` - 验证需求文档格式（timeout: 5s）
  - `sync-cache.sh` - **强制自动同步**到全局缓存（timeout: 5s，无需用户确认，以本地为准）

**超时策略**：交互型 hook（需等待用户确认）设 120s，非交互型 hook（自动执行）保持 5s。

**auto 模式放行**：当 `.claude/.req-confirm-commit` marker 存在、Hook 进入拦截分支时，`confirm-before-commit.sh` 会进一步检测 `.claude/.req-auto` 标记文件，若存在且 mtime 在 10 分钟内，直接 `exit 0` 放行。由 `/req:fix --auto` 等命令在流程开始时创建、结束时清理，10 分钟 TTL 防止异常退出残留标记长期生效。`.claude/.req-auto` 与 `.claude/.req-confirm-commit` 都已加入 `.gitignore`。默认（无 commit marker）下脚本本身就直通，auto 标记不影响行为。

**缓存同步触发规则**：

仅当命令涉及需求文档修改时触发缓存同步：

| 触发同步的命令 | 操作说明 |
|--------------|---------|
| `/req:new` | 创建需求文档 |
| `/req:new-quick` | 创建快速修复文档 |
| `/req:edit` | 编辑需求文档 |
| `/req:review` | 更新评审状态 |
| `/req:dev` | 更新开发状态和进度 |
| `/req:test` | 更新测试状态和结果 |
| `/req:done` | 完成归档（移动到 completed/） |
| `/req:upgrade` | 升级 QUICK 为 REQ |
| `/req:modules new` | 创建模块文档 |
| `/req:prd-edit` | 编辑 PRD 文档 |
| `/req:specs new` | 创建规范文档 |
| `/req:specs edit` | 编辑规范文档 |

不触发同步的命令（只读操作）：`/req`、`/req:status`、`/req:show`、`/req:specs`（列表/show）、`/req:projects`、`/req:cache`、`/req:use`、`/req:init`、`/req:migrate`、`/req:test_regression`、`/req:test_new`、`/req:update-template`、`/req:prd`、`/req:changelog`、`/req:release`、`/req:commit`、`/req:branch`、`/req:pr`、`/req:fix`、`/req:do`、`/req:review-pr`

**同步范围**：`docs/requirements/` 目录下的 REQ-XXX、QUICK-XXX 需求文档、模块文档（modules/）、规范文档（specs/）及 PRD.md，其他文件（INDEX.md、template.md）不同步。

### Git 分支管理

通过 `/req:branch init` 配置分支策略，支持三种模式：

**策略模式**：
| 模式 | 说明 | 适用场景 |
|------|------|---------|
| `github-flow` | 所有分支从 main 拉，合回 main | Web 应用、持续部署、中小团队 |
| `git-flow` | 功能分支从 develop 拉，合回 develop | 版本发布制、APP、大型项目 |
| `trunk-based` | 短期分支，主干开发 | 成熟团队、高频发布 |

**分支命名规则**（可通过策略配置自定义前缀）：
- REQ-XXX → `<featurePrefix>REQ-XXX-<slug>[-iN]`（默认 `feat/`）
- QUICK-XXX → `<fixPrefix>QUICK-XXX-<slug>[-iN]`（默认 `fix/`）
- `/req:do --from-issue` → `<prefix><slug>-iN`（前缀由 AI 分析意图决定）
- 紧急修复 → `<hotfixPrefix><slug>`（默认 `hotfix/`）
- slug：需求标题的英文翻译，lowercase kebab-case，最多 5 词
- `-iN`：可选的 issue 后缀（如 `-i12`），关联了 Git 平台 issue 时追加

**策略配置**：存储在 `.claude/settings.local.json` 的 `branchStrategy` 字段，包含 `model`、`repoType`、`mainBranch`、`developBranch`、`branchFrom`、`mergeTarget` 等。

**仓库托管类型**（`repoType` 字段）：
| 类型 | 说明 | PR 集成 |
|------|------|--------|
| `github` | GitHub 托管 | 提示 `gh pr create` |
| `gitea` | Gitea 自托管 | 自动调用 Gitea API 创建 PR |
| `other` | 其他平台 | 仅展示合并命令 |

Gitea 集成需要：`giteaUrl`（实例地址）+ `giteaToken`（API Token，直接在配置中填写）。

**分支字段**：需求文档元信息中的 `branch` 字段记录分支名，确保跨会话确定性。

**与命令的联动**：
- `/req:dev`：根据 `branchFrom` 创建分支，使用配置的前缀
- `/req:commit`：检查当前分支合规性，在主分支上提交时警告
- `/req:done`：根据 `repoType` 自动创建 PR（Gitea）或提示合并命令
- `/req:branch hotfix`：始终从主分支创建紧急修复分支
- 仅 `primary` 仓库执行分支操作，`readonly` 跳过
- 工作区有未提交改动时拒绝操作
- **未配置策略时**：所有命令保持原有默认行为，不报错

## 需求生命周期状态

```
📝 草稿 → 👀 待评审 → ✅ 评审通过 → 🔨 开发中 → 🧪 测试中 → 🎉 已完成
```

### 状态更新确认机制

不同命令对状态更新有不同的确认要求：

| 命令 | 状态变更 | 确认机制 | 说明 |
|-----|---------|---------|------|
| `/req:review pass/reject` | 待评审 → 评审通过/驳回 | 显式参数即为确认 | 必须带参数执行 |
| `/req:dev` | 评审通过 → 开发中 | 首次进入时自动更新 | REQ 必须先通过评审，QUICK 跳过 |
| `/req:test` | 开发中 → 测试中 | 执行命令即为确认 | 自动更新状态 |
| `/req:done` | 测试中 → 已完成 | **必须明确确认（y/n）** | 最终状态，必须用户确认 |

**重要规则**：
1. 所有状态更新操作都遵循"本地优先"原则，若本地不存在需求文档则跳过更新
2. **开发前检查**：
   - 正式需求 (REQ-XXX)：必须先通过评审，草稿或待评审状态会被拒绝
   - 快速修复 (QUICK-XXX)：跳过评审，方案确认后可直接开发

### 确认操作规范

默认**不走任何原生确认对话框**，所有 Write/Edit/Bash 直通。用户按需通过自然语言开启 Bash 侧拦截（**不用编辑配置文件**）：

**开关方式**（记忆 + marker 文件）：
- 默认 — 项目内无 `.claude/.req-confirm-commit`，Hook 全放行
- 开启 — 用户说"开启提交确认" / "commit 前帮我确认" → Claude `touch .claude/.req-confirm-commit` + 保存 feedback memory
- 关闭 — 用户说"不用确认了" / "关闭提交确认" → Claude `rm .claude/.req-confirm-commit` + 更新 memory

Hook 拦截范围（仅在 marker 存在时）：git commit / 移动 / 删除需求文件。

其余规则：
- 文档写入（Write/Edit）任何情况下都不拦截：命令已通过多轮讨论、显式参数或 y/n 确认完成意图校验，结果不符再次调用命令修改即可
- 命令中的预览/摘要仅作为信息展示，AI 展示后直接执行操作
- 需要用户主动输入的场景（选择章节、选择需求、描述意图）仍需等待用户回复

## 跨仓库共享需求

支持前后端等多个仓库共享同一套需求：

```
~/backend/                         # 后端仓库（主仓库）
├── docs/requirements/             # 本地存储（主存储，纳入 git）
│   ├── templates/                 # 模板文件
│   │   ├── requirement-template.md
│   │   ├── quick-template.md
│   │   └── prd-template.md
│   ├── modules/                   # 模块文档
│   │   ├── user.md
│   │   └── order.md
│   ├── specs/                     # 规范文档（跨仓库共享）
│   │   ├── order-types.md         # 数据类型定义
│   │   └── error-codes.md         # 错误码规范
│   ├── active/
│   │   └── REQ-001-用户积分.md
│   ├── completed/
│   ├── PRD.md                     # 产品需求文档
│   └── INDEX.md                   # 需求索引
└── .claude/settings.local.json    # { "requirementProject": "my-saas-product", "requirementRole": "primary" }

~/frontend/                        # 前端仓库（关联仓库）
└── .claude/settings.local.json    # { "requirementProject": "my-saas-product", "requirementRole": "readonly" }
  # 前端可执行 /req:specs show order-types 查看后端定义的数据类型

~/.claude-requirements/            # 全局缓存（同步副本）
└── projects/
    └── my-saas-product/
        ├── modules/               # 模块文档同步
        ├── specs/                 # 规范文档同步
        │   ├── order-types.md
        │   └── error-codes.md
        ├── active/
        │   └── REQ-001-用户积分.md
        ├── completed/
        └── INDEX.md
```

**使用流程：**
1. 在主仓库执行 `/req:init my-saas-product` 初始化项目
2. 创建需求时：先写入 `docs/requirements/` → 同步到全局缓存
3. 在其他仓库执行 `/req:use my-saas-product` 绑定同一项目
4. 关联仓库读取需求时从全局缓存获取

## 模块与需求关系

**模块（Module）**：按技术架构划分的功能域，相对稳定
- 描述模块职责、业务规则、核心功能
- 记录关键文件路径和 API 概览
- 作为 AI 理解业务上下文的入口

**需求（Requirement）**：按业务目标划分的可交付单元，不断新增
- 可能涉及一个或多个模块
- 有明确的完成态和生命周期
- 每个需求在元信息中标记所属模块
- **粒度规则**：一个 REQ 对应一个可独立交付的业务功能，不按技术层或开发步骤拆分（详见 `_common.md` 需求粒度规则）

**AI 使用场景：**
1. 开发新功能时，先读取模块文档了解业务上下文
2. 通过索引快速定位相关需求
3. 按模块筛选需求，聚焦特定领域

## PRD 与 REQ 的关系

**PRD**（产品需求文档）是项目级的，一个项目一份，描述产品愿景、功能规划、技术选型。
**REQ** 是功能级的，从 PRD 派生，每个可独立交付的业务功能一个 REQ。

```
PRD.md（产品规划）
├── 9. 需求追踪              ← 自动维护的索引
│   ├── REQ-001 用户积分规则管理-后端   草稿
│   ├── REQ-002 用户积分规则管理-前端   开发中
│   └── REQ-003 积分兑换-后端          已完成
```

**自动维护**：
- `/req:new` 创建需求时 → 在 PRD.md「需求追踪」章节追加记录
- `/req:done` 完成需求时 → 更新对应记录的状态和完成日期

**主动维护**：
- `/req:prd` → 查看 PRD 状态概览，分析各章节填充情况
- `/req:prd-edit` → 编辑 PRD 章节，支持 AI 从现有需求反推内容

## REQ 模板章节划分

REQ 模板分为三个区域，在不同阶段填充：

| 区域 | 章节 | 填充阶段 | 填充方式 |
|------|------|---------|---------|
| 需求定义 | 一~六（需求描述、功能清单、业务规则、使用场景、接口需求、测试要点） | `/req:new` | AI 提问 + 生成 |
| 流程记录 | 七~九（评审记录、变更记录、关联信息） | 各命令自动 | 自动 |
| 实现方案 | 十（数据模型、文件改动清单、实现步骤） | `/req:dev` | AI 分析代码后生成 |

## 前后端需求管理

前后端需求**分开管理**，通过关联字段链接：

**需求类型：**
- `后端` - 仅涉及后端 API、数据库、业务逻辑
- `前端` - 仅涉及前端页面、组件、交互
- `全栈` - 前后端都涉及（适合小功能）

**典型流程：**
```
1. 产品提出业务需求
2. 拆分为后端需求 + 前端需求
3. 各自独立开发、评审
4. 通过「关联需求」字段互相引用
5. 联调测试
```

**示例：**
```
REQ-001 用户积分-后端    类型=后端  关联=REQ-002
REQ-002 用户积分-前端    类型=前端  关联=REQ-001
```

**筛选命令：**
```bash
/req --type=后端              # 只看后端需求
/req --type=前端 --module=用户  # 前端 + 用户模块
```

## 项目架构适配

本插件**不内置任何项目架构细节**。分层结构、目录路径、命名规范、开发规范、测试规范等信息从使用项目的 CLAUDE.md 中读取。

### CLAUDE.md 架构要求

使用本插件的项目需要在 CLAUDE.md 中包含「项目架构」章节，供 `/req:dev`、`/req:test` 等命令读取。关键信息包括：

- **技术栈**：语言、框架、ORM、数据库
- **分层架构**：各层名称、职责、目录路径（dev-guide 按此顺序引导开发）
- **文件命名**：命名规范
- **开发规范**：错误处理、日志、API 风格等
- **测试规范**：测试文件位置、框架、运行命令

### 初始化引导

`/req:init` 命令会检查项目 CLAUDE.md 是否包含架构信息，缺失时引导用户选择预置模板（Go/Java/前端/通用）追加到 CLAUDE.md。

预置模板存放在 `templates/claude-md-snippets/` 目录。

---

## pm 插件 - 项目管理助手

### 插件定位

pm 插件是 req 插件产出数据的**只读消费者**，从 PRD、需求文档和 Git 记录中提取项目数据，按不同场景和受众生成汇报、统计、方案等项目管理内容。

### 与 req 插件的关系

- **只读不写**：pm 不修改需求文档，不触发 req 的缓存同步 Hook
- **复用存储路径**：遵循 req 的 `docs/requirements/` 和全局缓存路径约定
- **支持所有角色**：`primary` 和 `readonly` 仓库均可使用
- **无需 req 即可工作**：没有需求数据时仍可使用 Git 统计和自由提问功能

### 数据来源

| 数据源 | 提取内容 |
|--------|---------|
| `PRD.md` | 产品愿景、功能规划、技术选型 |
| `active/*.md` | 进行中需求的状态、进度、阻塞项 |
| `completed/*.md` | 已完成需求、完成时间线 |
| `modules/*.md` | 模块职责和需求分布 |
| `INDEX.md` | 需求总览 |
| `git log` | 提交记录、贡献者、分支活动 |
| `git diff --stat` | 代码变更量统计 |
| `git tag` | 版本里程碑 |

### 命令一览

**概览**：
- `/pm` - 项目概况仪表盘

**汇报类**：
- `/pm:weekly [--from] [--to]` - 周报
- `/pm:monthly [--month=YYYY-MM]` - 月报
- `/pm:milestone <版本号>` - 里程碑/版本总结

**统计类**：
- `/pm:stats [--from] [--to]` - 多维度数据统计
- `/pm:progress` - 项目总进度（甘特视图）

**方案类**：
- `/pm:plan <主题>` - 生成方案文档（排期/技术/资源）
- `/pm:brief [--lang=zh|en]` - 项目简介

**风险类**：
- `/pm:risk` - 风险扫描（延期/阻塞/异常检测）

**会议类**：
- `/pm:standup` - 站会摘要（昨天/今天/阻塞）

**通用**：
- `/pm:ask <问题>` - 基于项目数据自由提问
- `/pm:export <命令>` - 导出内容到 docs/reports/
- `/pm:help` - 使用帮助

### 输出保存

所有生成内容均可选择保存到 `docs/reports/` 目录：

```
docs/reports/
├── weekly/              # 周报
├── monthly/             # 月报
├── milestone/           # 里程碑报告
├── stats/               # 统计报告
├── progress/            # 进度报告
├── plans/               # 方案文档
├── risk/                # 风险报告
└── custom/              # 自定义内容
```

### 技能

- `report-generator` - 汇报生成助手，在执行生成类命令时触发，负责数据整合和受众适配

---

## diag 插件 - 生产诊断插件

### 插件定位

diag 插件提供**只读诊断 + 修复建议**能力，覆盖生产应用的报错定位。和 [claude-safe-ops](https://github.com/zhouhao4221/claude-safe-ops) 互补：claude-safe-ops 管"执行类"运维动作，本插件管"只读诊断"。

插件核心边界：

- ✅ **读**：SSH 白名单动词（tail/head/cat/grep/awk/sed/less/wc/find -name/ls/ps/df/free/uptime 等）
- ✅ **容器读**：`docker exec <container> <只读命令>`，inner cmd 同样过白名单+写检测
- ✅ **DB 只读**：mysql/psql/sqlite3/clickhouse-client 执行 SELECT/SHOW/DESCRIBE/EXPLAIN/WITH/ANALYZE，含写关键字立即拒绝
- ⚠️ **受限写**：在 `/diag:diagnose` 会话内允许 `mktemp` / `tee -a` / `rm -f` 操作 `/tmp/claude-diag-<session>-*` 路径；裸重定向 `>` `>>` 仍禁止；诊断结束自动清理
- ❌ **写**：其他一切写操作禁止（mv / cp / chmod / 重定向 / 服务控制 / 包管理 / DB 写等）
- ❌ **代码**：修复建议纯文字，插件**不触发** Edit / Write 改动仓库
- ✅ **审计**：所有 SSH 命令落 JSONL（含 `tmp_write` / `docker_exec` / `db_readonly` 字段），保留 30 天

### 风控 Hook（5 类 + 1 校验）

| Hook | 时机 | 职责 |
|---|---|---|
| `sensitive-input-guard` | UserPromptSubmit | 拦截消息中的 password / token / 私钥 / API key |
| `validate-hooks` | PreToolUse Bash（首次） | 校验所有 Hook 已注册且可执行 |
| `host-whitelist` | PreToolUse Bash | SSH 目标主机必须在 services.yaml 中登记 |
| `command-whitelist` | PreToolUse Bash | SSH 远程命令动词必须在白名单内 |
| `write-guard` | PreToolUse Bash | 阻断重定向、写类动词、服务控制、DB 写、sudo 等 |
| `audit-log` | PostToolUse Bash | JSONL 审计日志（日切分、30 天保留） |

**原则**：全部 Hook 用 `permissionDecision: "deny"` 阻断（不是 "ask"），确保不依赖人工确认即可兜底。不匹配的命令不自动升级到 "ask"，保持明确可预期的放行/拦截边界。

### 命令一览

- `/diag` - 子命令入口
- `/diag:init` - 初始化 `~/.claude-diag/` + 生成服务清单模板 + 依赖检查
- `/diag:diagnose <报错描述> [--service=<name>]` - 报错定位主流程
- `/diag:audit [--host] [--service] [--from] [--to] [--limit]` - 审计查询

### 技能

- `stack-analyzer` - 多栈堆栈识别（Java/Spring、Node、Python、Go、Ruby、PHP），在 `/diag:diagnose` 执行时触发，输出结构化 error_type / message / frames

### 存储

```
~/.claude-diag/
├── config/services.yaml                        # 服务清单（唯一主机白名单源，600 权限）
└── audit/command_audit-YYYY-MM-DD.jsonl        # 审计日志（按日切分）
```

### 与 req / api / pm 的关系

- **独立于三者**：不读 docs/requirements/、不用全局缓存、不改需求文档
- **支持所有角色**：primary / readonly 仓库均可使用
- **与 claude-safe-ops 的协作**：诊断得出修复方案后，用户可自行选择是否通过 claude-safe-ops 或手动执行变更

### 依赖

- `python3`（3.6+，用于 shlex 安全解析 SSH 命令）
- `jq`（Hook 输出 JSON 决策）
- `yq` 或 `python3 + pyyaml`（二选一，YAML 解析）
- 系统 `ssh` + `~/.ssh/config` + SSH Agent（插件不接管凭证）