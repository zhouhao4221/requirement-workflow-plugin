---
description: PR 审查与合并 - AI 代码审查、提交评论、合并 PR
argument-hint: "[review|merge|fetch-comments] [PR-ID] [--level=low|medium|high] [--auto]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(git:*, gh:*, tea:*, curl:*), Agent, Skill
---

# PR 审查与合并

对已创建的 PR 进行 AI 代码审查，可将审查意见提交到平台，审查通过后合并 PR。

> 不受仓库角色限制，readonly 可执行。
>
> CLI 优先级：GitHub → `gh pr`/`gh api`；Gitea → 按 [`_gitea_cli.md`](../shared/_gitea_cli.md) 检测 `tea`。tea 未覆盖的接口走 curl。

## 命令格式

```
/req:review-pr [子命令] [REQ-XXX]
```

| 子命令 | 说明 | 示例 |
|--------|------|------|
| (空) | 查看 PR 状态 | `/req:review-pr` |
| `review` | AI 代码审查（`--level=` 指定 `/code-review` 档位，省略则按 PR 复杂度自动选） | `/req:review-pr review` |
| `fetch-comments` | 拉取 PR 评论，AI 生成修改清单并应用 | `/req:review-pr fetch-comments` |
| `merge` | 合并 PR | `/req:review-pr merge` |

省略编号时从当前分支自动匹配需求。未指定子命令时展示 PR 状态概览。

---

## 前置条件

依赖 `/req:pr` 已创建 PR。未找到关联 PR 时提示先创建。

---

## 查看状态

根据 `repoType` 查询 PR（从需求文档 `branch` 字段取分支名，Gitea 需指定 `head=OWNER:branch`）。展示：PR 编号、标题、状态、合并方向、是否可合并、审查状态、可用操作。

---

## review — AI 代码审查

### 1. 取 diff 并判定规模

PR 元数据按平台取（GitHub `gh pr view`，Gitea `/pulls/{N}`），diff 一律走本地 git：fetch PR 分支与 `mergeTarget` 两端后 `git diff --stat <mergeTarget>...<branch>` 得到文件数与行数。

| PR 规模 | 判定 | diff 进主会话的方式 |
|---------|------|-------------------|
| 小 PR | ≤ 10 个文件且 ≤ 800 行 | 读全量 diff |
| 大 PR | 超过任一阈值 | 派 `diff-digest` 取摘要（无需落盘），diff 原文不进主会话 |

### 2. 读取审查依据

按优先级：项目 CLAUDE.md 开发规范 → 测试规范 → 需求文档功能清单和业务规则。

另 Read `docs/prompt/pr-review.md`，存在则将其审查维度（必备输入、优质输出标准、常见失败模式）并入第 4 步审查关注点；缺失静默跳过。

### 3. 对比需求文档与实际实现

检查维度：

| 检查项 | 判断依据 |
|--------|---------|
| 状态字段 | 文档状态是否为「开发中/测试中」 |
| 功能清单 (第二章) | diff 是否覆盖清单每一项 |
| 接口需求 (第五章) | diff 中路由/DTO 是否在文档中记录 |
| 数据模型 (11.1) | 表/字段变更是否在文档中描述 |
| 文件改动清单 (11.3) | diff 实际文件 vs 清单列出文件 |
| 实现步骤 (11.4) | 清单步骤是否在 diff 中能找到 |
| 业务规则 (第三章) | 关键规则是否在代码中体现（如校验逻辑） |
| 关联需求 | 文档「关联」字段引用 |

> primary 读 `docs/requirements/active/`，readonly 读 `<requirementSource.path>/<requirementsDir>/active/`。未找到需求文档时跳过此步。
>
> 大 PR 用第 1 步 `diff-digest` 返回的文件清单与结构性改动（路由、DTO、表/字段）做比对，不拉 diff 原文。

### 4. 代码质量审查

| PR 规模 | 方式 |
|---------|------|
| 小 PR | 主会话基于第 1 步读入的 diff 内联审查：正确性、安全性、错误处理、需求匹配、测试覆盖 |
| 大 PR | 调用原生 `/code-review`（Skill 工具），主会话不看 diff 原文，只接收已验证的问题清单 |

> 大 PR 不再自研逐文件委派：原生审查多 agent 并行 + 逐条验证去重，实测无误报且跨文件问题自己追完；而自研路径要主会话把 diff 再抄进每个 prompt，「diff 不进主会话」并不成立。它的 fork 跑在**会话模型**上，成本随会话模型走，一次 medium 约 6 分钟。

**4.1 档位**：`--level=` 显式指定优先；否则按下表打分自动选，并在输出里打印 `档位：<level>（命中：<信号列表>）`，便于事后调阈值。信号全部来自第 1 步的 `git diff --numstat` 与 `diff-digest` 返回的结构性改动清单，不额外读文件内容。

