---
description: Issue 工作流 - 创建/编辑/关闭/列表/查看/评论 issue
argument-hint: "<new|edit|close|reopen|list|show|comment> [参数...]"
allowed-tools: Read, Glob, Grep, Bash(git:*, gh:*, curl:*, python3:*, jq:*)
---

# Issue 工作流

统一管理 GitHub / Gitea issue 的全生命周期：创建、编辑、关闭、重开、列表、查看、评论讨论。

> 此命令**不受仓库角色限制**，readonly 也可执行。不触发缓存同步。

---

## 子命令路由

根据 `$ARGUMENTS` 的第一个 token 决定执行分支：

| 第一个参数 | 功能 | 跳转章节 |
|-----------|------|---------|
| `new` | 创建 issue | §3 |
| `edit` | 修改 issue 字段 | §4 |
| `close` | 关闭 issue（可附留言） | §5 |
| `reopen` | 重开 issue | §6 |
| `list` | 列出 issue | §7 |
| `show` | 查看 issue 详情和评论 | §8 |
| `comment` | 添加或列出评论 | §9 |
| 无 / `help` | 打印子命令摘要并终止 | — |

**解析规则**：
- issue 编号参数支持 `#42`、`42` 两种写法，自动去掉 `#`
- 未知子命令 → 打印摘要并退出
- 所有子命令都先执行 §1 前置检查 + §2 API 配置解析

---

## §1 前置检查（所有子命令共用）

### 1.1 读取 `branchStrategy`

```python
import json, os
path = ".claude/settings.local.json"
cfg = json.load(open(path)) if os.path.exists(path) else {}
bs = cfg.get("branchStrategy", {})
repo_type = bs.get("repoType", "other")
gitea_url = bs.get("giteaUrl")
gitea_token = bs.get("giteaToken")
```

### 1.2 按 repoType 校验依赖

| repoType | 前置要求 | 失败处理 |
|---------|---------|---------|
| `gitea` | `giteaUrl` + `giteaToken` 必须非空 | `❌ Gitea 未配置，请先执行 /req:branch init` 后终止 |
| `github` | `command -v gh` 可用 | `❌ 未找到 gh CLI：https://cli.github.com/` 后终止 |
| `other` / 未配置 | 无 | 仅 `list` / `show` 报 `❌ other 类型不支持 list/show`；写操作改为输出手动提交提示 |

### 1.3 OWNER/REPO 解析

```bash
REMOTE=$(git remote get-url origin)
# 支持 ssh://git@host:port/owner/repo.git、git@host:owner/repo.git、https://host/owner/repo.git
# 去掉 .git，取最后两段
```

