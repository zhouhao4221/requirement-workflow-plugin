# CLAUDE.md

## 项目本质

DevFlow 是一个 **Claude Code 插件市场（marketplace）**，对外发布 5 个插件，覆盖软件研发全生命周期。

> 在本仓库工作 = **开发/维护这些插件本身**，而非使用它们。下游用户安装插件后在他们自己的项目里跑 `/req:*`、`/pm:*` 等命令。本仓库里出现的 `docs/requirements/`、`docs/reports/` 等是插件自身的 dogfooding 产物（DevFlow 用自己的 req 插件管理自己的需求）。

面向**下游用户**的文档是 `README.md`（+ 英/韩双语）和 `docs/tutorial.md`；本文件（CLAUDE.md）面向**在本仓库工作的 AI 与维护者**。

## 核心心智模型（最重要）

1. **命令/技能文件是「给 Claude 的指令文档」，不是可执行代码。** `commands/<name>.md` 与 `skills/<name>/SKILL.md` 是自然语言指令，运行时由 Claude 解读执行。**改流程 = 改 `.md`**，通常无需动脚本。
2. **脚本（`scripts/`）只做确定性的副作用**：文档校验、状态字段写入、Hook 拦截、布局守卫、外部数据解析（如 Swagger）。不承载业务判断。
3. **共享逻辑抽到 `plugins/<p>/shared/`**，命令用 `../shared/x.md` 链接引用，避免重复、控制 token；**不能放 `commands/` 下**（原因见「命令与技能结构」）。新命令链接到具体专题文件（`_storage`/`_branch`/`_issue`/`_gitea_cli`/`_granularity`/`_template`/`_delegate`/`_verify`/`_claude-md`），不要链 `_common.md`（它只是索引）。
4. **只写 Claude 推不出来的内容**：平台差异约束、非显而易见的业务规则、输出格式。不写 curl/gh/tea 完整命令、Python 实现、URL 模板。判断标准：能从 API 文档或常识推断 → 不写；不能（如「Gitea labels 必须走独立端点」）→ 写。

## 插件全景

| 插件 | 版本 | 职责 | 目录构成 |
|------|------|------|---------|
| **req** | 4.2.1 | 需求全流程：分析→评审→开发→测试→归档 + 分支/PR/issue/版本 | commands shared skills agents hooks scripts templates schemas |
| **pm** | 0.7.0 | 项目管理助手：周报/月报/统计/风险/方案（只读消费 req 数据） | commands shared skills scripts |
| **api** | 0.5.0 | 前端 API 对接：Swagger 解析、字段映射、TS 代码生成 | commands shared skills scripts docs tests |
| **diag** | 0.3.0 | 生产诊断（**全程只读**）：SSH 拉日志→解析堆栈→关联代码→修复建议 | commands skills hooks scripts templates tests |
| **uat** | 1.4.0 | UI 验收测试：AI 按流程文档逐场景执行界面操作（前身 `qa`） | commands skills templates |

整体版本 `marketplace.json` = 2.39.1。**事实源是各 `plugin.json` + `marketplace.json`，不是 README**——README/tutorial 的版本号已过时，且只覆盖 req/pm/api，未收录 diag/uat（已知文档债务，非功能不成熟；diag 由 REQ-001、uat 由 REQ-002 完整交付）。

## 命令与技能结构

**command 是能力的唯一入口；`skills/` 下只放 helper skill**（REQ-003 的「命令→技能镜像」派生机制已于 2026-08 废止）：

- **`commands/<name>.md`**：唯一权威源，且 `commands/` 下**只能**放这类文件（必须有 frontmatter + `description`）。可引用 `../shared/` 里的共享子文件（`_storage.md`、`_gitea_cli.md`、`release-rationale.md` 等）。
- **`skills/<name>/SKILL.md`**：仅限**与任何命令都不同名**的 helper skill（见下节），全部手写。

**两类东西都会污染斜杠菜单，一律禁止**——Claude Code 把 `skills/` 下每个子目录、`commands/` 下每个 `.md` 都注册成菜单项：

- **命令同名 skill 镜像**：与 command 落在同一菜单、`description` 一模一样，每条命令重复两遍（`claude plugin details req` 里出现 `do, do`、`pr, pr`），多出的那份 description 还白占 always-on token。原 `scripts/gen-skills.py` 按 `SKIP_MIRROR` 名单派生的 51 个镜像（req 23 · pm 12 · api 6 · uat 6 · diag 4）已整体删除。
- **共享参考文档放 `commands/`**：`_storage.md` 之类会变出 `/req:_storage` 等 12 个伪命令。统一放 `plugins/<p>/shared/`（req 10 · pm 1 · api 1）。

