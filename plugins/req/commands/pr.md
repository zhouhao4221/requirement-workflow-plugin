---
description: 创建 PR - 根据仓库类型自动创建 Pull Request
argument-hint: "[REQ-XXX]"
allowed-tools: Read, Glob, Grep, Bash(git:*, gh:*, curl:*)
model: claude-sonnet-4-6
---

# 创建 Pull Request

根据分支策略中的仓库类型，自动推送分支并创建 PR。

> 此命令**不受仓库角色限制**，readonly 仓库也可执行。
> 不触发缓存同步。

## 命令格式

```
/req:pr [REQ-XXX] [--title=自定义标题] [--base=目标分支]
```

- 省略编号时根据当前分支自动匹配需求
- `--title` 覆盖自动生成的 PR 标题
- `--base` 覆盖策略配置的合并目标

---

## 执行流程

### 1. 识别需求和分支

**指定编号**：读取该需求文档的 `branch` 字段
**未指定**：从当前分支名匹配需求编号

```bash
CURRENT=$(git branch --show-current)
# 从分支名提取 REQ-XXX 或 QUICK-XXX
```

匹配失败时提示：
```
⚠️ 当前分支 <branch> 未关联需求，请指定需求编号：/req:pr REQ-001
```

### 2. 前置检查

```bash
# 检查是否有未提交的改动
git status --porcelain
```

有未提交改动时，**自动执行 `/req:commit` 流程**（分支检查 → 暂存 → 生成提交信息 → 提交），完成后继续创建 PR。

```
📦 检测到未提交的改动，先执行提交...
```

提交完成后自动进入步骤 3。

### 3. 读取策略配置

```python
strategy = read_settings("branchStrategy")

if strategy:
    repo_type = strategy.get("repoType", "other")
    merge_target = strategy.get("mergeTarget", "main")
    gitea_url = strategy.get("giteaUrl")
    main_branch = strategy.get("mainBranch", "main")
else:
    repo_type = "other"
    merge_target = detect_main_branch()
```

`--base` 参数覆盖 `merge_target`。

### 4. 生成 PR 信息

**标题生成规则**：
- REQ-XXX → `feat(REQ-XXX): <需求标题>`
- QUICK-XXX → `fix(QUICK-XXX): <需求标题>`
- hotfix 分支 → `hotfix: <描述>`
- `--title` 参数覆盖自动标题

**Body 生成**：从需求文档提取关键信息

```markdown
## 需求
- 编号：REQ-XXX
- 标题：XXX
- 状态：开发中

## 功能清单
[从需求文档「二、功能清单」提取]

## 变更文件
[从需求文档「十、实现方案」的文件改动清单提取，或通过 git diff 生成]
```

### 5. 推送分支

```bash
# 推送到远程（如果还没推送）
git push -u origin <branch>
```

### 6. 根据仓库类型创建 PR

---

#### repoType = "gitea"

通过 Gitea REST API 创建 PR。

**解析远程仓库信息**：
```bash
REMOTE_URL=$(git remote get-url origin)
# SSH: git@git.example.com:owner/repo.git → owner, repo
# HTTPS: https://git.example.com/owner/repo.git → owner, repo
```

**检查 Token**：
```
从 branchStrategy.giteaToken 读取 token 值
TOKEN = strategy.giteaToken
```

Token 缺失时：
```
⚠️ giteaToken 未配置。无法通过 API 自动创建 PR。

  💡 设置方式：在 .claude/settings.local.json 的 branchStrategy 中配置 giteaToken：
  "giteaToken": "<your-token>"
  生成方式：Gitea → 设置 → 应用 → 生成令牌（需 repo 权限）

  手动创建 PR：
  ${GITEA_URL}/${OWNER}/${REPO}/compare/${base}...<branch>
```

