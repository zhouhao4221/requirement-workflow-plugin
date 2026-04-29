---
description: 颁布版本 - 合并 SQL、生成回滚、打 tag、创建 Release
argument-hint: "<version> [--bump=major|minor|patch] [--from=<tag>] [--to=<ref>] [--tag] [--no-draft] [--main=<branch>]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(git:*, gh:*, tea:*, curl:*)
model: claude-haiku-4-5-20251001
---

# 颁布版本

准备发版产物（SQL 合并、回滚脚本、changelog、commit、PR）并**默认创建 draft Release**。加 `--tag` 额外创建 annotated git tag；加 `--no-draft` 直接正式发布。

> readonly 仓库可用。不触发缓存同步。
> CLI 优先：GitHub → `gh`；Gitea → 检测 `tea`，不支持的接口回退 curl。详见 [`_gitea_cli.md`](./_gitea_cli.md)。
> 设计原理和边界情况详见 [`release-rationale.md`](./release-rationale.md)。

## 参数

| 参数 | 说明 |
|------|------|
| `<version>` | 可选，如 `v1.2.0`。不传则自动推导（见步骤 2） |
| `--bump=major\|minor\|patch` | 显式 bump 等级，与 `<version>` 互斥 |
| `--from=<ref>` | 起始点，默认上一个 git tag |
| `--to=<ref>` | 结束点，默认 HEAD |
| `--tag` | **额外**创建并推送 annotated git tag（Release 始终创建） |
| `--no-draft` | 创建正式 Release（默认 draft） |
| `--no-release` | 跳过创建平台 Release，仅准备产物和 PR |
| `--main=<branch>` | 临时覆盖 `branchStrategy.mainBranch` |

示例：
- `/req:release`（准备产物 + PR + draft Release，不打 tag）
- `/req:release --tag`（同上 + annotated tag）
- `/req:release --no-draft`（正式 Release，无 tag）
- `/req:release --tag --no-draft`（正式 Release + tag）
- `/req:release v1.2.0`（显式版本 + draft Release）

## 起步分支速查

| 策略 | 必须从此分支运行 | 流程模式 | PR2 回流 |
|------|----------------|---------|---------|
| `git-flow`（develop 起步） | `developBranch` | cross-branch | ✅ main → develop |
| `git-flow`（发布分支起步） | `release/*` / `chore/release-*` | release-branch | ✅ release → develop |
| `github-flow` / `trunk-based` | `mainBranch` | direct | ❌ 无需回流 |
| 未配置 | 按当前分支名判断 | 同上规则 | ❌ 无需回流 |

---

## 执行流程

### 步骤 0：角色检查

读取 `.claude/settings.local.json` 中的 `requirementRole`：

- **readonly**：
  - 从全局缓存 `~/.claude-requirements/projects/<requirementProject>/` 读取需求文档
  - **禁止修改任何 `docs/requirements/` 下的文件**（包括状态更新、关联信息追加等）
  - SQL 合并（`docs/migrations/released/`）和 changelog（`docs/changelogs/`）的写入**不受此限**——这些是版本产物，不是需求文档；目录不存在时自动创建
  - 其余步骤（git commit、PR、tag）照常执行
- **primary / 未配置**：正常读写本地 `docs/requirements/`

### 步骤 1：参数校验 + 分支判定

1. `<version>` 与 `--bump` 互斥，否则报错退出
2. `create_tag = bool(args.tag)`；`skip_release = bool(args.no_release)`
3. 读 `branchStrategy`：`strategy_model / main_branch / develop_branch / repo_type`
4. **策略合规检查**（无确认，直接阻止）：
   - `git-flow` + 当前在 `main_branch`：自动 `git checkout <develop_branch>`，提示重跑，exit
   - `github-flow` / `trunk-based` + 当前不在 `main_branch`：硬阻止
