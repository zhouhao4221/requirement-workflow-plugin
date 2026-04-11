---
description: 颁布版本 - 合并 SQL、生成回滚、打 tag、创建 Release
---

# 颁布版本

将一组已完成需求打包成正式版本：合并 migration SQL、生成回滚脚本、调用 `/req:changelog`、打 git tag、根据仓库类型自动创建 Gitea/GitHub Release。

> 此命令**不受仓库角色限制**，readonly 仓库也可执行。
> 输出目录 `docs/migrations/released/`，不触发缓存同步。

## 命令格式

```
/req:release <version> [--from=<tag|commit>] [--to=<ref>] [--prerelease] [--no-draft] [--main=<branch>]
```

**参数说明：**
- `<version>`：**必填**，版本号（如 `v1.2.0`、`1.2.0`）
- `--from`：可选，起始点，默认上一个 git tag
- `--to`：可选，结束点，默认 HEAD
- `--prerelease`：可选，强制标记为预发布（仅用于在主分支上也想发布 RC 的场景）
- `--no-draft`：可选，**跳过 draft 阶段直接正式发布**。默认行为是创建 draft release（见下面"默认行为说明"），加此参数可切换到"立即发布"流程：本地创建 annotated tag + push，然后调用平台 Release API 创建正式 release。适用于 hotfix、可信任的自动化流水线、或 `repoType == other` 的场景
- `--main=<branch>`：可选，临时覆盖主分支名（优先级高于 `branchStrategy.mainBranch`），用于 tag 目标和跨分支流程的合并目标

**默认行为说明：draft 是默认模式**

从 v2 开始，`/req:release` **默认创建 Gitea / GitHub draft release**——不创建本地 git tag、不 push tag，tag 由平台在你手工 publish 时创建（lightweight，指向 draft 记录的 SHA）。这样设计的原因：
- 发布的大部分步骤不可逆（commit、push、tag、平台 Release），人工 gate 让你最后有机会检查 release notes / 资产文件 / 版本范围
- 与 git-flow cross-branch 流程天然配合——一次 PR gate（merge 到主分支）+ 一次 draft gate（平台 publish），两道闸门都过了才真正对外发版
- 意外情况下"放弃发布"很便宜：删 draft 就行，不留 git tag 和外部可见的 release

**不想 draft 就加 `--no-draft`**。

**示例：**
- `/req:release v1.2.0`（默认创建 draft，命令跑完后需在 Gitea/GitHub 手工 publish）
- `/req:release v1.2.0 --no-draft`（跳过 draft 直接正式发布）
- `/req:release v1.2.0 --from=v1.1.0`（默认 draft）
- `/req:release v1.2.0-rc.1 --prerelease --no-draft`（预发布 + 立即发布，常用于 CI 触发的 RC）
- `/req:release v1.2.0 --main=master`（临时覆盖主分支，默认 draft）

---

## 起步分支速查表

在正确的分支上运行 `/req:release` 可避免不必要的 PR 绕路：

| 分支策略 | 推荐起步分支 | 原因 |
|---------|-------------|------|
| `git-flow` | `developBranch`（通常是 develop） | 主分支通常有保护规则禁止直推；develop 起步会走 cross-branch PR 流程，在一个 PR 里带齐 changelog + SQL + 回滚 |
| `github-flow` | `mainBranch`（通常是 main） | main 即开发主干，direct 模式一把过 |
| `trunk-based` | `mainBranch` | 同上 |
| 发布候选 | `release/*` | 自动标记为预发布 |