**调用 API**：
```bash
curl -s -X POST "${GITEA_URL}/api/v1/repos/${OWNER}/${REPO}/pulls" \
  -H "Authorization: token ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "<pr_title>",
    "body": "<pr_body>",
    "head": "<branch>",
    "base": "<merge_target>"
  }'
```

**检查是否已存在 PR**（避免重复创建）：
```bash
# 先查询是否已有从 head 到 base 的 PR
curl -s "${GITEA_URL}/api/v1/repos/${OWNER}/${REPO}/pulls?state=open&head=${OWNER}:${branch}&base=${merge_target}" \
  -H "Authorization: token ${TOKEN}"
```

已存在时：
```
ℹ️ PR 已存在：${GITEA_URL}/${OWNER}/${REPO}/pulls/<number>
   标题：<existing_title>
   状态：Open
```

成功创建后：
```
✅ PR 已创建！

  🔗 ${GITEA_URL}/${OWNER}/${REPO}/pulls/<number>
  📋 标题：feat(REQ-001): 用户积分规则管理
  🎯 合并方向：feat/REQ-001-user-points → main

💡 后续操作：
- /req:review-pr review   AI 代码审查
- /req:review-pr merge    审查通过后合并 PR
- /req:done               归档需求
```

然后进入「步骤 8. 分支清理提示」。

---

#### repoType = "github"

使用 `gh` CLI 创建 PR。

**检查 gh CLI**：
```bash
command -v gh &>/dev/null
```

可用时直接执行：
```bash
gh pr create \
  --title "<pr_title>" \
  --body "<pr_body>" \
  --base "<merge_target>"
```

不可用时提示命令：
```
🔀 请手动创建 PR：

  gh pr create --title "feat(REQ-001): 用户积分规则管理" --base main

  或在浏览器中打开：
  https://github.com/<owner>/<repo>/compare/<merge_target>...<branch>
```

---

#### repoType = "other"

不创建 PR，仅展示合并信息：

```
🔀 分支已推送到远程

  分支：<branch>
  合并目标：<merge_target>

  合并命令：
  git checkout <merge_target> && git merge <branch>

💡 请在对应平台手动创建 PR/MR
```

---

### 7. Git Flow 双目标

当策略为 `git-flow` 且分支是 hotfix 时，需要创建两个 PR：

1. hotfix → main（生产发布）
2. hotfix → develop（开发同步）

Gitea 会创建两个 PR，GitHub 会执行两次 `gh pr create`，other 展示两组命令。

```
📋 Git Flow Hotfix 需创建 2 个 PR：

  1/2 hotfix/fix-order-calc → main
  ✅ PR #42 已创建

  2/2 hotfix/fix-order-calc → develop
  ✅ PR #43 已创建
```

---

### 8. 分支清理提示

PR 创建成功后，读取 `branchStrategy.deleteBranchAfterMerge` 配置（默认 `true`）。

**配置为 true 或未配置时**：

```
🗑️ PR 创建后，是否切回主分支并删除本地开发分支？

  将执行：
  git checkout <merge_target>
  git branch -d <branch>
```

等待用户确认：
- 确认 → 执行切换和删除
- 拒绝 → 保留分支，仅提示后续手动清理命令

**配置为 false 时**：不提示，保留分支。

**注意事项**：
- 使用 `git branch -d`（小写 d），未合并的分支会被 Git 拒绝，防止误删
- 远程分支不删除（PR 合并后平台会自动清理，或在平台设置中配置自动删除）
- 如果当前就在目标分支上（如 main），跳过 checkout 步骤

---

## 未配置策略时的行为

未配置 `branchStrategy` 时，行为等同 `repoType: "other"`：

- 推送当前分支到远程
- 展示合并命令
- 提示 `/req:branch init` 配置策略以启用 PR 集成

```
⚠️ 未配置分支策略，仅推送分支

  💡 执行 /req:branch init 配置仓库类型，可自动创建 PR
```

---

## 用户输入

$ARGUMENTS
