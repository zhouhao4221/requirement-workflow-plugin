---
description: 颁布版本 - 合并 SQL、生成回滚、打 tag、创建 Release
argument-hint: "<version> [--bump=major|minor|patch] [--from=<tag>] [--to=<ref>] [--tag] [--no-draft] [--main=<branch>]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(git:*, gh:*, tea:*, curl:*)
model: claude-haiku-4-5-20251001
---

# 颁布版本

准备发版产物（SQL 合并、回滚脚本、changelog、commit、PR）。**默认不创建 git tag**，加 `--tag` 后追加 tag 和平台 Release。

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
| `--tag` | 创建并推 git tag + 平台 Release（默认跳过） |
| `--no-draft` | 仅 `--tag` 时有效，正式发布（默认 draft） |
| `--main=<branch>` | 临时覆盖 `branchStrategy.mainBranch` |

示例：
- `/req:release`（准备产物 + PR，不打 tag）
- `/req:release --tag`（+ draft Release）
- `/req:release --tag --no-draft`（+ 正式 Release）
- `/req:release v1.2.0 --tag`（显式版本 + 打 tag）

## 起步分支速查

| 策略 | 必须从此分支运行 | 流程模式 |
|------|----------------|---------|
| `git-flow` | `developBranch` 或 `release/*` / `chore/release-*` | cross-branch / release-branch |
| `github-flow` / `trunk-based` | `mainBranch` | direct |
| 未配置 | 按当前分支名判断 | 同上规则 |

---

## 执行流程

### 步骤 1：参数校验 + 分支判定

1. `<version>` 与 `--bump` 互斥，否则报错退出
2. `create_tag = bool(args.tag)`；`--no-draft` 无 `--tag` 时警告忽略
3. 读 `branchStrategy`：`strategy_model / main_branch / develop_branch / repo_type`
4. **策略合规检查**（无确认，直接阻止）：
   - `git-flow` + 当前在 `main_branch`：自动 `git checkout <develop_branch>`，提示重跑，exit
   - `github-flow` / `trunk-based` + 当前不在 `main_branch`：硬阻止
5. **流程模式**：当前 == `main_branch` → `direct`；`release/*` / `chore/release-*` → `release-branch`；`develop_branch` → `cross-branch`；其他 → 硬阻止
6. **draft 初始化**（仅 `create_tag`）：
   - `is_draft = not args.no_draft`
   - `repoType=other` + draft：询问是否降级 `--no-draft`（**强制交互**）
   - cross/release-branch + `--no-draft`：额外确认（**强制交互**）

打印：`当前分支 / 策略 / 流程模式 / create_tag 状态`

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
5. 若 `!create_tag`：进入步骤 13c

**release-branch**：同 cross-branch，但 PR1 是 `<release_branch>` → `<main_branch>`，PR2（步骤 10.6）同样自动合并。

### 步骤 11：创建 Git Tag（仅 `--tag`）

确认当前在 `tag_target`（= `main_branch`）。`push_tag_first` 决策（详见 rationale §6）：

| 组合 | push_tag_first | 行为 |
|------|---------------|------|
| draft + gitea | true | annotated tag + push（Gitea draft 要求先存在） |
| draft + github | false | 不创建，gh release 懒创建 |
| 正式 + gitea | false | 不创建，API 从 target_commitish 生成 |
| 正式 + github / other | true | annotated tag + push |

### 步骤 12：创建平台 Release（仅 `--tag`）

Release notes 取 `docs/changelogs/<version>.md`。

- **gitea**：解析 remote URL，读 `branchStrategy.giteaToken`，`POST /api/v1/repos/.../releases`（body 用 `jq --rawfile`，详见 rationale §11），成功后上传 SQL 资产
- **github**：`gh release create <version> [--draft --target <tag_target>] --notes-file docs/changelogs/<version>.md [sql 文件...]`
- **other**：打印手动命令

已存在（HTTP 409）时打印链接，不重复创建。

### 步骤 10.5：切回起始分支

```bash
git checkout "$start_branch"
```

### 步骤 10.6：PR2 回流（仅 release-branch 且 `--tag`）

创建 PR2: `<release_branch>` → `<develop_branch>`，等待用户确认（**非阻塞**，可跳过）。

### 步骤 10.7：清理 release 分支（仅 release-branch 且 `--tag`）

PR2 merged → `git branch -D <release_branch>` + `git push origin --delete <release_branch>`。`remote ref does not exist` 视为成功。PR2 pending 时保留分支。

### 步骤 13：最终报告

**13a 非 draft（`--tag --no-draft`）**：
```
✅ 版本 <version> 已颁布！
📋 需求清单 / 📄 SQL 脚本 / 📝 版本说明
🏷️ ✅ tag 已推送  🚀 <Release URL>
💡 检查回滚 SQL：cat docs/migrations/released/<version>.rollback.sql
```

**13b draft（`--tag`）**：
```
⚠️ DRAFT：<version> 草稿已创建，需手工 Publish
📋/📄/📝 同上
🏷️  gitea: ✅ annotated tag 已推 | github: ⚠️ 未创建（publish 时生成）
🚀 <Draft Release URL>（仅作者/管理员可见）
⚠️ 未 publish 前：CI/CD 不触发，release 不可见
💡 放弃：gitea 需删 draft + tag；github 只删 draft
```

**13c 无 tag（默认）**：
```
✅ 版本 <version> 产物已就绪！
📋/📄/📝 同上
🏷️ ❌ 未指定 --tag  🚀 ❌ 未指定 --tag
🔀 PR: <PR URL>（等待合并到 <main_branch>）
💡 合并后：/req:release <version> --tag
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
| `--no-draft` 未搭配 `--tag` | 警告忽略 |
| 未指定 `--tag` | 步骤 11/12/10.6/10.7 跳过 |
| Gitea draft 422（Release is has no Tag） | 详见 rationale §12 |
| `--draft`（老语法） | 接受但忽略（默认已是 draft） |

## 用户输入

$ARGUMENTS