解析规则详见 [_issue.md 的 OWNER/REPO 解析](./_issue.md#ownerrepo-解析)。

---

## §2 公共逻辑（所有子命令按需引用）

### 2.1 关联需求识别

写操作（`new` / `edit --body` / `close --comment` / `comment`）可自动在正文/评论末尾附需求上下文。

```python
import re
req_id = args.get("--req")
if not req_id:
    branch = git("branch --show-current")
    m = re.search(r"(REQ-\d+|QUICK-\d+)", branch)
    req_id = m.group(1) if m else None
```

命中后读需求文档（复用 [_storage.md 存储路径解析](./_storage.md#存储路径解析)），提取：元信息的「标题 / 类型 / 模块 / 状态」+「二、功能清单」首段作摘要。

### 2.2 标签匹配（fuzzy match live labels）

**禁止硬编码中英文对照表**。全部基于仓库真实 labels 做匹配：

```python
# 第 1 步：拉取真实 labels
# gitea:  GET /repos/{o}/{r}/labels?limit=50
# github: gh label list --limit 100 --json name,description
real_labels = [{"id":1,"name":"bug"},{"id":2,"name":"enhancement"},...]

# 第 2 步：对 --labels 中每项做匹配
def match(user_input, real):
    norm = lambda s: s.lower().replace(" ", "").replace("-", "").replace("_", "")
    # a) 完全匹配（忽略大小写）
    exact = [r for r in real if r["name"].lower() == user_input.lower()]
    if exact: return exact[:1]
    # b) 去空格/连字符/下划线后匹配
    fuzzy = [r for r in real if norm(r["name"]) == norm(user_input)]
    if fuzzy: return fuzzy[:1]
    # c) 子串包含
    sub = [r for r in real if norm(user_input) in norm(r["name"]) or norm(r["name"]) in norm(user_input)]
    return sub  # 可能多个，需让用户选
```

**用户传中文**（如 `--labels=紧急`）→ 仓库若有「紧急」或「urgent」之类 label，fuzzy 子串会命中；若全无命中 → 询问：

```
❓ 仓库未找到匹配标签 "紧急"，是否在仓库中创建该标签？(y/n)
```

`y` → Gitea `POST /labels` / `gh label create`；`n` → 跳过该标签。

### 2.3 指派人解析

**Gitea**：
```bash
curl -s "${GITEA_URL}/api/v1/repos/${OWNER}/${REPO}/collaborators?limit=50" \
  -H "Authorization: token ${TOKEN}"
```

`@me` 需先拿当前 login：
```bash
curl -s "${GITEA_URL}/api/v1/user" -H "Authorization: token ${TOKEN}" | jq -r .login
```

**GitHub**：`gh` 原生支持 `@me`，无需解析。

匹配策略同 §2.2（完全 → 前缀 → 子串），无匹配时**跳过该 assignee**，不终止。

### 2.4 JSON 转义

**禁止**直接字符串拼接 `-d '{"body":"..."}'`。含引号、换行、反斜杠的文本必须用 `python3` 转义：

```bash
BODY_JSON=$(printf '%s' "$BODY" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
PAYLOAD=$(python3 -c "import json; print(json.dumps({'title':'$TITLE','body':$BODY_JSON,'labels':$LABEL_IDS}))")
```

或用 `jq -Rs` 把 raw 文本编码成 JSON 字符串。

### 2.5 错误处理（统一表）

| HTTP / 错误 | 提示 |
|------------|------|
| 401 / 403 | `❌ 鉴权失败，请检查 giteaToken 或 gh auth status` |
| 404 | `❌ Issue #N 不存在（或仓库路径错误）` |
| 422 | 回显 API `message` 字段，标出具体哪个字段不合法 |
| 423（locked） | `❌ Issue #N 已锁定，无法评论/编辑` |
| curl 非 0 退出 | `❌ 请求失败：<stderr>，检查网络后重试` |

Gitea 响应判断：取 HTTP code 用 `curl -o /tmp/resp -w "%{http_code}"`。

### 2.6 `--auto` 模式

检测 `.claude/.req-auto` 且 mtime < 10 分钟 → 跳过预览 / 交互确认。

| 子命令 | 是否支持 `--auto` | 跳过项 |
|-------|------------------|-------|
| `new` | ❌ 不支持 | 创建必须预览 |
| `edit` | ✅ | 修改预览 |
| `close` | ✅ | 确认关闭、评论预览 |
| `comment` | ✅ | 评论预览 |
| `reopen` / `list` / `show` | — | 本就无交互 |

---

## §3 new — 创建 Issue

```
/req:issue new <标题> [--body=<正文>] [--labels=a,b] [--assignees=u1,u2] [--req=REQ-XXX]
```

### 3.1 解析参数

- 必填：标题（第二个参数之后的文本；若用户未提供 → 进入交互，要求输入）
- 可选：`--body` / `--labels` / `--assignees` / `--req`

### 3.2 拉取仓库 labels 和 collaborators

参照 §2.2、§2.3。

### 3.3 智能匹配字段

- `--labels` → §2.2 fuzzy match
- `--assignees` → §2.3 解析
- **推荐标签**：若步骤 §2.1 命中需求，把需求的「类型」（后端/前端/全栈）和「模块」加入**候选**（不强制），展示给用户勾选

### 3.4 生成正文草稿

**有 `--body`**：直接用。

**无 `--body`**：AI 生成模板（占位让用户后续可编辑）：

```markdown
## 问题描述

<根据标题展开的一句话>

## 复现步骤

1. 
2. 

## 预期行为

## 实际行为

## 环境信息

- 分支：<git branch --show-current>
- 提交：<git rev-parse --short HEAD>
```

**关联需求时追加**（用 `---` 分隔）：

```markdown

---
## 关联需求

- 编号：REQ-001
- 标题：用户积分规则管理
- 类型：后端
- 模块：积分
- 状态：开发中

**业务上下文**：
<需求文档功能清单首段>
```

**防误关闭检查**：若标题或正文含 `closes #\d+` / `fixes #\d+`，提醒：

```
⚠️ 正文中检测到 "closes #42"。此关键词会在 PR 合并时自动关闭 issue。
   若只想创建新 issue 不关联其他 issue，请去掉关键词。
   继续？(y/n)
```

### 3.5 预览并确认（`new` 强制预览，不受 `--auto` 影响）

```
📝 Issue 草稿：

  仓库：pipexerp/diciai (gitea)
  标题：登录超时后 token 未清除
  标签：bug, authentication
  指派：@haiqing
  关联：REQ-001 用户积分规则管理

  正文（前 10 行）：
  ─────────────────────────────────────
  ## 问题描述
  ...
  ─────────────────────────────────────

  是否提交？(y/n/e - 编辑某字段)
```

`e` → 询问要改哪个字段（1.标题 / 2.正文 / 3.标签 / 4.指派 / 5.关联），改完回预览。

### 3.6 调 API 提交

**gitea**：
```bash
PAYLOAD=$(python3 -c "import json; print(json.dumps({
  'title': '$TITLE',
  'body': $BODY_JSON,
  'labels': $LABEL_IDS,       # [1,2]
  'assignees': $ASSIGNEE_LOGINS  # ['user1']
}))")

curl -s -X POST "${GITEA_URL}/api/v1/repos/${OWNER}/${REPO}/issues" \
  -H "Authorization: token ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD"
```

响应 201 → 提取 `number` 和 `html_url`。

**github**：
```bash
gh issue create \
  --title "$TITLE" \
  --body "$BODY" \
  $(for l in "${LABELS[@]}"; do echo -n "--label \"$l\" "; done) \
  $(for a in "${ASSIGNEES[@]}"; do echo -n "--assignee \"$a\" "; done)
```

`gh` 成功后直接返回 URL。

**other**：输出 Markdown 让用户手动粘贴：
```
ℹ️ repoType=other，请手动创建：
标题：<T>
正文：<B>
```

### 3.7 成功输出

```
✅ Issue 已创建

  🔗 https://git.example.com/pipexerp/diciai/issues/170
  #170 登录超时后 token 未清除
  🏷️  bug, authentication
  👤 @haiqing
  📎 关联：REQ-001

💡 后续操作：
  /req:fix --from-issue=#170         修复此 issue
  /req:new --from-issue=#170          创建正式需求
  /req:new-quick --from-issue=#170   创建快速修复
  /req:issue comment 170 <文本>      添加评论
```

---

## §4 edit — 修改 Issue 字段

```
/req:issue edit #N [--title=] [--body=] [--add-labels=] [--remove-labels=] [--assignees=]
```

### 4.1 无参数时展示现状

仅传 `edit #N` 不带任何字段 → 拉 issue 现状 + 提示可用字段，不修改：

```
ℹ️ Issue #42 当前状态：
  标题：登录超时 token 未清除
  状态：open
  标签：bug, 紧急
  指派：@haiqing

💡 可用字段：--title --body --add-labels --remove-labels --assignees
```

### 4.2 有字段时处理

按 §2.2、§2.3 解析 labels 和 assignees。

### 4.3 预览变更

```
📝 修改预览 #42：

  标题：登录超时 token 未清除
     → [新] 登录超时 token 未清除（已确认前端也受影响）
  标签：+authentication, -紧急
  指派：@haiqing, @alice

  是否提交？(y/n)
```

`--auto` → 跳过，直接提交。

### 4.4 调 API

**gitea**（**关键：labels 走独立端点，不在 PATCH body**）：

```bash
# 标题 / 正文 / 指派 / 状态 → PATCH
PAYLOAD=$(python3 -c "import json; print(json.dumps({
  'title': '$NEW_TITLE',
  'body': $NEW_BODY_JSON,
  'assignees': $ASSIGNEES
}))")

curl -s -X PATCH "${GITEA_URL}/api/v1/repos/${OWNER}/${REPO}/issues/${N}" \
  -H "Authorization: token ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD"

# 新增标签
curl -s -X POST "${GITEA_URL}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/labels" \
  -H "Authorization: token ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"labels\":[$ADD_IDS]}"

# 移除标签（每个单独 DELETE）
for ID in "${REMOVE_IDS[@]}"; do
  curl -s -X DELETE "${GITEA_URL}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/labels/${ID}" \
    -H "Authorization: token ${TOKEN}"
done
```

**github**（一条搞定）：
```bash
gh issue edit "$N" \
  --title "$NEW_TITLE" \
  --body "$NEW_BODY" \
  $(for l in "${ADD[@]}"; do echo -n "--add-label \"$l\" "; done) \
  $(for l in "${REMOVE[@]}"; do echo -n "--remove-label \"$l\" "; done) \
  $(for a in "${ADD_ASN[@]}"; do echo -n "--add-assignee \"$a\" "; done)
```

### 4.5 成功输出

```
✅ Issue #42 已更新

  修改：标题、+authentication、-紧急、+@alice
  🔗 <url>
```

---

## §5 close — 关闭 Issue

```
/req:issue close #N [--comment=<告别留言>] [--reason=completed|not_planned]
```

### 5.1 预览

```
🔒 将关闭 Issue #42 登录超时 token 未清除
   留言：修复已合并至 main（PR #158）
   原因：completed

  确认？(y/n)
```

`--auto` → 跳过。

### 5.2 执行（gitea：两步，评论在前）

```bash
# 第 1 步：有 --comment 时先发评论
if [ -n "$COMMENT" ]; then
  COMMENT_JSON=$(printf '%s' "$COMMENT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
  curl -s -X POST "${GITEA_URL}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/comments" \
    -H "Authorization: token ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"body\": $COMMENT_JSON}"
fi

# 第 2 步：改状态
curl -s -X PATCH "${GITEA_URL}/api/v1/repos/${OWNER}/${REPO}/issues/${N}" \
  -H "Authorization: token ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"state":"closed"}'
```

> **顺序原因**：评论失败不影响关闭，关闭失败时评论也已留痕用户可人工处理。

> **`--reason` 在 Gitea 静默降级**：Gitea API 的 `state` 字段只接受 `open` / `closed`，不支持 `completed` / `not_planned`。首次遇到 `--reason` 时打印一行提示：
> ```
> ℹ️ Gitea 不支持 --reason，已忽略（GitHub 专属字段）
> ```

### 5.3 执行（github：一条搞定）

```bash
gh issue close "$N" \
  ${COMMENT:+--comment "$COMMENT"} \
  ${REASON:+--reason "$REASON"}
```

### 5.4 成功输出

```
✅ Issue #42 已关闭
   💬 留言：修复已合并至 main（PR #158）
   🔗 <url>
```

---

## §6 reopen — 重开 Issue

```
/req:issue reopen #N
```

无参数，无预览（反正就一步）。

**gitea**：`PATCH /issues/{n} {"state":"open"}`

**github**：`gh issue reopen "$N"`

成功：
```
✅ Issue #42 已重开
   🔗 <url>
```

---

## §7 list — 列出 Issue

```
/req:issue list [--state=open|closed|all] [--labels=a,b] [--assignee=@me|user] [--limit=20] [--page=1]
```

默认：`--state=open --limit=20 --page=1`。

### 7.1 拉取数据

**gitea**：
```bash
curl -s "${GITEA_URL}/api/v1/repos/${OWNER}/${REPO}/issues?type=issues&state=${STATE}&labels=${LABELS}&page=${PAGE}&limit=${LIMIT}" \
  -H "Authorization: token ${TOKEN}"
```

- `type=issues` 排除 PR
- `@me` 需先 `GET /user` 解析（§2.3），再传 `assigned_by=<login>` 或 `created_by=<login>`
- `limit` 上限 50，超出自动截到 50
- **客户端二次过滤**：响应里过滤 `pull_request != null` 的条目（某些 Gitea 版本 `type=issues` 未完全生效）

**github**：
```bash
gh issue list \
  --state "$STATE" \
  ${LABELS:+--label "$LABELS"} \
  ${ASSIGNEE:+--assignee "$ASSIGNEE"} \
  --limit "$LIMIT" \
  --json number,title,state,labels,assignees,updatedAt
```

`gh` 原生支持 `@me` 且自动过滤 PR。

### 7.2 输出表格

```
📋 Open issues @pipexerp/diciai (第 1 页 / 20 条)

  #   状态   标题                                      标签            指派      更新
  ──────────────────────────────────────────────────────────────────────────────
  170 open   登录超时后 token 未清除                   bug             @haiqing  2h
  165 open   导出 Excel 中文乱码                       bug, 紧急       -          1d
  158 open   积分排行榜排序异常                        enhancement     @alice    3d
  ...

💡 下一页：/req:issue list --page=2
💡 查看详情：/req:issue show #170
```

标题超 40 字符截断加 `…`。时间用相对格式（`2h` / `1d` / `3w`）。

---

## §8 show — 查看 Issue 详情和评论

```
/req:issue show #N
```

### 8.1 拉取数据

**gitea**：
```bash
# issue 主体
curl -s "${GITEA_URL}/api/v1/repos/${OWNER}/${REPO}/issues/${N}" \
  -H "Authorization: token ${TOKEN}"

# 所有评论
curl -s "${GITEA_URL}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/comments" \
  -H "Authorization: token ${TOKEN}"
```

**github**：
```bash
gh issue view "$N" --comments --json number,title,state,body,author,labels,assignees,createdAt,comments
```

### 8.2 渲染格式（参考 `review-pr.md` 评论渲染风格）

```
📌 Issue #170 登录超时后 token 未清除

  状态：open
  作者：@haiqing（2026-04-15 14:32）
  标签：bug, authentication
  指派：@haiqing, @alice
  关联分支：fix/login-token-not-cleared-i170

─── 正文 ─────────────────────────────────────

## 问题描述
...（issue body 全文）

─── 💬 评论（共 3 条）──────────────────────────

[1] @alice（2026-04-15 15:01）
    我能复现，在 Chrome 125 上。

[2] @haiqing（2026-04-15 16:22）
    已定位到 src/interceptors/request.ts:45
    > 响应拦截器捕获 401 时未清 token

[3] @alice（2026-04-16 09:10）
    PR #158 已修复，请 review。

💡 /req:issue comment 170 <文本>     添加评论
💡 /req:issue close 170              关闭此 issue
```

---

## §9 comment — 添加或列出评论

```
/req:issue comment #N <评论文本>
/req:issue comment #N --list
```

### 9.1 `--list` 模式

仅渲染评论列表（即 §8.2 的「💬 评论」部分），不显示 issue 主体：

```bash
# gitea
curl -s "${GITEA_URL}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/comments" \
  -H "Authorization: token ${TOKEN}"

# github
gh issue view "$N" --comments --json comments
```

### 9.2 add 模式（默认）

**参数校验**：评论文本必填且非空。

**关联需求**（可选）：若命令带 `--req` 或当前分支含 REQ-XXX → 评论末尾附：
```

---
💬 来自 REQ-001 用户积分规则管理
```

**预览**（`--auto` 跳过）：
```
💬 添加评论到 Issue #170：

  ─────────────────────────────────────
  已定位到 src/interceptors/request.ts:45
  > 响应拦截器捕获 401 时未清 token
  
  ---
  💬 来自 REQ-001 用户积分规则管理
  ─────────────────────────────────────

  确认提交？(y/n)
```

**gitea**：
```bash
BODY_JSON=$(printf '%s' "$BODY" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
curl -s -X POST "${GITEA_URL}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/comments" \
  -H "Authorization: token ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"body\": $BODY_JSON}"
```

**github**：
```bash
gh issue comment "$N" --body "$BODY"
```

### 9.3 成功输出

```
✅ 评论已添加到 Issue #170
   💬 已定位到 src/interceptors/request.ts:45...
   🔗 <comment_url>
```

---

## 与其他 issue 相关命令的分工

| 场景 | 命令 | 说明 |
|------|------|------|
| **本命令覆盖** | `/req:issue *` | 完整生命周期 |
| 从 issue 派生需求 | `/req:new --from-issue=#N` | 读 issue → 需求文档 |
| 从 issue 派生修复 | `/req:fix --from-issue=#N` | 读 issue → 修复分支 |
| 从 issue 派生任务 | `/req:do --from-issue=#N` | 读 issue → 智能开发 |
| 需求完成时关闭 issue | `/req:done` / `/req:fix` 结束询问 | 与需求流绑定 |
| commit message 自动关联 | 在 message 末尾加 `closes #N` | PR 合并时自动关闭 |

---

## 用户输入

$ARGUMENTS