`scripts/check-layout.py` 一次性守住三条：`skills/` 无命令镜像、`commands/` 无非命令文件、所有相对链接可达。`--check` 报错退 1（发布前置），不带参数则自动清理可清理的部分。

命令 frontmatter：

```yaml
---
description: 命令简介
argument-hint: "[参数] [--选项=值]"
allowed-tools: Read, Glob, Grep
model: claude-haiku-4-5-20251001   # 省略则继承会话模型
---
```

**模型分级**（三档；README 的三档表分配已过时，以本节为准）：

| 策略 | 适用 | 做法 |
|------|------|------|
| 显式 haiku | 纯查询/展示/格式化输出/配置/规则明确的状态流转 | `model: claude-haiku-4-5-20251001` |
| 显式 sonnet | 数据聚合 + 成文类（pm 周报/月报/里程碑/统计/进度/简介/风险扫描）、有界的单元审查 | `model: claude-sonnet-5` |
| 不指定 | 分析代码/生成方案/多轮需求讨论/架构理解/自由问答 | 省略 `model` |

> sonnet 一律写 `claude-sonnet-5`（原生 1M 上下文、超 200K 不加价、Pro/Max 不计 extra usage，2026-08 核实）。`pm:plan`/`pm:ask` 需要真实推理，保持省略。
> 模型分级**仅对 `commands/*.md` 命令调用生效**；helper skill 无 `model` 字段，运行在触发它的会话/命令模型下。
> 边界例外：`done`/`review`/`upgrade`/`release` 虽含写操作，但流程被模板和显式参数高度约束，仍用 haiku。

**子任务委派**（命令内粒度，与整条命令的模型分级正交）：**会话模型专注判断，执行外包给 subagent**——主会话做方案设计、跨文件一致性、闸门交互、验收复核，其余派给 `plugins/req/agents/` 的 6 个 agent，原始输出不进主上下文。

| 只读型 | 用途 | | 可写型 | 用途 |
|--------|------|---|--------|------|
| `code-scout` haiku | 定位代码 | | `impl-worker` sonnet | 按实施单改一个独立单元 |
| `test-runner` haiku | 跑测试 | | `doc-writer` haiku | 按素材+骨架成文/回填章节 |
| `file-reviewer` sonnet | 审一个源文件的 diff | | | |
| `diff-digest` haiku | 压缩大 diff，可逐文件落盘 | | | |

规则见 `shared/_delegate.md`。派生 subagent 的命令 `allowed-tools` 必须列 `Agent`（`allowed-tools` 是白名单限制，不是免确认）。

**委派写操作有准入门槛**（`impl-worker`，见 `_delegate.md` 的「委派实施」）：方案已确认到文件级 + 单元互不依赖 + 契约已定死 + 有验收命令，四条全满足才派；新建抽象、跨层契约变更、方案仍在演化的首版实现一律主会话自己写。验收复核的是 `git diff` 实际内容，不是 subagent 的自述。**降档不是委派的理由**——委派是为了上下文隔离（避免开发中途触发压缩、让已确认方案被摘要化），不是为了把推理换成便宜模型。

**两条已知失败模式**（dogfooding 实测踩过，6 个 `file-reviewer` 里 5 个中招）：① prompt 只给素材的磁盘路径而不内联正文 → subagent 把轮次耗在自己找文件上；② 一个 subagent 塞多个文件 → 撞 `maxTurns` 交出半成品。切分要细、素材要内联。

**allowed-tools**：只读命令不声明 Write/Edit/Bash。**Token 节约**：单文件 < 30 KB；> 50 KB 拆主文件 + rationale；详见 [`docs/design/token-optimization.md`](./docs/design/token-optimization.md)。

## 自动触发技能（helper skill）

`skills/` 下**只有** helper skill——不与任何命令同名，由命令运行时按 `description` 自动激活，提供细化引导：

| 插件 | helper skill |
|------|-------------|
| req | `requirement-analyzer`（new/edit）· `prd-analyzer`（prd-edit）· `dev-guide`（dev，读 architecture.md 分层引导）· `test-guide`（test*）· `quick-fix-guide`（new-quick）· `issue-guide`（issue）· `changelog-generator`（changelog）· `version-bumper`（release，按 semver 推导各插件版本）· `code-impact-analyzer`（需求变更/影响评估）· `natural-language-dispatcher`（自然语言意图→命令映射） |
| pm | `report-generator`（各生成类命令，整合数据为面向受众的文档，禁用 emoji 便于导出） |
| diag | `stack-analyzer`（仅 diagnose 期间，多语言堆栈解析为结构化 YAML） |
| uat | `uat-executor`（仅 run 期间，意图驱动执行界面操作） |
| api | `api-field-mapper`（编辑前端 `.ts/.tsx/.vue` 时被动提示字段映射） |

