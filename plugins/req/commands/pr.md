---
description: 创建 PR - 根据仓库类型自动创建 Pull Request
argument-hint: "[REQ-XXX]"
allowed-tools: Read, Glob, Grep, Bash(git:*, gh:*, curl:*)
---

# 创建 Pull Request

根据分支策略中的仓库类型，自动推送分支并创建 PR。

> 不受仓库角色限制，readonly 也可执行。不触发缓存同步。

## 命令格式

```
/req:pr [REQ-XXX] [--title=自定义标题] [--base=目标分支]
```

- 省略编号时根据当前分支名匹配需求
- `--title`、`--base` 覆盖自动值

---

## 执行流程

### 1. 识别需求和分支

- 指定编号 → 读取该需求的 `branch` 字段
- 未指定 → `git branch --show-current`，从分支名提取 `REQ-XXX` / `QUICK-XXX`
- 两者都失败 → 提示 `请指定需求编号：/req:pr REQ-XXX` 退出

### 2. 前置检查

`git status --porcelain` 有未提交改动时，自动串联执行 `/req:commit` 流程（分支检查 + 生成提交信息 + 提交），成功后继续。

### 3. 读取策略配置

读取 `.claude/settings.local.json.branchStrategy`：
- `repoType`（缺省 `other`）
- `mergeTarget`（缺省 `main`，被 `--base` 覆盖）
- `giteaUrl`、`giteaToken`（仅 gitea 需要）
- `deleteBranchAfterMerge`（缺省 `true`）

无 `branchStrategy` → 按 `other` 处理。

### 4. 生成 PR 标题和 Body

**标题**（`--title` 覆盖）：
- REQ-XXX → `feat(REQ-XXX): <标题>`
- QUICK-XXX → `fix(QUICK-XXX): <标题>`
- hotfix 分支 → `hotfix: <描述>`

**Body**（Markdown）：
```
## 需求
- 编号 / 标题 / 状态（从需求文档 YAML 元信息读取）

## 功能清单
（从需求文档「二、功能清单」提取）

## 变更文件
（从「十一、实现方案.文件改动清单」提取；无则跳过）
```

### 5. 推送分支

```bash
git push -u origin <branch>
```

### 6. 按 repoType 创建 PR

#### gitea

1. 解析 `git remote get-url origin` 得到 `OWNER/REPO`（SSH/HTTPS 均支持）
2. `giteaToken` 缺失 → 提示配置方式，给出手动 compare 链接退出
3. 先查是否已有 PR：
   ```bash
   curl -s "${giteaUrl}/api/v1/repos/${OWNER}/${REPO}/pulls?state=open&head=${OWNER}:<branch>&base=<target>" \
     -H "Authorization: token ${giteaToken}"
   ```
   有 → 输出现有 PR 链接，跳到步骤 8
4. 无 → 调 `POST /api/v1/repos/${OWNER}/${REPO}/pulls`，参数 `title/body/head/base`

成功输出：
```
✅ PR 已创建
   🔗 <url>
💡 /req:review-pr review / merge，或 /req:done 归档
```

#### github

检查 `command -v gh`。可用 → `gh pr create --title "..." --body "..." --base <target>`。不可用 → 提示命令 + 浏览器 compare 链接。

#### other

不创建 PR，输出：
```
分支已推送：<branch> → <target>
合并命令：git checkout <target> && git merge <branch>
```

### 7. Git Flow hotfix 双目标

`model == "git-flow"` 且分支以 `hotfix/` 开头 → 按步骤 6 对 `main` 和 `develop` 各创建一次，输出两个 PR 链接 / 两组命令。

### 8. 分支清理提示

`deleteBranchAfterMerge != false` 时询问：
```
是否切回 <target> 并删除本地分支 <branch>？
```
确认 → `git checkout <target> && git branch -d <branch>`（小写 `-d`，未合并会被拒绝）。当前已在目标分支则跳过 `checkout`。远程分支不删。

---

## 用户输入

$ARGUMENTS
