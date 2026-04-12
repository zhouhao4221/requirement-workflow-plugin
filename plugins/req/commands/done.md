---
description: 完成需求 - 标记完成并归档
argument-hint: "[REQ-XXX]"
allowed-tools: Read, Write, Edit, Glob, Bash(git:*, mv:*, gh:*, curl:*)
model: claude-sonnet-4-6
---

# 完成需求

标记需求为已完成，归档文档。

> 存储路径和缓存同步规则见 [_common.md](./_common.md)

## 命令格式

```
/req:done [REQ-XXX]
```

- 省略编号时自动选择「测试中」的需求
- 多个候选时交互式选择（列出编号列表，用户输入编号）

---

## 执行流程

### 1. 选择需求

- 指定编号 → 使用该需求
- 未指定 → 查找可完成需求（状态为测试中）

### 2. 前置检查

- 状态必须为「测试中」
- 检查测试完成情况，有未通过时展示警告：

```
⚠️ 存在未通过的测试
以下测试未通过：
- [列出未通过的测试项]

强行完成可能导致带缺陷上线。
```

### 3. 生成完成摘要

```
📋 需求完成确认：REQ-001 部门渠道关联

📊 完成统计：
- 功能点：6/6 ✅
- 测试点：8/8 ✅
- 涉及文件：12 个
- 开发周期：2 天（2026-01-07 ~ 2026-01-08）

📁 代码变更：
新增文件（4）：
- internal/sys/model/sys_dept_channel_model.go
- internal/sys/store/sys_dept_channel_store.go
- internal/sys/biz/dept_channel.go
- docs/migrations/1.2/1.2.3.sql

修改文件（8）：
- internal/sys/biz/sys_dept.go
- internal/sys/controller/v1/sys_dept.go
- internal/sys/router.go
- pkg/api/core/v1/sys_dept.go
- internal/oms/store/sales_order_store.go
- internal/oms/biz/sales_order_biz.go
- internal/dashboard/store/sales_dashboard_store.go
- internal/dashboard/biz/sales_dashboard_biz.go

即将归档需求 REQ-XXX
- 需求文档将从 active/ 移至 completed/
- 状态将变为「已完成」
- 归档后需手动恢复
```

### 4. 更新需求文档

- 修改元信息状态为「已完成」
- 勾选生命周期「已完成」
- 记录完成时间

### 5. 更新 PRD 索引

在 `docs/requirements/PRD.md` 的「需求追踪」章节中，更新对应需求的状态和完成日期：

```markdown
| REQ-XXX | 需求标题 | 模块名 | 已完成 | 创建日期 | YYYY-MM-DD |
```

若 PRD.md 不存在或无「需求追踪」章节，跳过此步骤。

### 6. 归档文档并同步缓存

- 移动到 completed/ 目录
- **必须执行缓存同步**：
  1. 读取 `.claude/settings.local.json` 获取 `requirementProject`
  2. 若项目已绑定，执行缓存归档：
     ```bash
     CACHE_ROOT=~/.claude-requirements/projects/<project>
     mv $CACHE_ROOT/active/REQ-XXX-*.md $CACHE_ROOT/completed/
     ```
  3. 缓存目录不存在时跳过（项目未初始化）

### 7. 生成完成报告

```
🎉 需求已完成！

═══════════════════════════════════════════════
📋 需求完成报告
═══════════════════════════════════════════════

📌 基本信息
- 编号：REQ-001
- 标题：部门渠道关联
- 优先级：P1
- 负责人：-

📅 时间线
- 创建：2026-01-07
- 评审通过：2026-01-07
- 开发完成：2026-01-08
- 测试通过：2026-01-08
- 完成：2026-01-08
- 总周期：2 天

📊 工作量
- 功能点：6 个
- 测试点：8 个
- 新增文件：4 个
- 修改文件：8 个

📁 归档位置
$REQ_COMPLETED/REQ-001-部门渠道关联.md

═══════════════════════════════════════════════

💡 后续操作：
- 合并分支（如有）：见下方分支合并提醒
- 查看历史需求：ls docs/requirements/completed/
- 创建新需求：/req:new
- 查看活跃需求：/req
```

### 8. 分支合并提醒

> 读取 `.claude/settings.local.json` 的 `branchStrategy`，根据策略和仓库类型生成合并建议。

```python
strategy = read_settings("branchStrategy")
branch = req_doc.branch  # 需求文档中的 branch 字段

if not branch or branch == "-":
    # 无分支记录，跳过
    pass
else:
    if strategy:
        merge_target = strategy["mergeTarget"]
        delete_after = strategy.get("deleteBranchAfterMerge", True)
        model = strategy["model"]
        repo_type = strategy.get("repoType", "other")
        gitea_url = strategy.get("giteaUrl")
    else:
        merge_target = detect_main_branch()
        delete_after = True
        model = None
        repo_type = "other"
```

#### 根据仓库类型决定合并方式

**repoType = "gitea"** → 自动创建 Gitea PR：