若在 git-flow 的主分支上运行本命令，step 1.5 的守门规则会提醒切换到 develop，避免 `chore(release): prepare` 提交被保护分支打回后手动绕路。

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
main_branch = args.main or strategy.get("mainBranch", "main")  # --main 参数优先
```

**判定规则**：

| 当前分支 | 流程模式 | Release 类型 |
|---------|---------|-------------|
| `mainBranch`（如 main/master） | **直接发布** | 正式发布（`prerelease=false`） |
| `release/*` | **直接发布** | 预发布（`prerelease=true`） |
| `developBranch`（如 develop） | **跨分支流程**（合 SQL → PR → 合并后在主分支发预发布） | 预发布（`prerelease=true`，避免触发 CD） |
| 其他所有分支（feat/*、fix/*、hotfix/* 等） | **禁止**，硬阻止 | — |

> 说明：
> - 「主分支」由 `branchStrategy.mainBranch` 决定（默认 `main`）
> - 「开发分支」由 `branchStrategy.developBranch` 决定（默认 `develop`）
> - develop 上发布采用「跨分支流程」：不在 develop 上打 tag，最终 tag 创建在主分支
> - hotfix 必须先合回主分支再执行 release

```python
develop_branch = strategy.get("developBranch", "develop")

if current_branch == main_branch:
    flow_mode = "direct"
    is_prerelease = False
elif current_branch.startswith("release/"):
    flow_mode = "direct"
    is_prerelease = True
elif current_branch == develop_branch:
    flow_mode = "cross-branch"
    is_prerelease = True  # 从 develop 发起的流程统一走预发布，避免误触发 CD
else:
    print(f"❌ 当前分支 {current_branch} 不允许发布版本")
    print(f"   允许的分支：{main_branch}（正式）、release/*（预发布）、{develop_branch}（跨分支预发布）")
    exit()

# git-flow 保护分支守门：避免在受保护的主分支上起步 direct 模式
if (
    flow_mode == "direct"
    and current_branch == main_branch
    and strategy.get("model") == "git-flow"
):
    print(f"⚠️  检测到 git-flow 模式下当前在主分支 {main_branch}")
    print(f"    git-flow 的主分支通常设有保护规则，step 8.8 的 `chore(release): prepare` 提交会被直接 push 拒绝，")
    print(f"    你将被迫手动 reset → 切 develop → cherry-pick → 新 PR → 等合并 → 回主分支 → tag，绕一大圈。")
    print()
    print(f"    推荐做法：切到 {develop_branch} 重新运行 /req:release，走 cross-branch 流程一次性通过 PR 完成")
    print(f"    （一个 PR 带齐 changelog + SQL + 回滚，合并后自动 tag 主分支）。")
    print()
    print("请选择：")
    print(f"  [1] 切到 {develop_branch} 并中止本次运行（推荐，你需要重新执行命令）")
    print(f"  [2] 继续在 {main_branch} 直接发布（仅当主分支无保护或你确信可直推时选择）")
    print("  [3] 中止")
    choice = input("> ").strip()
    if choice == "1":
        run(f"git checkout {develop_branch}")
        print(f"✅ 已切到 {develop_branch}，请重新运行 /req:release {version}")
        exit()
    elif choice != "2":
        print("已中止")
        exit()
    # choice == "2"：用户确认继续，按 direct 流程往下走

# --prerelease 参数可强制覆盖：仅允许从「正式」改为「预发布」
if args.prerelease:
    is_prerelease = True
# 不提供反向覆盖（--release）—— 非主分支禁止创建正式发布是硬规则

# draft 模式（默认开启）：创建平台草稿 release，tag 由平台在用户手工 publish 时创建 lightweight tag
# 用 --no-draft 显式关闭；老的 --draft 作为冗余别名接受但无效果（向前兼容文档示例）
is_draft = not bool(args.no_draft)

# draft 模式依赖平台 API（Gitea/GitHub）；repoType=other 无 draft 概念，自动降级
repo_type = strategy.get("repoType", "other")
if is_draft and repo_type == "other":
    print("⚠️  repoType=other 不支持 draft release，自动降级为 --no-draft 模式")
    print("   本次发布将创建本地 annotated tag 并 push，但不调用任何平台 Release API")
    print("   （step 10 的 other 分支会输出手工命令提示）")
    print("   若想使用 draft 模式：请先 /req:branch init 把 repoType 配为 gitea 或 github")
    is_draft = False
```

**未配置 `branchStrategy`** 时：`mainBranch` 默认为 `main`，按上述规则判定。`--prerelease` 仍可强制改为预发布。

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

### 5.5 产物预览与最终确认

用户在 step 5 选完需求后，**不要立即执行 step 6+**。先根据当前所有决定参数（`flow_mode`、`is_draft`、`is_prerelease`、`repo_type`、选中需求是否带 SQL）计算并打印出**本次发布将产出的所有物料清单**，等待用户最后确认一次 y/n。

**为什么要这一步**：发布的大部分动作都不可逆（提交、push、tag、平台 Release）。用户必须在实际执行前看清所有将要发生的事——尤其是在 `--draft`、`--prerelease`、`cross-branch` 这些会改变最终行为的条件下，用户的心智模型和命令默认行为常常不一致。明确的预览消除"以为会 X，实际做了 Y"的事故。

**计算输入**：
- `selected_reqs`：step 5 用户选中的需求（可能为空，此时允许继续"纯 commit 分类 changelog"流程）
- `has_sql`：`selected_reqs` 里是否至少一个带 SQL 文件
- `sql_source_count`：待合并的源 SQL 文件数量（来自 step 4 扫描结果）
- `flow_mode`：`direct` / `cross-branch`（step 1.5 已确定）
- `is_draft`、`is_prerelease`：step 1.5 已确定
- `repo_type`、`main_branch`、`develop_branch`：step 1.5 已确定

**输出模板**（条件分支必须动态渲染，不要把所有分支都打出来）：

```
═══════════════════════════════════════════════
📋 本次发布将产出（<version>）
═══════════════════════════════════════════════

🎯 模式
├── flow_mode:   <direct | cross-branch>
├── prerelease:  <true | false>
├── draft:       <true | false>
└── repo_type:   <gitea | github | other>

📝 文档产物
└── ✅ docs/changelogs/<version>.md

🗃️  SQL 产物
<若 has_sql>
├── ✅ docs/migrations/released/<version>.sql           (合并 <sql_source_count> 个源文件)
├── ✅ docs/migrations/released/<version>.rollback.sql  (自动 <Y> 条 / 待补 <Z> 条)
└── ✅ 删除 <sql_source_count> 个源 SQL 文件（git rm）
<否则>
└── ❌ 无（本次选中的需求无 migration 文件）

📦 Git 提交
<若 flow_mode == direct>
└── ✅ chore(release): prepare <version>  →  当前分支 <current_branch>
<若 flow_mode == cross-branch>
└── ✅ chore(release): prepare <version>  →  <develop_branch>（然后 push）

🔀 分支操作
<若 flow_mode == direct>
└── ❌ 无跨分支操作（direct 模式）
<若 flow_mode == cross-branch>
├── ✅ git push origin <develop_branch>
├── ✅ 创建 PR: <develop_branch> → <main_branch>  (通过 <repo_type> API / gh CLI)
├── ⏸️  等待你确认 PR 合并完成  ← 阻塞点
└── ✅ git checkout <main_branch> && git pull --ff-only

🏷️  Git Tag
<若 is_draft == false>
├── ✅ git tag -a <version>  (annotated，本地创建)
└── ✅ git push origin <version>  →  推到 <repo_type>
<若 is_draft == true>
└── ❌ 不创建本地 tag（draft release 将由平台在你手工 publish 时创建 lightweight tag 指向当前 SHA）

🚀 平台 Release
<若 is_draft == false>
└── ✅ <repo_type> Release <version>
       ├── prerelease: <is_prerelease>
       ├── target:     <tag_target>
       └── 状态:        正式发布（对外可见<若 is_prerelease == true>，标记为预发布</若>）
<若 is_draft == true>
└── ✅ <repo_type> **Draft** Release <version>
       ├── prerelease:        <is_prerelease>
       ├── target_commitish:  <SHA 前 8 位>（draft 阶段绑定 SHA）
       ├── 状态:               草稿（仅作者/管理员可见）
       └── ⚠️  需手工在平台点 Publish 才真正发布
                publish 后平台会在 target SHA 上创建 lightweight tag

═══════════════════════════════════════════════

确认以上所有产物符合预期？
  [y] 继续执行 step 6+
  [n] 或其他 → 中止发布（已选需求不保留，下次重新选）
>
```

**用户回 y** → 进入 step 6；**其他回复** → 打印"已中止"并退出，不执行任何 step 6+ 操作。

**这是强制交互点，必须等待用户输入，不得自动跳过。**

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

### 6.5 删除已合并的原始 SQL 文件

**⚠️ 必须在步骤 6 写入成功后立即执行，不可跳过。**

对本次纳入合并的每个源 SQL 文件执行删除：

```bash
# 对每个已合并的源文件执行（记录在步骤 4 扫描结果中、且被步骤 5 用户选中的文件）
for sql_file in <merged_sql_files>; do
    git rm "$sql_file"
done
# 若文件未被 git 跟踪则用 rm
```

规则：
- 仅删除**被选中并成功合并**的文件，未选中需求的 SQL 保留
- 使用 `git rm` 将删除放入暂存区（不单独 commit，在步骤 8.5.1 或 8.8 统一提交）
- 若 `released/<version>.sql` 写入失败则**不得**执行本步骤
- 删除操作通过 Hook 会弹出 Bash 确认对话框

最终报告步骤 11 的「SQL 脚本」区块追加一行：`└── 已清理 X 个源 SQL 文件`。

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

### 8.5 跨分支流程（仅 `flow_mode == "cross-branch"`）

当在 `developBranch` 上执行 release 时，不在 develop 上打 tag，而是通过 PR 把产物合并到主分支，再在主分支上完成 tag 和 Release。

**流程**：

1. **提交产物到 develop**（包含合并 SQL、回滚 SQL、changelog，以及步骤 6 中 `git rm` 删除的原始 SQL）
   ```bash
   git add docs/migrations/released/<version>.sql \
           docs/migrations/released/<version>.rollback.sql \
           docs/changelogs/<version>.md
   # 步骤 6 的 git rm 已将删除放入暂存区，无需再 add
   git commit -m "chore(release): prepare <version>"
   git push origin <develop_branch>
   ```
   （若部分文件不存在则跳过添加）

2. **创建 PR：develop → main**

   **⚠️ 复用 PR 前必须检查状态**：

   ```bash
   # Gitea 示例：查询 develop→main 的 PR，必须过滤 state=open
   curl -s "${GITEA_URL}/api/v1/repos/${OWNER}/${REPO}/pulls?state=open&head=${OWNER}:${develop_branch}&base=${main_branch}" \
     -H "Authorization: token ${TOKEN}"
   ```

   判定规则：
   - 查询结果中有 `state == "open"` 的 PR → 复用（确认 head 指向最新 develop commit）
   - 查询结果为空，或只有 `merged`/`closed` 状态的 PR → **必须新建**
   - **绝不能复用已 merged/closed 的 PR 编号**

   根据 `repoType` 调用相应接口：
   - `gitea` → Gitea API
   - `github` → `gh pr create`
   - `other` → 输出手动命令后**终止命令**

   PR 标题：`chore(release): <version>`
   PR Body：包含本次发布的需求清单 + changelog 正文摘要 + 「合并后将自动在 {main_branch} 上创建 {version} 预发布」提示。

   > **提交顺序关键**：必须先完成步骤 1（提交产物到 develop 并 push），再创建/复用 PR。这样 PR 的 head 就包含 changelog，合并后主分支就有 changelog，不会出现步骤 4 的 "changelog 不存在" 错误。

3. **等待用户确认 PR 合并完成**

   输出提示并等待用户回复：
   ```
   ⏸️  PR 已创建：<PR URL>

       请在平台上完成代码审查并合并 PR。
       合并完成后回复「继续」或「y」以继续后续发布流程。
       回复其他内容将中止本次发布（已创建的 SQL/changelog/PR 会保留）。
   ```

   **这是强制交互点，必须等待用户输入，不得自动跳过或假设已合并。**

4. **拉取主分支最新状态**

   用户确认后：
   ```bash
   git checkout <main_branch>
   git pull --ff-only origin <main_branch>
   ```

   验证 PR 的合并提交已进入主分支：
   ```bash
   test -f docs/changelogs/<version>.md
   ```

   若文件不存在说明 PR 未真正合并或合并的是旧版本（例如复用了已合并 PR），此时：
   - **不得**尝试 `git checkout develop -- docs/changelogs/<version>.md` 这种补丁式操作
   - **不得**直接 push master
   - 警告用户 PR 状态异常，回到步骤 2 重新创建新 PR，再次等待合并确认

5. **继续执行步骤 9（打 tag）和步骤 10（创建 Release）**，此时：
   - tag 创建在 `main_branch` 的 HEAD 上
   - Release 标记为 `prerelease=true`（Gitea/GitHub 均不会触发正式 CD）

> 对于 `flow_mode == "direct"`，跳过本步骤，进入步骤 8.8。

### 8.8 提交产物（仅 `flow_mode == "direct"`）

direct 模式下，需在打 tag 前将所有产物和删除操作提交到当前分支：

```bash
git add docs/migrations/released/<version>.sql \
        docs/migrations/released/<version>.rollback.sql \
        docs/changelogs/<version>.md
# 步骤 6 的 git rm 已将删除放入暂存区，无需再 add
git commit -m "chore(release): prepare <version>"
```

（若部分文件不存在则跳过添加；若无任何变更则跳过 commit）

> 跨分支模式已在步骤 8.5.1 中处理，跳过本步骤。

### 9. 创建 Git Tag（非 draft 模式）或记录 target SHA（draft 模式）

**必须先确认当前在正确的分支 HEAD 上，然后记录当前 HEAD SHA**：

```bash
# tag 应该打在 tag_target 分支上（direct 模式 = 当前分支，cross-branch 模式 = main_branch）
CURRENT=$(git branch --show-current)
if [ "$CURRENT" != "$tag_target" ]; then
    echo "❌ 当前分支 $CURRENT ≠ 预期 tag 目标 $tag_target，终止"
    exit 1
fi

# 无论哪种模式都先捕获当前 HEAD SHA，供 step 10 的 Release API 使用
tag_target_sha=$(git rev-parse HEAD)
```

#### 9a. 非 draft 模式（`--no-draft`）：创建 annotated tag 并 push

```bash
TAG_MESSAGE="Release <version>

Includes:
- REQ-001 用户积分管理
- REQ-003 订单导出

See docs/changelogs/<version>.md for full notes."

git tag -a <version> -m "$TAG_MESSAGE"

# 立即 push tag，避免 Gitea Release API 在没有 tag 时使用 target_commitish 指向错误分支
git push origin <version>
```

#### 9b. draft 模式（**默认**）：**完全跳过** git tag 和 push

```bash
echo "📌 draft 模式：跳过本地 tag 创建，tag 将由平台在用户手工 publish 时生成"
echo "   target_commitish SHA = ${tag_target_sha}（将传给 step 10 的 Release API）"
```

**不创建本地 annotated tag**，**不 push 任何 tag**。tag 的生命完全托付给 step 10 创建的 draft release：用户在 Gitea/GitHub 上点 Publish 时，平台会根据 draft 里记录的 `target_commitish` 生成 lightweight tag。

---

**`tag_target` 定义**：
- `direct` 模式：`current_branch`（main 或 release/*）
- `cross-branch` 模式：`main_branch`

**为什么非 draft 模式要先 push tag**：Gitea/GitHub 的 Release API 在 tag 不存在时会用 `target_commitish` 现场创建 tag。如果 `target_commitish` 默认为默认分支（可能是 develop），tag 就被打错。先推已存在的 annotated tag，Release API 会直接引用，不再创建。

**为什么 draft 模式反而不 push tag**：
1. draft release 本身就把"创建 tag"这个动作推迟到 publish 时刻——这是 draft 的核心价值
2. draft 的 `target_commitish` **必须传 SHA** 而不是分支名，否则 publish 前若主分支前进，tag 会打在错误的 commit 上。`tag_target_sha` 在上面已经捕获了当前 HEAD 的 SHA，step 10 会直接使用
3. 本地如果先 `git tag -a` 会和平台最终创建的 lightweight tag 类型冲突，push 时还会被拦或产生 divergent 状态——干脆完全不碰本地 tag

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

**调用 API**（必须显式传 `target_commitish`，防止默认分支错误）：

```bash
# target_commitish 选择：
#   非 draft 模式 → 传分支名 tag_target（tag 已经 push，API 只是引用已有 tag）
#   draft 模式 → 传 tag_target_sha（SHA），防止 publish 前分支 HEAD 前进导致 tag 打错 commit
if [ "$IS_DRAFT" = "true" ]; then
    TARGET_COMMITISH="${tag_target_sha}"
else
    TARGET_COMMITISH="${tag_target}"
fi

curl -s -X POST "${GITEA_URL}/api/v1/repos/${OWNER}/${REPO}/releases" \
  -H "Authorization: token ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"tag_name\": \"<version>\",
    \"target_commitish\": \"${TARGET_COMMITISH}\",
    \"name\": \"<version>\",
    \"body\": \"<changelog 正文，需 JSON 转义>\",
    \"draft\": ${IS_DRAFT},
    \"prerelease\": ${IS_PRERELEASE}
  }"
```

> - **非 draft 模式**：`target_commitish` 必须是 `tag_target`（跨分支模式下 = `main_branch`）。如果 tag 已经 push，Gitea 会直接引用已有 tag；否则按 `target_commitish` 创建 tag。
> - **draft 模式**：`target_commitish` 必须是 `tag_target_sha`（40 位 SHA）。Gitea 把 draft 和 SHA 绑定，用户手工 publish 时创建 lightweight tag 指向这个 SHA，不受后续 master push 影响。

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
# 组装 gh 参数
GH_EXTRA_ARGS=()
if [ "$IS_PRERELEASE" = "true" ]; then
    GH_EXTRA_ARGS+=(--prerelease)
fi
if [ "$IS_DRAFT" = "true" ]; then
    # --draft 创建草稿；--target 传 SHA，防止 publish 前 HEAD 前进
    GH_EXTRA_ARGS+=(--draft --target "${tag_target_sha}")
fi

gh release create <version> \
  --title "<version>" \
  --notes-file docs/changelogs/<version>.md \
  "${GH_EXTRA_ARGS[@]}" \
  docs/migrations/released/<version>.sql \
  docs/migrations/released/<version>.rollback.sql
```

（后两个文件参数仅在生成 SQL 时附加）

> draft 模式下 `gh release create` 本身就不会 push tag（`--draft` 语义等价于 Gitea 的 draft release）。非 draft 模式不传 `--target` 时 gh 默认用当前 HEAD，与此前 step 9 已 push 的 annotated tag 一致。

**不可用时**输出命令让用户手动执行。

---

#### repoType = "other" 或未配置

仅输出可手动执行的命令提示，不调用 API。

### 10.5 切回起始分支

无论 `flow_mode` 是 `direct` 还是 `cross-branch`，在 tag/Release 完成后都要切回命令启动时所在的分支（记录为 `start_branch`）：

```bash
if [ "$(git branch --show-current)" != "$start_branch" ]; then
    git checkout "$start_branch"
fi
```

**用途**：
- 跨分支模式下从 `main` 切回 `developBranch`，避免用户残留在主分支上误操作
- 直接模式下若当前已在 `start_branch`，等同空操作
- 切换前若工作区有脏改动（不应该发生，但防御性检查），警告并跳过切换

### 11. 输出最终报告

**根据 `is_draft` 分叉：draft 模式（默认）见 §11b，非 draft 模式（`--no-draft`）见 §11a。**

#### 11a. 非 draft 模式（`--no-draft`）

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

#### 11b. draft 模式（**默认**）

```
⚠️  DRAFT 发布：<version> 草稿已创建，尚未对外发布

═══════════════════════════════════════════════
🏷️  Draft Release: <version>
═══════════════════════════════════════════════

📌 版本信息
├── 版本号：<version>
├── 类型：draft（prerelease=<is_prerelease>）
├── target SHA：<tag_target_sha 前 8 位>
├── flow_mode：<direct / cross-branch>
├── 版本范围：<from>..<to>
└── 包含需求：N 个

📋 包含需求
├── REQ-001 ...
└── ...

📄 SQL 脚本
├── docs/migrations/released/<version>.sql           (合并 X 个文件)
└── docs/migrations/released/<version>.rollback.sql  (自动 Y 条 / 待补 Z 条)
(若本次无 SQL：└── 无)

📝 版本说明
└── docs/changelogs/<version>.md

🏷️  Git Tag
└── ⚠️  尚未创建。用户在平台 publish 时，平台会在 SHA <前 8 位> 上创建 lightweight tag。

🚀 Draft Release
└── <Gitea/GitHub Draft Release URL>
    （仅作者 / 仓库管理员可见；publish 后对所有人可见）

═══════════════════════════════════════════════

⚠️  重要：本次发布停在 DRAFT 阶段，未完成！

    要最终发布 <version>，你必须手工操作：
      1. 打开上方 Draft Release URL
      2. 检查 release notes、附件（若有 SQL）
      3. 点 Publish Release（平台会在 target SHA 上创建 tag）

    未 publish 前：
      ❌ 没有 git tag
      ❌ 对外不可见
      ❌ CI/CD 不会触发
      ❌ 其他开发者看不到这个版本

💡 后续操作：
- 查看 draft：     <Draft Release URL>
- 查看版本说明：   cat docs/changelogs/<version>.md
- 放弃发布：       在平台上删除 draft release（tag 尚未创建，无需清理）
- 修改 release notes：在平台上直接编辑 draft，或删除后重新运行 /req:release <version>（默认仍走 draft）
```

---

## 边界情况处理

| 场景 | 处理方式 |
|------|---------|
| 当前在 feat/* / fix/* / hotfix/* 等 | **硬阻止**，提示切换到 `mainBranch` / release/* / `developBranch` |
| 在主分支（`mainBranch`）但加 `--prerelease` | 标记为预发布 |
| 在 release/* | 自动标记为预发布 |
| 在 `developBranch` | 走跨分支流程，最终在主分支上发预发布 |
| 跨分支流程中 PR 未合并用户中止 | 保留已生成的 SQL/changelog/PR，不打 tag |
| 跨分支流程中主分支 pull 后找不到合并提交 | 警告后重新等待用户确认 |
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
| 默认 draft 模式 + `repoType == other` | **自动降级为 `--no-draft`**，打印警告继续执行。平台 Release 不会创建，step 10 other 分支输出手工命令提示 |
| draft 模式 draft 创建成功但 release notes 错误 | 直接在平台上编辑 draft，或删除 draft 后重跑命令（本地本来就没有 tag，无需清理） |
| draft 模式下 draft 创建后用户迟迟未 publish | 命令已终止，责任在用户。建议记在团队 checklist 里，或用 cron 巡检未 publish 的 draft |
| `--no-draft` 在受保护主分支 + cross-branch 流程 | step 9a 会创建 annotated tag 并 `git push origin <tag>`。若 Gitea/GitHub 对 tag 也配了保护规则，push 会失败——此时改回默认 draft 模式绕过（draft 不需要本地 push tag） |
| 用户传 `--draft`（老语法） | 接受但不报错，因为它现在是默认行为的冗余别名；`args.draft` 变量不参与逻辑，`is_draft` 只看 `args.no_draft` |

## 用户输入

$ARGUMENTS