| 分值 | 信号 | 判定依据 |
|------|------|---------|
| +1 | 规模大 | 超过 30 个文件或 2000 行 |
| +1 | 契约变更 | 结构性改动含接口签名、DTO/表字段、错误码、配置项或依赖变化 |
| +1 | 敏感路径 | 路径含 `migration`/`schema`/`.sql`、`auth`/`permission`/`acl`/`rbac`、`pay`/`billing`、`delete`/`purge`/`drop` |
| +1 | 缺测试 | 源码文件有改动，但测试文件改动行数不足源码改动的 10% |
| +1 | 跨模块 | 改动落在 ≥ 3 个顶层模块目录 |
| −1 | 轻量 | QUICK 需求或 hotfix 分支 |
| −1 | 非代码为主 | ≥ 80% 改动行在文档、配置、lock、生成文件 |

总分 ≤ −1 → `low`；0 或 1 → `medium`；≥ 2 → `high`。不自动选 `max`；`ultra` 不能由命令触发且单独计费，只在报告末尾提示「可手动 `/code-review ultra <PR#>`」。

**4.2 目标**：GitHub 传 PR 号；Gitea 与 `other` 传 ref 范围 `<mergeTarget>...<branch>`（第 1 步已 fetch 两端，ref 范围只依赖本地 git）。调用形式 `/code-review <level> <target>`。**不加 `--comment`**：GitHub 上会出现两套评论来源，Gitea 不支持；评论统一走第 6 步。

**4.3 结果映射**：Important → 阻塞；Nit → 建议；Pre-existing → 信息，并标注「非本 PR 引入」。原生结果已验证与去重，主会话不逐条复审，只核对与第 3 步「需求文档同步」是否重复。

**4.4 不可用时**：`/code-review` 不在可用技能列表（旧版本或被 `skillOverrides` 锁为仅用户可调用）→ 退回小 PR 的内联方式审查，并在报告首行注明「原生审查不可用，已内联审查」。

### 5. 输出审查报告

问题分三级：**阻塞**（阻止合并）、**建议**（不阻止）、**信息**（知识分享）。

报告分两部分：代码审查 + 需求文档同步（文档与代码偏差，不阻止合并但建议 `/req:edit` 补齐）。

### 6. 提交审查评论

**零问题直通**：阻塞=0、建议=0、文档同步项=0 时，自动用固定模板提交通过评论，跳过确认。

**有任意问题时**：展示精简版预览 → 询问用户是否提交（`--auto` 跳过确认）。

> 精简规则：保留阻塞（全部）、关键建议、文档同步关键缺失；去除信息级备注、风格命名建议、过程信息。控制在 300 字以内。
>
> Gitea：PR 评论用 `/issues/{N}/comments`（不是 `/pulls/`）。`repoType = "other"` 仅本地展示。

### 7. 无阻塞时的后续操作

阻塞=0 且 PR 为 Open 时：
- **有审核人**（PR reviewers 或 `branchStrategy.reviewers`）→ 提示是否提交 Approved（Gitea `POST /pulls/{N}/reviews` body `{"event":"APPROVED"}`，GitHub `gh pr review --approve`）
- **无审核人** → 仅展示结果，提示可 `/req:review-pr merge`

---

## fetch-comments — 拉取评论并修改代码

### 1. 拉取评论

同时拉取 Issue Comments（整体讨论）和 Review Comments（行内评论，含 `path` 和 `line` 字段）。
Gitea：整体评论 `/issues/{N}/comments`，行内评论先 `GET /pulls/{N}/reviews` 再逐条 `/reviews/{ID}/comments`。

### 2. 过滤评论

排除：当前 git 用户自己的评论、已 resolved/outdated 的行评论、AI 自提交的审查报告（body 以 `AI 代码审查报告` 开头）。

### 3. 展示 & 分析

分组展示评论清单，逐条读取引用源码位置（±20 行上下文），判断可执行/需讨论，生成修改方案。用户确认后执行。

---

## merge — 合并 PR

### 前置检查

PR 存在 → PR 为 Open → 无合并冲突。逐项失败时提示处理方式。

### 执行合并

读取 `branchStrategy.mergeMethod`（默认 `merge`），按平台执行（GitHub `gh pr merge --<mergeMethod>`，Gitea merge method 通过 `Do` 字段传递）。`repoType = "other"` 展示手动合并命令。

### 合并后

输出合并信息，提示 `/req:done` 归档。读取 `branchStrategy.deleteBranchAfterMerge`（默认 `true`），询问是否删除已合并分支。

---

## Git Flow 双 PR 场景

hotfix 分支可能存在两个 PR（→ main + → develop），分别展示，按先 main 后 develop 顺序操作。

---

## 与 `/req:release` 的关系

`/req:review-pr merge` 是单需求里程碑，不是发版：
- migration SQL 在 merge 时不会被归档，等 `/req:release` 统一处理
- 合并到 developBranch ≠ 发布
- 不要手工 tag 或建 Release，应由 `/req:release` 原子化完成

---

## 用户输入

$ARGUMENTS
