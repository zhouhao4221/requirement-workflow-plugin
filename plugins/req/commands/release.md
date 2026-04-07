---
description: 颁布版本 - 合并 SQL、生成回滚、打 tag、创建 Release
---

# 颁布版本

将一组已完成需求打包成正式版本：合并 migration SQL、生成回滚脚本、调用 `/req:changelog`、打 git tag、根据仓库类型自动创建 Gitea/GitHub Release。

> 此命令**不受仓库角色限制**，readonly 仓库也可执行。
> 输出目录 `docs/migrations/released/`，不触发缓存同步。

## 命令格式

```
/req:release <version> [--from=<tag|commit>] [--to=<ref>] [--prerelease]
```

**参数说明：**
- `<version>`：**必填**，版本号（如 `v1.2.0`、`1.2.0`）
- `--from`：可选，起始点，默认上一个 git tag
- `--to`：可选，结束点，默认 HEAD
- `--prerelease`：可选，强制标记为预发布（仅用于在主分支上也想发布 RC 的场景）

**示例：**
- `/req:release v1.2.0`
- `/req:release v1.2.0 --from=v1.1.0`
- `/req:release v1.2.0-rc.1 --prerelease`

---

## 执行流程

### 1. 参数校验

```python
if not version:
    print("❌ 请指定版本号")
    print("用法：/req:release <version> [--from=<tag>] [--to=<ref>] [--prerelease]")
    exit()
```

### 1.5 分支策略判定（预发布 / 正式发布）

读取 `branchStrategy` 和当前分支，决定 release 类型：

```python
strategy = read_settings("branchStrategy", {})
current_branch = run("git branch --show-current")
main_branch = strategy.get("mainBranch", "main")
develop_branch = strategy.get("developBranch")
hotfix_prefix = strategy.get("hotfixPrefix", "hotfix/")
```

**判定规则**：