> `natural-language-dispatcher` 是 req 的关键入口：用户用中文自然语言（非斜杠命令）表达意图时自动激活，识别意图→映射命令。`requirement-analyzer`/`prd-analyzer` 受 Memory 隔离约束：禁止 memory 影响文档结构/内容/格式。

---

## req 插件核心机制

### 双轨需求

| | REQ（正式需求） | QUICK（快速修复） |
|---|---|---|
| 生命周期 | 📝 草稿 → 👀 待评审 → ✅ 评审通过 → 🔨 开发中 → 🧪 测试中 → 🎉 已完成 | 草稿 → 方案确认 → 开发中 → 已完成（跳过评审+测试） |
| 入口 | `/req:new` | `/req:new-quick` |
| 模板 | `requirement-template.md`（一~十一章） | `quick-template.md`（问题/方案/验证/记录） |
| 开发门槛 | `/req:dev` 拒绝未评审的 REQ | 草稿即可开发 |
| 编号 | `REQ-XXX` | `QUICK-XXX`（扫描本地需求目录取最大值+1） |

状态流转由命令驱动：`/req:review pass/reject` · `/req:dev`（自动） · `/req:test`（自动）· `/req:done`（必须 y/n 确认）。`/req:upgrade <QUICK-XXX>` 将未完成的 QUICK 升级为 REQ（4 阶段扩 6 阶段）。无文档的轻量任务走 `/req:fix`（修 bug，含根因分析）和 `/req:do`（优化/重构/升级，AI 选流程）。

### 存储（无全局缓存）

需求文档**唯一事实源**是 primary 仓库的 `requirementsDir`（默认 `docs/requirements/`，纳入 git）。**无全局缓存**：readonly 仓库经 `.devflow/settings.local.json` 的 `requirementSource.path` **直读**主仓需求目录，不复制、不同步。

`docs/requirements/` 子目录：`active/`（进行中）· `completed/`（归档）· `modules/`（模块文档）· `specs/`（规范文档，跨仓库共享）· `templates/`（4 个模板）· `PRD.md` + `INDEX.md`。

**无同步**：需求只有一份，写入即生效，无 PostToolUse 同步 Hook、无 cp。（v2.x 的 `~/.claude-requirements/` 全局缓存 + `sync-cache.sh` 已于 v3 移除——breaking change，旧项目需跑 `/req:migrate` + readonly 重新 `/req:use` 绑定。）

**仓库角色**（`requirementRole`）：`primary` 读写本仓 `requirementsDir`；`readonly` 无本地需求目录、经 `requirementSource.path` 直读主仓、`/req:dev` 跳过所有文档写入。新增写操作命令必须考虑 readonly 跳过逻辑。不受角色限制的命令：`fix`/`do`/`issue`/`branch`。

### Hooks（`plugins/req/hooks/hooks.json`）

| 时机 | 脚本 | timeout | 行为 |
|------|------|---------|------|
| SessionStart | session-context.sh | 10s | 注入需求上下文；未初始化/未配分支策略时输出引导 |
| PreToolUse(Bash) | confirm-before-commit.sh | 120s | 默认放行；仅当 `.claude/.req-confirm-commit` 存在时拦截 git commit / mv·rm 需求文件 |
| PostToolUse(Write/Edit) | validate-requirement.sh | 5s | 校验文档章节 |

**两个 marker（勿混淆）**：
- `.claude/.req-confirm-commit`：**确认开关**（常驻）。存在 = 启用提交拦截；默认不存在 = 全部直通。用户说「开启提交确认」→ Claude `touch`，「关闭」→ `rm`。
- `.claude/.req-auto`：**自动化豁免**（临时，mtime 10 分钟 TTL）。`/req:fix --auto` 流程开始 `touch`、结束 `rm`；存在且有效时让 Hook 放行 commit 弹框。`--auto` 还跳过命令层文本交互（方案确认、类型选择、issue 关闭询问）并自动串联 commit→push→PR。两者均在 `.gitignore`。

### 分支与 issue

`/req:branch init` 配置策略：`github-flow`（main↔main）· `git-flow`（develop↔develop，hotfix 建两个 PR）· `trunk-based`。命名 `<prefix>REQ-XXX-<slug>[-iN]`（slug ≤5 词 kebab-case，`-iN` 为关联 issue 后缀）。