5. **流程模式**：当前 == `main_branch` → `direct`；`release/*` / `chore/release-*` → `release-branch`；`develop_branch` → `cross-branch`；其他 → 硬阻止
6. **draft 初始化**（`skip_release=false` 时执行）：
   - `is_draft = not args.no_draft`
   - `repoType=other` + draft：询问是否降级 `--no-draft`（**强制交互**）
   - cross/release-branch + `--no-draft`：额外确认（**强制交互**）
   - `repoType=gitea` + draft + `!create_tag`：Gitea draft Release 要求 tag 先存在，但未指定 `--tag`；询问（**强制交互**）：
     - [1] 改用 `--no-draft`：Gitea API 自动从 `target_commitish` 生成 lightweight tag，创建正式 Release
     - [2] 加 `--tag`：额外创建 annotated tag，继续 draft Release
     - [3] 取消

打印：`当前分支 / 策略 / 流程模式 / create_tag / skip_release / is_draft`

### 步骤 2：确定版本号和 git 范围

**范围**：`FROM_REF`（上一 git tag，无则仓库首次 commit）→ `TO_REF`（`--to` 或 HEAD）

**版本推导**（未传 `<version>` 时执行）：
- 无任何 tag → 首发 `v0.1.0`
- 基线 tag 非 X.Y.Z semver → 阻断，提示显式传版本号
- 扫描 `FROM_REF..TO_REF` commits，按优先级 bump：`!:` / `BREAKING CHANGE` → major；`feat:` → minor；`fix:/perf:/refactor:` → patch；仅 chore/docs/style/test/ci → 阻断
- `--bump` 存在时直接用，跳过扫描
- 打印 `基线 tag / 推导版本 / 推导依据`，**自动使用推导结果**（如需覆盖请显式传参）

### 步骤 3：扫描候选需求

```bash
git log $FROM_REF..$TO_REF --pretty=format:"%s%n%b" --no-merges \
  | grep -oE "(REQ|QUICK)-[0-9]+" | sort -u
```

读取每个需求文档，提取标题/类型/状态/关联 SQL 文件数。
- **primary**：从 `docs/requirements/` 读取
- **readonly**：从 `~/.claude-requirements/projects/<requirementProject>/` 读取；不存在则跳过该需求，继续纯 commit changelog 流程

### 步骤 4：扫描 migration SQL

```bash
find docs/migrations -maxdepth 2 -name "*.sql" ! -path "docs/migrations/released/*"
```

文件名含 `REQ-XXX` / `QUICK-XXX` 即归属对应需求。

### 步骤 5：自动选择需求

- `已完成` 需求：自动纳入，打印清单
- 其他状态：展示后询问一次 `[y/N]`（本步唯一交互点）
- 无需求：继续纯 commit changelog 流程

### 步骤 6：打印产物预览，自动继续

打印：`flow_mode / draft / create_tag / bump_reason / 将产出的文件 / 分支操作计划 / tag + Release 计划`

自动继续（如需中止请按 Ctrl+C）。

### 步骤 7：合并 SQL（有 SQL 时执行）

输出 `docs/migrations/released/<version>.sql`，文件头注释含 Release/Date/Range/Includes，每段前加来源注释，按选中顺序排列。

**写入成功后立即 `git rm` 所有已合并的源 SQL 文件**（详见 rationale §10），放入暂存区由后续 commit 统一提交。

### 步骤 8：生成回滚 SQL

输出 `docs/migrations/released/<version>.rollback.sql`，倒序排列（后建的先回滚）：

| 正向语句 | 自动生成回滚 |
|---------|------------|
| `CREATE TABLE x` | `DROP TABLE x;` |
| `CREATE TABLE IF NOT EXISTS x` | `DROP TABLE IF EXISTS x;` |
| `ALTER TABLE x ADD COLUMN y` | `ALTER TABLE x DROP COLUMN y;` |
| `ALTER TABLE x ADD INDEX i` | `ALTER TABLE x DROP INDEX i;` |
| `CREATE [UNIQUE] INDEX i ON x` | `DROP INDEX i;` |
| `ALTER TABLE x RENAME TO y` | `ALTER TABLE y RENAME TO x;` |
| INSERT / UPDATE / DELETE / DROP / 复杂 ALTER | `-- ⚠️ 需手动补充：<原语句首 80 字>` |

