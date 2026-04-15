---
description: PR 审查与合并 - AI 代码审查、提交评论、合并 PR
argument-hint: "[review|merge] [PR-ID]"
allowed-tools: Read, Glob, Grep, Bash(git:*, gh:*, curl:*)
---

# PR 审查与合并

对已创建的 PR 进行 AI 代码审查，可将审查意见提交到平台（Gitea/GitHub），审查通过后合并 PR。

> 此命令**不受仓库角色限制**，readonly 仓库也可执行。
> 不触发缓存同步。

## 命令格式

```
/req:review-pr [子命令] [REQ-XXX]
```

## 子命令

| 子命令 | 说明 | 示例 |
|--------|------|------|
| (空) | 查看 PR 状态 | `/req:review-pr` |
| `review` | AI 代码审查 | `/req:review-pr review` |
| `merge` | 合并 PR | `/req:review-pr merge` |

- 省略编号时从当前分支自动匹配需求
- 未指定子命令时展示 PR 状态概览

---

## 前置条件

本命令依赖 `/req:pr` 已创建的 PR。如果需求没有关联的 PR：

```
❌ 未找到关联的 PR

💡 请先创建 PR：/req:pr [REQ-XXX]
```

---

## 执行流程（查看状态）

### 1. 识别需求和 PR

**指定编号** → 读取该需求文档
**未指定** → 从当前分支名匹配需求编号（`REQ-\d+` 或 `QUICK-\d+`）

### 2. 查询 PR 信息

根据 `repoType` 查询 PR：

**Gitea**：
```bash
# 从需求的 branch 字段获取分支名，查询关联的 open PR
curl -s "${GITEA_URL}/api/v1/repos/${OWNER}/${REPO}/pulls?state=open&head=${OWNER}:${branch}" \
  -H "Authorization: token ${TOKEN}"
```

**GitHub**：
```bash
gh pr list --head <branch> --json number,title,state,reviews,mergeable,url
```

### 3. 展示状态

```
📋 PR 状态：REQ-001 用户积分规则管理

  🔗 PR #42: feat(REQ-001): 用户积分规则管理
  📊 状态：Open
  🎯 合并方向：feat/REQ-001-user-points → develop
  🔀 可合并：✅ 无冲突 / ❌ 有冲突
  📝 审查：未审查 / ✅ 已通过 / ❌ 需修改

💡 可用操作：
- /req:review-pr review   AI 代码审查
- /req:review-pr merge    合并 PR
```

---

## 执行流程（review - AI 代码审查）

### 1. 获取 PR diff

**Gitea**：
```bash
curl -s "${GITEA_URL}/api/v1/repos/${OWNER}/${REPO}/pulls/${PR_NUMBER}.diff" \
  -H "Authorization: token ${TOKEN}"
```

**GitHub**：
```bash
gh pr diff ${PR_NUMBER}
```

### 2. 读取审查规范

按优先级读取审查依据：
1. 项目 CLAUDE.md 中的**开发规范**章节（错误处理、日志、API 风格等）
2. 项目 CLAUDE.md 中的**测试规范**章节
3. 需求文档中的**功能清单**和**业务规则**（验证实现是否匹配需求）

### 2.5 对比需求文档与实际实现

读取需求文档并与 diff 实际内容交叉检查，找出**文档与代码不一致**的地方，稍后在报告中以「📌 需求文档同步」章节提醒用户更新。

**检查维度：**

| 检查项 | 如何判断 | 提醒内容 |
|--------|---------|---------|
| 状态字段 | 文档状态是否为「开发中 / 测试中」 | 仍为「待评审/草稿」时提醒先走 `/req:review pass` 再合并 |
| 功能清单 (第二章) | diff 是否覆盖清单中每一项 | 未覆盖的项列出；diff 多出的新功能也列出 |
| 接口需求 (第五章) | diff 中新增/修改的路由、DTO 是否在文档中记录 | 缺失的接口列出，建议补充 |
| 数据模型 (10.1) | diff 中的表/字段变更是否在文档中描述 | 未记录的 Model 变更列出 |
| 文件改动清单 (10.2) | diff 实际修改的文件 vs 清单列出的文件 | 两侧差异双向列出（实际多了哪些 / 清单多了哪些） |
| 实现步骤 (10.3) | 清单步骤是否都能在 diff 中找到对应痕迹 | 未落实的步骤列出 |
| 业务规则 (第三章) | 关键规则是否在代码中体现（如余额校验、权限校验） | 代码里找不到校验痕迹的规则列出 |
| 关联需求 | 文档「关联」字段引用的其他需求 | 列出便于用户判断是否需同步更新关联方 |