**CLI 选择**（`repoType`）：GitHub → `gh`；Gitea → **优先 `tea`**（login URL 匹配 `giteaUrl`），不支持的操作（评论列表、PR diff/review、标签增删、Release 附件）回退 `curl + giteaToken`。绝不自动 `tea login add`。OWNER/REPO 从 `git remote origin` 解析；`giteaUrl` 只从配置读，禁止从 remote 猜测。

`--from-issue=#N` 全链路：创建时拉 issue → 编号写入文档 `issue` 字段（无文档则靠分支名 `-iN` 后缀）→ commit 追加 `closes #N` → done 时询问 API 关闭（`--auto` 跳过询问，靠 `closes #N` 自动关）。

---

## 项目级配置约定

`.devflow/settings.json`（团队共享、入 git，放非密钥）+ `.devflow/settings.local.json`（不入 git，放密钥/本机路径）。读取时 local 覆盖同名。**Claude Code 自身的 hooks/permissions 仍在 `.claude/settings.json`，两者互不迁移**；项目级窄知识 skill 仍在 `.claude/skills/`。

| 字段 | 文件 | 控制 | 消费者 |
|------|------|------|--------|
| `requirementProject` | settings | 项目名（标签/显示用） | req、pm |
| `requirementRole` | settings | `primary`/`readonly` | req、pm |
| `requirementsDir` | settings | 需求目录，默认 `docs/requirements`，可改 | req、pm |
| `branchStrategy`（对象，不含 token） | settings | `repoType`/`giteaUrl`/`mainBranch`/`developBranch`/`*Prefix`/`branchFrom`/`mergeTarget`/`mergeMethod`/`reviewers` 等 | req、uat |
| `giteaToken` | settings.local | Gitea API token | req、uat |
| `requirementSource`（`{path,project?}`） | settings.local | **readonly 专用**：指向 primary 仓库根的本机绝对路径，据此直读主仓 | req、pm |

跨插件共享：pm 复用 `requirementProject`/`requirementRole`/`requirementsDir`；uat 复用 `branchStrategy`/`giteaToken`。

---

## 项目架构适配

插件不内置项目架构细节，从下游项目的 `docs/prompt/` 和 `.claude/skills/` 读取。

| 位置 | 内容 | 加载方式 |
|------|------|---------|
| `CLAUDE.md` | AI 行为指令（通用规则、引用指针） | 每次会话自动加载 |
| `docs/prompt/architecture.md` | 项目架构知识（分层、规范、技术栈） | `/req:dev`、`/req:test` 显式 Read |
| `docs/prompt/release.md` | 项目发版规则 | `/req:release` 步骤 0 Read |
| `docs/prompt/` Prompt 库（`code-generation`/`refactoring`/`test-generation`/`testing`/`error-diagnosis`/`pr-review`/`requirement-structuring`） | 各方面项目特有规范，统一 5 节骨架 | 对应命令按需 Read（`/req:dev`/`do`/`test*`/`fix`/`review-pr`/`new`·`edit`），缺失降级，非阻塞 |
| `docs/requirements/specs/` | 公共知识层（枚举、规则、契约摘要） | 命令按仓库角色注入 |
| `.devflow/settings.json(.local)` | 结构化配置 | 命令读取字段（local 覆盖同名） |
| `.claude/skills/<concern>.md` | 窄知识具体约定（如路径变量） | 命令扫描全量注入 |

- `/req:init` 扫描项目结构生成 `docs/prompt/architecture.md`；CLAUDE.md 只留引用指针，不内嵌架构内容。Prompt 库其余 7 文件从 `templates/prompt-snippets/` 复制空骨架（仅当不存在），供下游按项目填充；骨架格式见 `prompt-craft.md`。
- 项目级 skill 文件名反映关注点（`migration.md` ✅，`config.md` ❌）；`docs/prompt/` 文件按需 Read，缺失时打印创建提示（非阻塞）。
- 现有示例：`.claude/skills/migration.md` 声明 `MIGRATIONS_DIR`，供 `/req:dev` 写入、`/req:release` 扫描合并。Changelog 目录固定 `docs/changelogs/`，不参与配置。
- **Prompt 结构验证**：`plugins/req/schemas/prompt-schema.md` 定义各命令期望的 prompt 文件结构；`/req:update` 拉新版本后对照检查，缺必需章节报错、缺推荐章节警告。

---

## 其他插件要点