| 当前分支 | Release 类型 | prerelease 标记 |
|---------|-------------|----------------|
| `mainBranch`（如 main/master） | 正式发布 | `false` |
| `developBranch`（如 develop） | 预发布 | `true` |
| `release/*` | 预发布 | `true` |
| `<hotfixPrefix>*`（如 hotfix/*） | 预发布 | `true` |
| 其他功能分支（feat/*、fix/* 等） | **禁止发布**，硬阻止 | — |

```python
if current_branch == main_branch:
    is_prerelease = False
elif current_branch == develop_branch \
     or current_branch.startswith("release/") \
     or current_branch.startswith(hotfix_prefix):
    is_prerelease = True
else:
    print(f"❌ 当前分支 {current_branch} 不允许发布版本")
    print(f"   允许的分支：{main_branch}、{develop_branch or '(未配置)'}、release/*、{hotfix_prefix}*")
    print(f"   请先切换到合适的分支再执行 /req:release")
    exit()

# --prerelease 参数可强制覆盖：仅允许从「正式」改为「预发布」
if args.prerelease:
    is_prerelease = True
# 不提供反向覆盖（--release）—— 非主分支禁止创建正式发布是硬规则
```

**未配置 `branchStrategy`** 时：默认按当前分支为 main 处理，正式发布。`--prerelease` 仍可强制改为预发布。

显示判定结果（在交互选择前）：

```
📌 当前分支：develop
📌 分支策略：git-flow
🏷️  Release 类型：预发布（pre-release）
```

### 2. 确定 Git 范围

复用 `/req:changelog` 的范围逻辑：

```bash
TO_REF=${to:-HEAD}

if [ -z "$FROM_REF" ]; then
    FROM_REF=$(git describe --tags --abbrev=0 $TO_REF^ 2>/dev/null)
fi

if [ -z "$FROM_REF" ]; then
    FROM_REF=$(git rev-list --max-parents=0 HEAD)
    echo "⚠️ 未找到 git tag，将从仓库首次提交开始"
fi

echo "📌 版本范围：$FROM_REF..$TO_REF"
```

### 3. 自动推算候选需求

```bash
# 提取 commit message 中的需求编号
git log $FROM_REF..$TO_REF --pretty=format:"%s%n%b" --no-merges \
  | grep -oE "(REQ|QUICK)-[0-9]+" \
  | sort -u
```

读取每个候选需求的文档（`active/` + `completed/`，按角色选择本地或缓存路径），提取：
- 标题
- 类型（后端/前端/全栈）
- 当前状态
- 关联的 SQL 文件（见步骤 4）

### 4. 扫描 migration 文件

输入目录：`docs/migrations/`（不含 `released/` 子目录）

```bash
# 列出所有 .sql 文件，排除已发布目录
find docs/migrations -maxdepth 2 -name "*.sql" \
  ! -path "docs/migrations/released/*" 2>/dev/null
```

**关联规则**：文件名包含 `REQ-XXX` 或 `QUICK-XXX` 即归属对应需求。一个文件可属于多个需求（罕见，按出现顺序去重）。

### 5. 交互式选择

展示候选列表，等待用户选择：

```
📋 检测到 N 个候选需求（<from>..<to>）：

  [1] REQ-001 用户积分管理       已完成   📄 2 个 SQL
  [2] REQ-003 订单导出           已完成   📄 1 个 SQL
  [3] REQ-005 报表优化           测试中   ⚠️ 未完成  📄 1 个 SQL
  [4] QUICK-007 修复登录跳转     已完成   (无 SQL)

请选择要纳入 v1.2.0 的需求（如 1,2,4 或 all，回车取消）：
```

**规则**：
- 未完成的需求标 ⚠️ 提醒，但不禁止选择
- 用户输入 `all` 选全部，输入序号列表（逗号分隔）选部分
- 回车 / 空输入 → 取消整个发布
- 这是必须等待用户输入的场景，**不得**自动跳过

### 6. 合并 SQL

若所选需求中**至少一个**有 SQL 文件，则生成合并文件；否则跳到步骤 8。

**输出文件**：`docs/migrations/released/<version>.sql`

```sql
-- ============================================================
-- Release: <version>
-- Date:    YYYY-MM-DD
-- Range:   <from>..<to>
-- Includes:
--   REQ-001 用户积分管理 (后端)
--   REQ-003 订单导出 (后端)
-- ============================================================

-- ------------------------------------------------------------
-- REQ-001 用户积分管理
-- Source: docs/migrations/feat-REQ-001-add-points.sql
-- ------------------------------------------------------------
<原文件内容>

-- ------------------------------------------------------------
-- REQ-003 订单导出
-- Source: docs/migrations/feat-REQ-003-export.sql
-- ------------------------------------------------------------
<原文件内容>
```

**顺序**：按用户选择列表的顺序，同需求多 SQL 按文件名排序。

### 7. 生成回滚 SQL

**输出文件**：`docs/migrations/released/<version>.rollback.sql`

**自动推导规则**（按行扫描合并后的 SQL）：

| 正向语句 | 自动回滚 |
|---------|---------|
| `CREATE TABLE x (...)` | `DROP TABLE x;` |
| `CREATE TABLE IF NOT EXISTS x` | `DROP TABLE IF EXISTS x;` |
| `ALTER TABLE x ADD COLUMN y ...` | `ALTER TABLE x DROP COLUMN y;` |
| `ALTER TABLE x ADD INDEX i ...` | `ALTER TABLE x DROP INDEX i;` |
| `CREATE INDEX i ON x` | `DROP INDEX i;` |
| `CREATE UNIQUE INDEX i ON x` | `DROP INDEX i;` |
| `ALTER TABLE x RENAME TO y` | `ALTER TABLE y RENAME TO x;` |
| `INSERT INTO x ...` | `-- ⚠️ 需手动补充：INSERT 无法自动回滚` |
| `UPDATE x ...` | `-- ⚠️ 需手动补充：UPDATE 无法自动回滚` |
| `DELETE FROM x ...` | `-- ⚠️ 需手动补充：DELETE 无法自动回滚` |
| `DROP ...` | `-- ⚠️ 需手动补充：原 DROP 无法自动回滚` |
| 复杂 ALTER（MODIFY/CHANGE） | `-- ⚠️ 需手动补充：列定义变更需手动还原` |
| 其他无法识别 | `-- ⚠️ 需手动补充：<原语句首 80 字>` |

**生成格式**：

```sql
-- ============================================================
-- Rollback for: <version>
-- Date:         YYYY-MM-DD
-- ⚠️ 警告：标记为「需手动补充」的语句必须人工补全后才能执行
-- ============================================================

-- 倒序回滚（后建的先回滚）

-- REQ-003 订单导出
DROP TABLE IF EXISTS order_export_log;

-- REQ-001 用户积分管理
ALTER TABLE users DROP COLUMN points;
DROP TABLE IF EXISTS user_point_logs;
-- ⚠️ 需手动补充：INSERT INTO point_rules VALUES ...
```

**记录待补充的数量**，最终报告中提示。

### 8. 调用 `/req:changelog`

无论是否有 SQL，都自动生成版本说明：

```
将自动调用 /req:changelog <version> --from=<from> --to=<to>
```

**实现方式**：直接执行 changelog 命令的核心逻辑（读取 commit、分类、关联需求、写入 `docs/changelogs/<version>.md`），不要求用户重复输入。

若 `docs/changelogs/<version>.md` 已存在 → 通过 Hook 弹出确认对话框。

### 9. 创建 Git Tag

```bash
TAG_MESSAGE="Release <version>

Includes:
- REQ-001 用户积分管理
- REQ-003 订单导出

See docs/changelogs/<version>.md for full notes."

git tag -a <version> -m "$TAG_MESSAGE"
```

**通过 PreToolUse Hook** 自动弹出原生确认（已有 Bash 拦截机制覆盖 git 操作）。

**不自动 push**，最终报告中提示用户执行 `git push origin <version>`。

### 10. 创建 Gitea / GitHub Release

读取 `branchStrategy.repoType`：

```python
strategy = read_settings("branchStrategy", {})
repo_type = strategy.get("repoType", "other")
```

**release notes 内容**：取 `docs/changelogs/<version>.md` 的正文。

---

#### repoType = "gitea"

**解析远程仓库信息**：
```bash
REMOTE_URL=$(git remote get-url origin)
# SSH: git@git.example.com:owner/repo.git → owner, repo
# HTTPS: https://git.example.com/owner/repo.git → owner, repo
```

**Token 检查**：从 `branchStrategy.giteaToken` 读取，缺失时输出提示并跳过 Release 创建（tag 仍保留）。

**调用 API**：
```bash
curl -s -X POST "${GITEA_URL}/api/v1/repos/${OWNER}/${REPO}/releases" \
  -H "Authorization: token ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"tag_name\": \"<version>\",
    \"name\": \"<version>\",
    \"body\": \"<changelog 正文，需 JSON 转义>\",
    \"draft\": false,
    \"prerelease\": ${IS_PRERELEASE}
  }"
```

**已存在时**（HTTP 409 或查询命中）：提示 Release 已存在，输出链接，不重复创建。

**SQL 文件上传**（若生成了 SQL）：
```bash
# 上传 .sql 和 .rollback.sql 作为 release 资源
curl -s -X POST "${GITEA_URL}/api/v1/repos/${OWNER}/${REPO}/releases/${RELEASE_ID}/assets?name=<version>.sql" \
  -H "Authorization: token ${TOKEN}" \
  -F "attachment=@docs/migrations/released/<version>.sql"
```

---

#### repoType = "github"

**检查 gh CLI**：
```bash
command -v gh &>/dev/null
```

**可用时直接执行**：
```bash
gh release create <version> \
  --title "<version>" \
  --notes-file docs/changelogs/<version>.md \
  ${IS_PRERELEASE:+--prerelease} \
  docs/migrations/released/<version>.sql \
  docs/migrations/released/<version>.rollback.sql
```

（后两个文件参数仅在生成 SQL 时附加）

**不可用时**输出命令让用户手动执行。

---

#### repoType = "other" 或未配置

仅输出可手动执行的命令提示，不调用 API。

### 11. 输出最终报告

```
✅ 版本 <version> 已颁布！

═══════════════════════════════════════════════
🏷️  Release: <version>
═══════════════════════════════════════════════

📌 版本信息
├── 版本号：<version>
├── 类型：正式发布 / 预发布
├── 当前分支：<branch>
├── 发布日期：YYYY-MM-DD
├── 版本范围：<from>..<to>
└── 包含需求：N 个

📋 包含需求
├── REQ-001 用户积分管理 (后端)
├── REQ-003 订单导出 (后端)
└── QUICK-007 修复登录跳转 (全栈)

📄 SQL 脚本
├── docs/migrations/released/<version>.sql           (合并 X 个文件)
└── docs/migrations/released/<version>.rollback.sql  (自动 Y 条 / 待补 Z 条)

📝 版本说明
└── docs/changelogs/<version>.md

🏷️  Git Tag
└── <version> ✅ 已创建（未推送）

🚀 Release
└── <Gitea/GitHub Release URL 或 跳过原因>

═══════════════════════════════════════════════

💡 后续操作：
- 推送 tag：       git push origin <version>
- 检查回滚 SQL：   cat docs/migrations/released/<version>.rollback.sql
- 查看版本说明：   cat docs/changelogs/<version>.md
```

**若回滚 SQL 中存在「需手动补充」**：
```
⚠️ 回滚脚本中有 Z 条语句需手动补充，发布前请人工检查！
```

---

## 边界情况处理

| 场景 | 处理方式 |
|------|---------|
| 当前在功能分支（feat/* 等） | **硬阻止**，提示切换到允许的分支 |
| 在主分支但加 `--prerelease` | 标记为预发布 |
| 在 develop / release/* / hotfix/* | 自动标记为预发布 |
| 没有 git tag | 从首次提交开始，显示警告 |
| 范围内无 commit | 终止操作 |
| 范围内无候选需求 | 提示后询问是否继续（仅打 tag + changelog） |
| 用户未选择任何需求 | 取消整个发布 |
| 选中需求都无 SQL | 跳过 SQL 步骤，仅执行 changelog/tag/release |
| `docs/migrations/released/<version>.sql` 已存在 | Hook 弹确认 |
| `docs/changelogs/<version>.md` 已存在 | Hook 弹确认 |
| git tag 已存在 | 提示已存在，询问是否跳过 tag 步骤继续 |
| Gitea token 缺失 | 跳过 Release，保留 tag |
| gh CLI 缺失 | 输出命令让用户手动执行 |
| `repoType` 未配置 | 仅输出手动命令 |

## 用户输入

$ARGUMENTS
