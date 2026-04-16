---
description: 完成需求 - 标记完成并归档
argument-hint: "[REQ-XXX]"
allowed-tools: Read, Write, Edit, Glob, Bash(git:*, mv:*, gh:*, curl:*)
model: claude-haiku-4-5-20251001
---

# 完成需求

标记需求为已完成，归档文档。

> 存储路径和缓存同步规则见 [_common.md](./_common.md)

## 命令格式

```
/req:done [REQ-XXX]
```

- 省略编号时自动选择「测试中」的需求
- 多个候选时交互式选择

---

## 执行流程

### 1. 选择需求

- 指定编号 → 使用该需求
- 未指定 → 扫描 `active/` 中状态为「测试中」的需求，唯一则直接使用，多个则列出让用户选

### 2. 前置检查

- 读取需求文档 YAML 元信息 + 「测试要点」章节
- 状态必须为「测试中」，否则报错退出
- 若测试要点中存在未勾选项（`- [ ]`），展示警告并要求用户确认继续

### 3. 更新需求文档

修改 YAML 元信息：
- `status: 已完成`
- `completedAt: YYYY-MM-DD`（今日）

勾选生命周期「已完成」对应的复选框。

### 4. 更新 PRD 索引

定位 `docs/requirements/PRD.md` 的「需求追踪」章节（`grep -n "需求追踪"`），更新对应需求所在行的「状态」和「完成日期」两列。PRD 不存在或无该章节时跳过。

### 5. 归档文档 + 同步缓存

```bash
git mv docs/requirements/active/REQ-XXX-*.md docs/requirements/completed/
```

缓存同步由 PostToolUse Hook 自动处理，无需命令内显式调用。

### 6. 输出确认

```
🎉 REQ-XXX <标题> 已完成
   归档至 docs/requirements/completed/REQ-XXX-<slug>.md
```

### 7. 分支合并提醒

读取 `.claude/settings.local.json.branchStrategy` 和需求文档的 `branch` 字段。无 `branchStrategy` 或 `branch` 为空 → 跳过本步。

按 `repoType` 决定动作：

**gitea** — 通过 REST API 自动创建 PR：

```bash
git push -u origin <branch>
curl -s -X POST "${giteaUrl}/api/v1/repos/${OWNER}/${REPO}/pulls" \
  -H "Authorization: token ${giteaToken}" \
  -H "Content-Type: application/json" \
  -d '{"title":"feat(REQ-XXX): <标题>","head":"<branch>","base":"<mergeTarget>","body":"..."}'
```

成功 → 输出 PR 链接，并提示 `/req:review-pr review` / `/req:review-pr merge`。
`giteaToken` 缺失 → 提示手工 compare 链接。

**github** — 输出：
```
git push -u origin <branch>
gh pr create --title "feat(REQ-XXX): <标题>" --base <mergeTarget>
```

**other** — 输出本地 merge 命令（`git checkout <mergeTarget> && git merge <branch>`）。

**Git Flow + hotfix 分支**：合并到 `main` 和 `develop` 两处，Gitea/GitHub 创建两个 PR，other 输出两组命令。

### 8. 关联 issue 关闭提醒

按 [_common.md 的 Issue 读取优先级](./_common.md#issue-编号的读取优先级) 获取 issue 编号：先查需求文档元信息 `issue` 字段，若为 `-` 或为空则查分支名 `-iN` 后缀。均未找到 → 跳过本步。

否则询问用户：

```
🔗 检测到关联 issue: #123
   是否关闭该 issue？(y/n)
```

**用户确认（y）**，按 `repoType` 调用对应 API：

**gitea**：
```bash
curl -s -X PATCH "${giteaUrl}/api/v1/repos/${OWNER}/${REPO}/issues/${ISSUE_NUM}" \
  -H "Authorization: token ${giteaToken}" \
  -H "Content-Type: application/json" \
  -d '{"state":"closed"}'
```

**github**：
```bash
gh issue close ${ISSUE_NUM} --comment "Closed by REQ-XXX"
```

**other**：输出提示让用户手工关闭：
```
💡 请手动关闭 issue #123
```

**用户拒绝（n）**：跳过，不做任何操作。

成功关闭后输出：
```
✅ Issue #123 已关闭
   🔗 ${ISSUE_URL}
```

---

## 与 `/req:release` 的区别

`/req:done` 只做归档，不发版。发版用 `/req:release`（合并 SQL / 生成 changelog / 打 tag / 创建 Release）。

## 用户输入

$ARGUMENTS