**读取路径**：
- `primary` 仓库：`docs/requirements/active/<REQ-ID>-*.md`
- `readonly` 仓库：`~/.claude-requirements/projects/<project>/active/<REQ-ID>-*.md`

**未找到需求文档时**（如 `/req:fix`、`/req:do` 创建的无文档分支）跳过本步骤，仅做代码审查。

### 3. AI 逐文件审查

对 diff 中每个变更文件进行审查，检查维度：

| 维度 | 检查内容 |
|------|---------|
| 正确性 | 逻辑是否正确，边界条件是否处理 |
| 安全性 | SQL 注入、XSS、敏感信息泄露、权限校验 |
| 错误处理 | 异常是否捕获，错误是否正确返回 |
| 命名规范 | 变量/函数/文件命名是否符合项目规范 |
| 代码风格 | 是否符合项目 CLAUDE.md 中的编码规范 |
| 需求匹配 | 实现是否覆盖需求文档中的功能清单 |
| 测试覆盖 | 关键逻辑是否有测试，测试是否充分 |

### 4. 输出审查报告

问题分三级：

| 级别 | 含义 | 影响 |
|------|------|------|
| 🔴 阻塞 | 必须修复才能合并 | 阻止合并 |
| 🟡 建议 | 建议修改但不阻止合并 | 不阻止 |
| 🔵 信息 | 知识分享、风格偏好 | 不阻止 |

报告结构包含两部分：
1. **代码审查**：🔴/🟡/🔵 分级的代码问题
2. **📌 需求文档同步**：步骤 2.5 中发现的文档与代码偏差（不阻止合并，但建议用户 `/req:edit` 补齐）

输出格式：

```
📝 AI 代码审查报告：PR #42

  审查文件：8 个
  审查结果：🔴 1 个阻塞 | 🟡 3 个建议 | 🔵 2 个信息
  需求同步：⚠️ 3 项待更新

---

🔴 阻塞问题：

  📄 internal/user/biz/points.go:45
  问题：积分扣减未检查余额是否充足，可能导致负数
  建议：添加余额校验 `if user.Points < amount { return ErrInsufficientPoints }`

---

🟡 建议：

  📄 internal/user/controller/v1/points.go:23
  问题：缺少请求参数校验
  建议：对 amount 字段添加 min=1 校验

  📄 internal/user/store/points_store.go:67
  问题：批量操作未使用事务
  建议：用 db.Transaction() 包裹

  📄 internal/user/model/points_record.go:12
  问题：CreatedAt 字段缺少 json tag
  建议：添加 `json:"created_at"`

---

🔵 信息：

  📄 internal/user/biz/points.go:20
  备注：可以考虑将积分规则抽为配置，方便后续调整

  📄 internal/user/router.go:34
  备注：路由分组命名建议统一为 /api/v1/points（当前为 /api/v1/point）

---

📌 需求文档同步（REQ-001）：

  ⚠️ 文件改动清单未同步
    文档第 10.2 节缺失：
      + internal/user/store/points_record_store.go
      + internal/user/model/points_record.go
    文档第 10.2 节多余（实际未改动）：
      - internal/user/controller/v1/admin_points.go

  ⚠️ 接口未记录
    diff 新增路由 POST /api/v1/points/transfer，文档第五章未记录

  ⚠️ 功能清单覆盖不全
    文档第二章列出但 diff 中未找到实现：
      - "积分过期自动清理"

  💡 建议执行：/req:edit REQ-001，补齐以上内容

---

📊 总结：有 1 个阻塞问题需修复后才能合并；3 项需求文档待同步

💡 可用操作：
- 修复后重新提交：/req:commit
- 修复后重新审查：/req:review-pr review
- 更新需求文档：/req:edit REQ-001
- 无阻塞后合并：/req:review-pr merge
```

### 5. 提交审查评论到平台

审查完成后，**将报告摘要作为 PR 评论提交**到 Gitea/GitHub，团队成员在网页上可见。

**Gitea**：
```bash
curl -s -X POST "${GITEA_URL}/api/v1/repos/${OWNER}/${REPO}/issues/${PR_NUMBER}/comments" \
  -H "Authorization: token ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "body": "<审查报告 Markdown 格式>"
  }'
```

**GitHub**：
```bash
gh pr review ${PR_NUMBER} --comment --body "<审查报告 Markdown 格式>"
```

**repoType = "other"**：仅本地展示，不提交评论。

提交成功后：
```
✅ 审查报告已提交到 PR #42
   🔗 ${PR_URL}
```

---

## 执行流程（merge - 合并 PR）

### 1. 前置检查

依次检查以下条件：