```
🔀 正在创建 Pull Request ...

  分支：feat/REQ-001-user-points → main
  标题：feat(REQ-001): 用户积分规则管理
```

通过 Gitea REST API 创建 PR：

```bash
# 从 git remote 解析 owner/repo
REMOTE_URL=$(git remote get-url origin)
# 支持 SSH 和 HTTPS 格式解析

# 先推送分支到远程
git push -u origin <branch>

# 调用 Gitea API 创建 PR
curl -s -X POST "${GITEA_URL}/api/v1/repos/${OWNER}/${REPO}/pulls" \
  -H "Authorization: token ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "feat(REQ-001): 用户积分规则管理",
    "body": "## 需求\n- 编号：REQ-001\n- 标题：用户积分规则管理\n\n## 变更内容\n[从需求文档提取功能清单]",
    "head": "<branch>",
    "base": "<merge_target>"
  }'
```

成功后输出：
```
✅ PR 已创建！

  🔗 ${GITEA_URL}/${OWNER}/${REPO}/pulls/<pr_number>
  📋 标题：feat(REQ-001): 用户积分规则管理
  🎯 合并方向：feat/REQ-001-user-points → main

💡 后续操作：
- /req:review-pr review   AI 代码审查
- /req:review-pr merge    审查通过后合并 PR
```

失败时回退到手动模式（输出合并命令）。

**giteaToken 缺失时**：
```
⚠️ giteaToken 未配置。无法通过 API 自动创建 PR。

  💡 设置方式：在 .claude/settings.local.json 的 branchStrategy 中配置 giteaToken：
  "giteaToken": "<your-token>"
  生成方式：Gitea → 设置 → 应用 → 生成令牌（需 repo 权限）

  手动创建 PR：
  ${GITEA_URL}/${OWNER}/${REPO}/compare/${merge_target}...<branch>
```

**repoType = "github"** → 提示使用 gh CLI：

```
🔀 分支合并提醒：

  分支：feat/REQ-001-user-points → main

  推送并创建 PR：
  git push -u origin feat/REQ-001-user-points
  gh pr create --title "feat(REQ-001): 用户积分规则管理" --base main
```

**repoType = "other"** → 仅展示合并命令：

```
🔀 分支合并提醒：

  当前分支：feat/REQ-001-user-points
  合并目标：main

  合并命令：
  git checkout main && git merge feat/REQ-001-user-points

  删除分支：
  git branch -d feat/REQ-001-user-points
```

#### Git Flow 额外提醒

当 `model == "git-flow"` 且分支是 hotfix 时，需要合并到两个分支。

**Gitea**：创建两个 PR（hotfix → main，hotfix → develop）
**GitHub**：提示创建两个 `gh pr create`
**Other**：展示两组合并命令

```
🔀 分支合并提醒（Git Flow）：

  当前分支：hotfix/fix-order-calc
  需合并到 2 个分支：

  1. 合并到 develop：
     git checkout develop && git merge hotfix/fix-order-calc

  2. 合并到 main（如需发布）：
     git checkout main && git merge hotfix/fix-order-calc

  删除分支：
  git branch -d hotfix/fix-order-calc
```

### 9. 可选：Git 提交关联

如果有关联的 Git 提交，显示提交记录：

```
📝 关联的 Git 提交：
- d7929c9 feat(sys): 实现部门渠道关联 (REQ-001)
- 36c055f feat(sys): 添加部门渠道缓存机制 (REQ-001)
```

---

## 回滚操作

如果需要将已完成的需求重新激活：

```bash
# 手动操作
mv $REQ_COMPLETED/REQ-001-*.md $REQ_ACTIVE/
# 然后修改文档状态
```

---

## 统计数据

完成需求时自动统计：
- 需求总数
- 平均完成周期
- 功能点完成率
- 测试通过率

数据可用于团队效能分析。

---

## 与 `/req:release` 的关系

**`/req:done` 只归档需求，不触发发版**。两条命令对应完全不同的动作：

| 命令 | 动作 | 可见性 |
|------|------|--------|
| `/req:done` | 本地移动 `active/` → `completed/`，更新 INDEX | 仅团队内部 |
| `/req:release` | 合并 SQL + 生成回滚 + changelog + tag + 平台 Release | **对外发布** |

**完成一批需求后发版的正确流程**：

1. 每个需求 `/req:done` 归档
2. 累积到想发版时，跑 `/req:release`（v3.0.0+ 可不传版本号，自动推导）
3. `/req:release` **默认创建 draft**，命令跑完后需要你手工去 Gitea/GitHub 点 Publish 才真正对外发布
4. 如果这些需求带了 `docs/migrations/*.sql`，会在 `/req:release` step 6 被合并到 `docs/migrations/released/<version>.sql`，原文件被 `git rm`

**注意**：`/req:done` **不会**自动把 migration SQL 归档到 `released/`。归档是 release 命令的职责，不是 done 的。如果你在 done 之后看到需求的 migration 文件还在 `docs/migrations/` 下，那是正常的——它们在等下一次 release。

## 用户输入

$ARGUMENTS