**pm** — req 数据的**只读消费者**，从 PRD/需求文档/Git 记录生成内容。无 req 数据时仍可用（仅 Git 指标）。命令：`/pm` · `weekly` · `monthly` · `milestone` · `stats` · `progress` · `plan` · `risk` · `standup` · `ask` · `brief` · `export` · `help`（13 条）。输出到 `docs/reports/`。

**api** — 前端 API 对接。配置 `.api-config.json`（项目根，入 git）；Swagger **不缓存**，每次实时解析（`scripts/swagger-parser.py`，无第三方依赖）。产物：TS 类型→`{typeDir}`、请求函数→`{outputDir}`；gen 做字段 diff + 引用文件影响分析后才写入。命令：`/api`（入口）· `import` · `search` · `map` · `gen` · `config` · `help`（7 条）。

**diag** — 生产诊断，**全程只读**，与 [claude-safe-ops](https://github.com/zhouhao4221/claude-safe-ops) 互补。边界：SSH 只读命令 ✅ · DB SELECT ✅ · 远端 `/tmp/claude-diag-*` append ⚠️ · 写操作/Edit/Write ❌。**6 个风控 Hook 全 deny**：敏感输入拦截 · Hook 完整性自检（防风控链被禁用）· SSH 主机白名单 · 命令动词白名单 · 写操作+本地提权阻断 · JSONL 审计（30 天）。**改动 hooks/ 须同步 hooks.json 注册，否则被 validate-hooks 拦截。** 命令：`/diag`（入口）· `init` · `diagnose` · `audit`（4 条）。存储 `~/.claude-diag/`。依赖：`python3` · `jq` · `yq`/`pyyaml` · `ssh`。

**uat** — UI 验收测试。存储：`docs/uat/flows/`（流程文档，入 git）· `docs/uat/reports/` + `screenshots/`（`.gitignore`）。`/uat:run` 激活 `uat-executor`，意图驱动、不依赖预写选择器（testid 为可选加速）。结果四态 PASS/⚠️PASS/FAIL/SKIP。命令：`/uat`（入口）· `init`（首次必跑，装 skill 到项目）· `new` · `run` · `report` · `bug`（FAIL→issue，6 条）。

---

## 维护规则与易错点

1. 能力只改 `commands/<name>.md`（及其 `shared/_*.md` 子文件）；发布前跑 `python3 scripts/check-layout.py --check` 守住菜单与链接。helper skill 手写，脚本不碰。
2. 共享规则改 `_*.md`，勿在每个命令重复。**共享文件之间不要用 Markdown 链接互引**（命令会顺着链接把整组 ~33KB 全读进来），互相提及写纯文本文件名，仅真实依赖用链接。
3. `requirementRole=readonly` 是贯穿多命令的分支点，新增写命令必须处理跳过。
4. **`scripts/` 下的 hook 脚本同样受配置约定管辖**：读 `.devflow/settings.json(.local)`、按 `requirementsDir` 解析路径、readonly 走 `requirementSource.path`，不得写死 `docs/requirements` 或回退 `.claude/`。改配置约定时必须连带检查 `hooks.json` 注册的每个脚本——v2.39.1 修的就是它们漏跟 v3 迁移、静默失效整整四个版本。
5. 两个 marker：`.req-confirm-commit`=开关常驻，`.req-auto`=临时豁免有 TTL。
6. Gitea 一律「tea 优先、curl 回退」，禁止自动 `tea login add`。
7. 模型分级三档（haiku / `claude-sonnet-5` / 省略）按推理强度选，helper skill 无 `model` 字段；命令内高吞吐步骤走 subagent 委派而非降整条命令的档位。委派规则集中在 `shared/_delegate.md`：切分要细（一个 subagent 一个源文件/一个单元）、素材正文内联进 prompt（给路径必超轮）、写操作满足准入四条才派、超轮用 SendMessage 续问而非重派。详见「命令与技能结构」。
8. diag 的 6 个风控 Hook 是设计核心，改 hooks 必须同步注册。
9. `/req:release` 用 `version-bumper` 按 semver 推导各插件版本；发布事实源是 plugin.json，README 版本号需手动同步（当前已滞后）。
10. **改 `agents/` 或任何插件文件后，本仓库工作区的改动对运行时无效**——Claude Code 运行时加载的是 `~/.claude/plugins/cache/devflow/<plugin>/<version>/`，`/plugin` 更新则从 `~/.claude/plugins/marketplaces/devflow`（GitHub 克隆）拉。cache 按版本号分目录，**不 bump 版本号 `/plugin` 会报「already at the latest version」而不更新**。要让改动生效并可实测，必须走完：提交 → push → `/plugin` 更新 → `/reload-plugins`。在此之前跑 subagent 测的都是旧定义。