| 检查项 | 失败时行为 |
|--------|-----------|
| PR 是否存在 | ❌ 提示先创建 PR |
| PR 是否 Open 状态 | ❌ 提示 PR 已关闭/已合并 |
| 是否有合并冲突 | ❌ 提示解决冲突后重试 |

```
❌ PR #42 存在合并冲突

💡 解决方式：
  git checkout <branch>
  git merge <merge_target>
  # 解决冲突后
  git add . && git commit
  git push
```

### 2. 执行合并

读取 `branchStrategy.mergeMethod` 配置（默认 `merge`）：

| 值 | 说明 | 适用场景 |
|------|------|---------|
| `merge` | 保留完整提交历史 | 默认，适合大多数团队 |
| `squash` | 压缩为一个提交 | 希望主分支历史简洁 |
| `rebase` | 变基到目标分支 | 追求线性历史 |

**Gitea**：
```bash
curl -s -X POST "${GITEA_URL}/api/v1/repos/${OWNER}/${REPO}/pulls/${PR_NUMBER}/merge" \
  -H "Authorization: token ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "Do": "<mergeMethod>",
    "merge_message_field": "<merge commit message>"
  }'
```

`Do` 字段映射：`merge` → `"merge"`, `squash` → `"squash"`, `rebase` → `"rebase"`

**GitHub**：
```bash
gh pr merge ${PR_NUMBER} --<mergeMethod>
# --merge / --squash / --rebase
```

**repoType = "other"**：
```
🔀 请手动合并 PR

  合并命令：
  git checkout <merge_target>
  git merge <branch>
  git push
```

### 3. 合并成功

```
✅ PR #42 已合并！

  🔗 ${PR_URL}
  🎯 feat/REQ-001-user-points → develop
  📋 合并方式：merge

💡 后续操作：
- /req:done REQ-001   归档需求
```

### 4. 分支清理

合并成功后，读取 `branchStrategy.deleteBranchAfterMerge` 配置（默认 `true`）。

**配置为 true 或未配置时**：

```
🗑️ 是否删除已合并的分支？

  将执行：
  git checkout <merge_target>
  git pull
  git branch -d <branch>
```

等待用户确认：
- 确认 → 执行切换、拉取最新、删除本地分支
- 拒绝 → 保留分支

**配置为 false 时**：不提示，跳过清理。

---

## Git Flow 双 PR 场景

当策略为 `git-flow` 且分支是 hotfix 时，可能存在两个 PR（→ main + → develop）。

此时分别展示/审查/合并两个 PR：

```
📋 Hotfix 关联 2 个 PR：

  1. PR #42: hotfix/fix-order-calc → main     状态：Open
  2. PR #43: hotfix/fix-order-calc → develop   状态：Open

请选择操作的 PR（或输入 all 全部处理）：
```

合并时按顺序：先合并 → main，再合并 → develop。

---

## 与其他命令的衔接

```
/req:dev        开发完成后
    ↓
/req:commit     提交代码
    ↓
/req:pr         创建 PR
    ↓
/req:review-pr review   AI 审查代码 + 提交评论
    ↓
/req:review-pr merge    合并 PR + 清理分支
    ↓
/req:done       归档需求
```

---

## 与 `/req:release` 的关系

**`/req:review-pr merge` 只是完成单个需求的里程碑，不是发版**。具体边界：

1. **migration SQL 在 merge 时不会被归档**
   合并 PR 后，`docs/migrations/` 下该需求的 SQL 文件仍然保留在原目录，不会被搬到 `released/`。这些 SQL 会等到下一次 `/req:release` 被命令合并到 `docs/migrations/released/<version>.sql`，并 `git rm` 原文件。
2. **合并到 `developBranch` ≠ 发布**
   在 git-flow 下，merge 通常是把 feat 分支合到 `developBranch`。发版仍需要跑 `/req:release`，由它走 cross-branch 流程打开 develop → main 的 release PR。
3. **不要为"发版"手工 tag 或手工建 Release**
   发版的所有动作（合并 SQL、生成回滚、changelog、tag、平台 Release）都应该由 `/req:release` 原子化完成。v3.0.0+ 默认 draft 模式，命令完成后你在 Gitea/GitHub 手工 publish 才真正发版——这是"双闸门"的核心。

**典型发版流水线**：

```
REQ-1 /req:review-pr merge     ← 单需求合并（不发版）
REQ-2 /req:review-pr merge     ← 单需求合并（不发版）
REQ-3 /req:review-pr merge     ← 单需求合并（不发版）
                ↓
        /req:release            ← 真正发版，自动推导版本号 + draft
                ↓
        在 Gitea/GitHub 点 Publish
```

---

## 用户输入

$ARGUMENTS