记录待补充数量，最终报告中提示。

### 步骤 9：生成 changelog

执行 `/req:changelog` 核心逻辑，写入 `docs/changelogs/<version>.md`（已存在则覆盖）。

### 步骤 10：提交产物 + 推送 + PR

**direct**：`git add` 所有产物 → `git commit "chore(release): prepare <version>"`，进入步骤 11。

**cross-branch**：
1. commit + `git push origin <develop_branch>`
2. 创建 PR: `<develop_branch>` → `<main_branch>`（复用 `state=open` 的 PR，不复用 merged/closed，详见 rationale §7.3）
   - `gitea` → API；`github` → `gh pr create`；`other` → 打印命令后终止
   - Body：需求清单 + changelog 摘要
3. **自动合并 PR**：
   - `github`：`gh pr merge <PR_NUMBER> --merge --delete-branch`
   - `gitea`：`POST /api/v1/repos/{owner}/{repo}/pulls/{index}/merge`（`{"Do":"merge"}`）
   - 合并失败（分支保护/CI 未通过）→ 打印 PR URL，等待用户手动合并后回复「继续」（**强制交互**）
4. `git checkout <main_branch> && git pull --ff-only`（验证 changelog 存在，异常见 rationale §7.4）
5. 继续步骤 11（若 `create_tag`）和步骤 12（若 `!skip_release`）

**release-branch**：同 cross-branch，但 PR1 是 `<release_branch>` → `<main_branch>`，PR2（步骤 14）同样自动合并。

### 步骤 10.9：主分支强制验证（步骤 11/12 前必须通过）

**无论 flow_mode 是 direct / cross-branch / release-branch，执行 tag 或 Release 前必须硬性确认当前在 `main_branch` 上：**

```bash
CURRENT=$(git branch --show-current)
if [ "$CURRENT" != "$main_branch" ]; then
    echo "❌ 当前分支 $CURRENT ≠ 主分支 $main_branch"
    echo "   Release 只能从 $main_branch 发布（branchStrategy.mainBranch）"
    echo "   请手动执行：git checkout $main_branch && git pull --ff-only"
    echo "   然后重新运行本命令"
    exit 1
fi
```

`target_commitish` 后续所有步骤统一使用 `main_branch`，**不使用 develop / release 分支**。

### 步骤 11：创建 Git Tag（仅 `--tag`）

确认当前在 `main_branch`（步骤 10.9 已保证）。`push_tag_first` 决策（详见 rationale §6）：

| 组合 | push_tag_first | 行为 |
|------|---------------|------|
| draft + gitea | true | annotated tag + push（Gitea draft 要求先存在） |
| draft + github | false | 不创建，gh release 懒创建 |
| 正式 + gitea | false | 不创建，API 从 target_commitish 生成 |
| 正式 + github / other | true | annotated tag + push |

### 步骤 12：创建平台 Release（`skip_release=false` 时执行）

Release notes 取 `docs/changelogs/<version>.md`。**`target_commitish` 固定为 `main_branch`（由步骤 10.9 保证），绝不使用 develop / release 分支。**

- **gitea**：解析 remote URL，读 `branchStrategy.giteaToken`，`POST /api/v1/repos/.../releases`（body 用 `jq --rawfile`，详见 rationale §11），`target_commitish: main_branch`，成功后上传 SQL 资产
- **github**：`gh release create <version> [--draft] --target <main_branch> --notes-file docs/changelogs/<version>.md [sql 文件...]`
- **other**：打印手动命令

已存在（HTTP 409）时打印链接，不重复创建。

### 步骤 13：切回起始分支

```bash
git checkout "$start_branch"
```

### 步骤 14：PR2 回流到 `branchFrom`（git-flow 模式）

**触发条件**：`strategy_model == "git-flow"`（即配置了 `developBranch`）且当前非 direct 模式。

git-flow 要求版本产物（changelog / SQL / version bump）同时落在 `mainBranch` 和 `branchFrom`，PR2 负责把主分支的内容回流到 develop，防止两者分叉。

| flow_mode | PR2 方向 | 说明 |
|-----------|---------|------|
| `cross-branch` | `main_branch` → `develop_branch` | 把 main 上的 merge commit 回流到 develop |
| `release-branch` | `release_branch` → `develop_branch` | 把 release 准备 commit 回流到 develop |

- PR 标题：`chore(release): backmerge <version> → <develop_branch>`
- PR Body：「回流版本产物到 `<develop_branch>`，确保 git-flow 两条主线同步。tag `<version>` 已在 `<main_branch>` 上创建，此 PR 不影响已发版本。」
- 等待用户确认（**非阻塞**，可跳过）；跳过时最终报告标记 ⏸️

### 步骤 15：清理 release 分支（仅 release-branch）

PR2 merged → `git branch -D <release_branch>` + `git push origin --delete <release_branch>`。`remote ref does not exist` 视为成功。PR2 pending 时保留分支。

### 步骤 16：最终报告

**16a 正式 Release（`--no-draft`）**：
```
✅ 版本 <version> 已颁布！
📋 需求清单 / 📄 SQL 脚本 / 📝 版本说明
🏷️ <若 --tag：✅ annotated tag 已推送 | 否则：— 无本地 tag（平台自动生成 lightweight tag）>
🚀 <Release URL>
💡 检查回滚 SQL：cat docs/migrations/released/<version>.rollback.sql
```

**16b draft Release（默认）**：
```
⚠️ DRAFT：<version> 草稿已创建，需手工 Publish
📋/📄/📝 同上
🏷️ <若 --tag：gitea: ✅ annotated tag 已推 | github: ⚠️ publish 时生成 | 否则：— 无本地 tag>
🚀 <Draft Release URL>（仅作者/管理员可见）
⚠️ 未 publish 前：CI/CD 不触发，release 不可见
💡 放弃：gitea 需删 draft（若有 tag 一并删）；github 只删 draft
```

**16c 跳过 Release（`--no-release`）**：
```
✅ 版本 <version> 产物已就绪！
📋/📄/📝 同上
🏷️ <若 --tag：✅ tag 已推送 | 否则：— 无 tag>
🚀 — 已跳过（--no-release）
🔀 PR: <PR URL>（等待合并到 <main_branch>）
```

---

## 边界情况

完整速查见 [rationale §12](./release-rationale.md)：

| 场景 | 处理 |
|------|------|
| feat/fix/hotfix/* 等分支 | 硬阻止 |
| git-flow + 在主分支 | 自动切 develop，提示重跑 |
| github-flow/trunk-based + 非主分支 | 硬阻止 |
| PR 未合并用户中止 | 保留已生成产物，不打 tag |
| 无 candidate 需求 / 全跳过未完成 | 继续纯 commit changelog |
| `--no-draft` 未指定 `--tag` | 正常执行，Release 公开，平台生成 lightweight tag |
| 未指定 `--tag` | 仅跳过步骤 11（annotated tag），Release 照常创建 |
| `--no-release` | 跳过步骤 12，仅准备产物和 PR |
| `repoType=gitea` + draft + 无 `--tag` | 步骤 1 强制交互，选择降级 --no-draft 或补 --tag |
| git-flow + cross-branch / release-branch | 步骤 14 自动创建 PR2 回流到 `developBranch`；github-flow / trunk-based 跳过 |
| Gitea draft 422（Release is has no Tag） | 详见 rationale §12 |
| `--draft`（老语法） | 接受但忽略（默认已是 draft） |

## 用户输入

$ARGUMENTS
