---
description: 颁布版本 - 合并 SQL、生成回滚、打 tag、创建 Release
argument-hint: "<version> [--from=<tag>] [--to=<ref>]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(git:*, gh:*, curl:*)
---

# 颁布版本

将一组已完成需求打包成正式版本：合并 migration SQL、生成回滚脚本、调用 `/req:changelog`、打 git tag、根据仓库类型自动创建 Gitea/GitHub Release。

> 此命令**不受仓库角色限制**，readonly 仓库也可执行。
> 输出目录 `docs/migrations/released/`，不触发缓存同步。

> 📖 **设计原理与边界情况速查见 [`release-rationale.md`](./release-rationale.md)**。本命令的"为什么"段落、行为矩阵详解、完整边界情况大表全部迁到该伴随文档；正常发版流程不需要读它。出错或追问"为什么"时按需引用对应章节（§1~§12）。

## 命令格式

```
/req:release [<version>] [--bump=major|minor|patch] [--from=<tag|commit>] [--to=<ref>] [--no-draft] [--main=<branch>]
```

**参数说明：**
- `<version>`：**可选**，版本号（如 `v1.2.0`、`1.2.0`）。**不传则自动推导**（见 step 2.5）：基于最近一个 git tag + `<FROM_REF>..<TO_REF>` 范围内 commits 的 conventional commit 类型推导下一个 semver
- `--bump=major|minor|patch`：可选，显式指定 bump 等级，跳过自动扫描 commits。仅在未传 `<version>` 时生效；和 `<version>` 互斥
- `--from`：可选，起始点，默认上一个 git tag
- `--to`：可选，结束点，默认 HEAD
- `--no-draft`：可选，跳过 draft 阶段直接正式发布。默认行为是创建 draft release（详见 rationale §1），适用于 hotfix、可信任的自动化流水线、或 `repoType == other` 的场景
- `--main=<branch>`：可选，临时覆盖主分支名（优先级高于 `branchStrategy.mainBranch`）

**版本号解析优先级**：显式 `<version>` > `--bump=<level>` > 自动推导 commits

**默认 draft 模式行为差异（详见 rationale §5）**：
- `github`：draft 不 push tag（`gh release create --draft` 懒创建）。放弃发布仅删 draft
- `gitea`：draft **仍会 push annotated tag**（API 要求 tag 先存在）。放弃发布需同时删 draft 和 tag
- `other`：step 1.5 强制交互降级为 `--no-draft`

**示例：**
- `/req:release`（最常用：自动推导版本号，默认 draft）
- `/req:release --bump=minor`（自动推导但强制 minor bump）
- `/req:release v1.2.0 --no-draft`（显式版本号 + 跳过 draft）
- `/req:release --from=v1.1.0`（自动推导 + 指定起始范围）
- `/req:release --main=master`（临时覆盖主分支）

---

## 起步分支速查表

| 分支策略 | 推荐起步分支 | 流程模式 |
|---------|-------------|---------|
| `git-flow`（develop 起步） | `developBranch` | `cross-branch`（一个 PR：develop → main，合并后 tag） |
| `git-flow`（发布分支起步） | `release/<version>` 或 `chore/release-<version>` | `release-branch`（双 PR：release→main 先合+tag，release→develop 回流） |
| `github-flow` | `mainBranch` | `direct` |
| `trunk-based` | `mainBranch` | `direct` |

**何时选 cross-branch vs release-branch**（详见 rationale §3）：develop 到 main 的 delta 没有未准备发布的 feature 堆积 → cross-branch；否则用 release-branch 隔离。

若在 git-flow 的主分支上运行本命令，step 1.5 守门会提醒切到 develop 或 release 分支（详见 rationale §4）。

---

## 执行流程

### 1. 参数校验

```python
if args.version and args.bump:
    print("❌ <version> 和 --bump 互斥，请只传其中一个")
    print("   显式版本号：/req:release v1.2.0")
    print("   按等级推导：/req:release --bump=minor")
    exit()

# step 5.5 物料预览模板会引用 bump_reason，必须在两条路径上都有定义
if args.version:
    bump_reason = "用户显式指定版本号"
else:
    bump_reason = None  # step 2.5 填充
```

### 1.5 分支策略判定

```python
strategy = read_settings("branchStrategy", {})
current_branch = run("git branch --show-current")
main_branch = args.main or strategy.get("mainBranch", "main")
develop_branch = strategy.get("developBranch", "develop")
```

**判定规则**：

| 当前分支 | 流程模式 |
|---------|---------|
| `mainBranch` | **direct**（当前分支即 tag 目标，无 PR） |
| `release/*` / `chore/release-*` | **release-branch**（双 PR） |
| `developBranch` | **cross-branch**（单 PR） |
| 其他所有分支 | **禁止**，硬阻止 |

```python
if current_branch == main_branch:
    flow_mode = "direct"
    release_branch = None
elif current_branch.startswith("release/") or current_branch.startswith("chore/release-"):
    flow_mode = "release-branch"
    release_branch = current_branch
elif current_branch == develop_branch:
    flow_mode = "cross-branch"
    release_branch = None
else:
    print(f"❌ 当前分支 {current_branch} 不允许发布版本")
    print(f"   允许的分支：{main_branch}、release/*、chore/release-*、{develop_branch}")
    exit()

start_branch = current_branch   # 供 step 10.5 切回使用
```

**git-flow 保护分支守门**（详细背景见 rationale §4）：

```python
if (
    flow_mode == "direct"
    and current_branch == main_branch
    and strategy.get("model") == "git-flow"
):
    print(f"⚠️  git-flow 模式下当前在主分支 {main_branch}")
    print(f"    主分支通常有保护规则，prepare 提交会被 push 拒绝。")
    print(f"    推荐切到 {develop_branch}（cross-branch）或 release/<version>（release-branch）。")
    print()
    print("请选择：")
    print(f"  [1] 切到 {develop_branch} 并中止本次运行（最常见，需重新执行命令）")
    print(f"  [2] 继续在 {main_branch} 直接发布（仅当主分支无保护时选择）")
    print("  [3] 中止（手动建 release 分支后重跑）")
    choice = input("> ").strip()
    if choice == "1":
        run(f"git checkout {develop_branch}")
        rerun_hint = f"/req:release {args.version}" if args.version else "/req:release"
        print(f"✅ 已切到 {develop_branch}，请重新运行 {rerun_hint}")
        exit()
    elif choice != "2":
        print("已中止")
        exit()
```

**draft 模式默认开启**：

```python
# 默认 draft，--no-draft 显式关闭；老的 --draft 作为冗余别名（向前兼容）
is_draft = not bool(args.no_draft)

# repoType=other 强制交互降级（不静默降级，理由见 rationale §2）
repo_type = strategy.get("repoType", "other")
if is_draft and repo_type == "other":
    print("⚠️  repoType=other 不支持 draft release（依赖 Gitea/GitHub Release API）")
    print("   继续将立即创建 annotated tag 并 push（相当于 --no-draft），跳过 draft 闸门。")
    print()
    print("请选择：")
    print("  [y] 确认降级为 --no-draft，立即发版（不可逆）")
    print("  [n] 或其他 → 取消；如需 draft 请先 /req:branch init 把 repoType 配为 gitea/github")
    choice = input("> ").strip().lower()
    if choice != "y":
        print("已取消。")
        exit()
    is_draft = False
    print("✅ 已降级为 --no-draft，继续执行")
```

**这是强制交互点，不得自动跳过。**

显示判定结果：

```
📌 当前分支：develop
📌 分支策略：git-flow
🔀 流程模式：cross-branch（develop → main PR 后打 tag）
```

### 1.6 draft 模式行为速览

| `is_draft` | 最终行为 | 触发 |
|----|----|----|
| `false` | 本地 annotated tag → push → 平台正式 Release | `--no-draft` |
| `true` | 平台 draft Release（gitea 需先 push tag，github 懒创建） | **默认** |

**完整行为矩阵和 tag 处理细节见 rationale §5**。

**`--no-draft` 在 developBranch / release 分支的额外确认**（危险组合，详见 rationale §5.2）：

```python
if flow_mode in ("cross-branch", "release-branch") and not is_draft:
    entry = "developBranch" if flow_mode == "cross-branch" else "release 分支"
    print(f"⚠️  你正在 {entry} 上使用 --no-draft 直接发版")
    print("   PR 合并后立即在主分支创建 tag + 对外 Release，跳过 draft 闸门。")
    print("   常见误操作：原本只想 dry-check 却覆盖了 draft 默认。")
    print()
    print("请确认：")
    print("  [y] 继续，清楚跳过 draft 的含义")
    print("  [n] 或其他 → 取消，建议去掉 --no-draft 走默认 draft 流程")
    choice = input("> ").strip().lower()
    if choice != "y":
        print("已取消")
        exit()
```

**这是强制交互点，不得自动跳过。**

---

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

### 2.5 自动推导版本号

**触发条件**：`<version>` 未显式传入。显式传入则跳过整个 step 2.5（`bump_reason` 已由 step 1 赋值）。

**这是强制交互点，不得自动跳过。**

**整体流程**（按下面 if/elif/else 严格执行，不允许 fall-through）：

```python
if args.version:
    pass   # 显式路径：完全跳过 step 2.5

else:
    base_tag = run("git describe --tags --abbrev=0", allow_fail=True) or None

    if base_tag is None:
        # 分支 A：仓库无任何 tag → 首发 v0.1.0
        inferred = "v0.1.0"
        has_v_prefix = True
        bump_reason = "首次发版（仓库无任何 tag，默认 v0.1.0）"

    else:
        # 仅接受严格 X.Y.Z core semver（不识别 prerelease 后缀，详见 rationale §8.2）
        has_v_prefix = base_tag.startswith("v")
        raw = base_tag.lstrip("v")
        m = re.match(r"^(\d+)\.(\d+)\.(\d+)$", raw)

        if not m:
            # 分支 B：基线 tag 不是标准 X.Y.Z → 阻断
            print(f"❌ 基线 tag `{base_tag}` 不是标准 X.Y.Z semver 格式")
            print(f"   本命令已不支持 prerelease/RC 语义，请采用以下任一方式：")
            print(f"     /req:release <version>         # 显式指定")
            print(f"     /req:release --bump=patch      # 按等级 bump（需 tag 符合 X.Y.Z）")
            print(f"   或先手动打一个规范 tag 作为基线后重试")
            exit()

        major, minor, patch = int(m[1]), int(m[2]), int(m[3])
        inferred_core, bump_reason = compute_bump(
            base_tag, TO_REF, major, minor, patch,
            explicit_bump=args.bump,
        )
        inferred = f"v{inferred_core}" if has_v_prefix else inferred_core
```

**关键互斥**：
- 分支 A：首发，进入 2.5.5
- 分支 B：直接 `exit()`，不返回 2.5.5
- 主路径：调用 `compute_bump`，进入 2.5.5

#### 2.5.1 辅助函数：`compute_bump()`

```python
def compute_bump(base_tag, to_ref, major, minor, patch, explicit_bump):
    """扫描 commits 决定 bump 等级，返回 (inferred_core, bump_reason)。"""
    commits = run(
        f"git log {base_tag}..{to_ref} --pretty=format:%s%n%b --no-merges"
    ).splitlines()

    breaking_n = sum(
        1 for c in commits
        if re.match(r"^(feat|fix|refactor|perf|chore)!:", c)
        or "BREAKING CHANGE:" in c
    )
    feat_n = sum(1 for c in commits if re.match(r"^feat:", c))
    fix_n = sum(1 for c in commits if re.match(r"^fix:", c))
    perf_n = sum(1 for c in commits if re.match(r"^perf:", c))
    refactor_n = sum(1 for c in commits if re.match(r"^refactor:", c))

    if explicit_bump:
        level = explicit_bump
        bump_reason = f"--bump={level} 显式指定"
    elif breaking_n > 0:
        level = "major"
        bump_reason = f"检测到 {breaking_n} 个 breaking change → major bump"
    elif feat_n > 0:
        level = "minor"
        bump_reason = f"{feat_n} 个 feat、{fix_n} 个 fix、{perf_n + refactor_n} 个 perf/refactor → minor bump"
    elif fix_n + perf_n + refactor_n > 0:
        level = "patch"
        bump_reason = f"{fix_n} 个 fix、{perf_n} 个 perf、{refactor_n} 个 refactor → patch bump"
    else:
        # chore-only 范围阻断（详见 rationale §8.3）
        print(f"❌ {base_tag}..{to_ref} 范围内未检测到实质变更")
        print(f"   commits 只包含 chore/docs/style/test/ci 类型，拒绝自动发版。")
        print(f"   如确需发版：")
        print(f"     /req:release <version>           # 完全手工")
        print(f"     /req:release --bump=patch        # 强制 patch bump")
        exit()

    if level == "major":
        inferred_core = f"{major + 1}.0.0"
    elif level == "minor":
        inferred_core = f"{major}.{minor + 1}.0"
    else:
        inferred_core = f"{major}.{minor}.{patch + 1}"

    return inferred_core, bump_reason
```

#### 2.5.5 预览 + 确认

```python
print()
print("═══════════════════════════════════════════════")
print("📌 版本号推导")
print("═══════════════════════════════════════════════")
print(f"基线 tag:    {base_tag or '（无，首发）'}")
print(f"推导版本:    {inferred}")
print(f"推导依据:    {bump_reason}")
print()
print(f"确认版本号？")
print(f"  [y / 回车]     使用 {inferred}")
print(f"  [输入其他版本] 如 v1.4.0，覆盖推导结果")
print(f"  [n]            取消发版")
print()
```

**必须等待用户输入，不得自动跳过。**

```python
reply = input("> ").strip()
if reply == "" or reply.lower() == "y":
    args.version = inferred

elif reply.lower() == "n":
    print("已取消")
    exit()

else:
    # 用户手工覆盖：必须 X.Y.Z 样式（不接受 prerelease）
    if not re.match(r"^v?\d+\.\d+\.\d+$", reply):
        print(f"❌ `{reply}` 不是合法 X.Y.Z semver 格式，已取消")
        exit()

    # v 前缀规范化：与基线保持一致（规则详见 rationale §8.1）
    user_has_v = reply.startswith("v")
    if has_v_prefix and not user_has_v:
        normalized = f"v{reply}"
        print(f"📝 已自动补齐 `v` 前缀：{reply} → {normalized}")
        reply = normalized
    elif not has_v_prefix and user_has_v:
        normalized = reply.lstrip("v")
        print(f"📝 已自动去除 `v` 前缀：{reply} → {normalized}")
        reply = normalized

    args.version = reply
    bump_reason = f"用户在推导预览中手工覆盖为 {reply}"

version = args.version  # 后续 step 统一用 version 变量
```

`bump_reason` 会在 step 5.5 物料预览中再次展示，让用户最终确认时能回看版本号怎么来的。

---

### 3. 自动推算候选需求

```bash
git log $FROM_REF..$TO_REF --pretty=format:"%s%n%b" --no-merges \
  | grep -oE "(REQ|QUICK)-[0-9]+" \
  | sort -u
```

读取每个候选需求的文档（`active/` + `completed/`，按角色选本地或缓存），提取标题、类型、状态、关联 SQL（见 step 4）。

### 4. 扫描 migration 文件

输入目录 `docs/migrations/`（不含 `released/` 子目录）：

```bash
find docs/migrations -maxdepth 2 -name "*.sql" \
  ! -path "docs/migrations/released/*" 2>/dev/null
```

**关联规则**：文件名包含 `REQ-XXX` 或 `QUICK-XXX` 即归属对应需求。一个文件可属于多个需求（按出现顺序去重）。

### 5. 交互式选择

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
- `all` 选全部，序号列表（逗号分隔）选部分
- 回车 / 空输入 → 取消整个发布
- **必须等待用户输入，不得自动跳过**

### 5.5 产物预览与最终确认

> **⚠️ AI 硬规则：这是 step 6+ 之前的最后一道闸门，必须渲染、必须等待 y/n、必须不得静默跳过。**
> 详见 rationale §9。即使所有前置 step 都没有交互，本步也必须交互。

根据当前所有决定参数（`flow_mode`、`is_draft`、`repo_type`、是否带 SQL）计算并打印**本次发布将产出的所有物料清单**，等用户最后 y/n。

**计算输入**：
- `selected_reqs`：step 5 选中的需求（可能为空，允许"纯 commit 分类 changelog"流程）
- `has_sql`：`selected_reqs` 是否至少一个带 SQL 文件
- `sql_source_count`：待合并的源 SQL 文件数量
- `flow_mode`、`is_draft`、`repo_type`、`main_branch`、`develop_branch`、`release_branch`：step 1.5 已确定
- `version`、`bump_reason`：step 1 / 2.5 已确定

**输出模板**（条件分支必须动态渲染，不要把所有分支都打出来）：

```
═══════════════════════════════════════════════
📋 本次发布将产出（<version>）
═══════════════════════════════════════════════

🎯 模式
├── flow_mode:    <direct | cross-branch | release-branch>
├── draft:        <true | false>
├── repo_type:    <gitea | github | other>
└── bump_reason:  <bump_reason>

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
<若 flow_mode == release-branch>
└── ✅ chore(release): prepare <version>  →  <release_branch>（然后 push）

🔀 分支操作
<若 flow_mode == direct>
└── ❌ 无跨分支操作（direct 模式）
<若 flow_mode == cross-branch>
├── ✅ git push origin <develop_branch>
├── ✅ 创建 PR: <develop_branch> → <main_branch>
├── ⏸️  等待你确认 PR 合并完成  ← 阻塞点
└── ✅ git checkout <main_branch> && git pull --ff-only
<若 flow_mode == release-branch>
├── ✅ git push origin <release_branch>
├── ✅ 创建 PR1: <release_branch> → <main_branch>
├── ⏸️  等待 PR1 合并  ← 阻塞点 1
├── ✅ git checkout <main_branch> && git pull --ff-only
├── [打 tag + 平台 Release 在 <main_branch> 上发生]
├── ✅ git checkout <release_branch>
├── ✅ 创建 PR2: <release_branch> → <develop_branch>  (回流 release 准备 commit)
├── ⏸️  等待 PR2 合并（可跳过，未合并不影响 tag）
└── 🧹 PR2 合并后：删除 <release_branch>（本地 + 远程），PR2 pending 则保留

🏷️  Git Tag
<若 push_tag_first == true>
├── ✅ git tag -a <version>  (annotated,本地创建)
└── ✅ git push origin <version>  →  推到 <repo_type>
<若 push_tag_first == false>
└── ❌ 不创建本地 tag（平台 Release API 在 <main_branch> HEAD 生成 lightweight tag）

🚀 平台 Release
<若 is_draft == false>
└── ✅ <repo_type> Release <version>
       ├── target:     <tag_target>
       └── 状态:        正式发布（对外可见）
<若 is_draft == true>
└── ✅ <repo_type> **Draft** Release <version>
       ├── target_commitish:  <tag_target>
       ├── 状态:               草稿（仅作者/管理员可见）
       └── ⚠️  需手工在平台点 Publish 才真正发布

═══════════════════════════════════════════════

确认以上所有产物符合预期？
  [y] 继续执行 step 6+
  [n] 或其他 → 中止发布（已选需求不保留）
>
```

**用户回 y** → 进入 step 6；**其他回复** → 打印"已中止"并退出。

**这是强制交互点，必须等待用户输入，不得自动跳过。**

### 6. 合并 SQL

若所选需求中**至少一个**有 SQL 文件，则生成合并文件；否则跳到 step 8。

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

**⚠️ 必须在 step 6 写入成功后立即执行，不可跳过。** 设计依据见 rationale §10。

```bash
for sql_file in <merged_sql_files>; do
    git rm "$sql_file"
done
# 若文件未被 git 跟踪则用 rm
```

规则：
- 仅删除**被选中并成功合并**的文件，未选中需求的 SQL 保留
- 用 `git rm` 把删除放进暂存区（不单独 commit，由 step 8.5/8.7/8.8 统一提交）
- 若 `released/<version>.sql` 写入失败则**不得**执行本步骤

最终报告 step 11「SQL 脚本」区块追加一行：`└── 已清理 X 个源 SQL 文件`。

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

无论是否有 SQL，都自动生成版本说明：直接执行 changelog 命令的核心逻辑（读 commit、分类、关联需求、写入 `docs/changelogs/<version>.md`）。

若 `docs/changelogs/<version>.md` 已存在 → 直接覆盖（如需重新生成请在调用 `/req:release` 前手动备份或删除旧文件）。

### 8.5 跨分支流程（仅 `flow_mode == "cross-branch"`）

不在 develop 上打 tag，而是通过 PR 把产物合并到主分支，再在主分支完成 tag 和 Release。

**流程**：

1. **提交产物到 develop**（包含 SQL、回滚、changelog，以及 step 6.5 的 `git rm`）
   ```bash
   git add docs/migrations/released/<version>.sql \
           docs/migrations/released/<version>.rollback.sql \
           docs/changelogs/<version>.md
   git commit -m "chore(release): prepare <version>"
   git push origin <develop_branch>
   ```
   （若部分文件不存在则跳过添加）

2. **创建 PR：develop → main**

   **⚠️ 复用 PR 前必须检查状态**（详见 rationale §7.3）：

   ```bash
   curl -s "${GITEA_URL}/api/v1/repos/${OWNER}/${REPO}/pulls?state=open&head=${OWNER}:${develop_branch}&base=${main_branch}" \
     -H "Authorization: token ${TOKEN}"
   ```

   - `state=open` 的 PR → 复用（确认 head 指向最新 develop commit）
   - 空 / 仅 `merged`/`closed` → **必须新建**
   - **绝不能复用已 merged/closed 的 PR 编号**

   根据 `repoType`：
   - `gitea` → API
   - `github` → `gh pr create`
   - `other` → 输出手动命令后**终止命令**

   PR 标题：`chore(release): <version>`
   PR Body：本次发布的需求清单 + changelog 正文摘要 + 「合并后将自动在 {main_branch} 上创建 {version} 发布」提示。

   > 提交顺序关键（详见 rationale §7.1）：必须先完成 step 1（提交 + push），再创建 PR。

3. **等待用户确认 PR 合并完成**

   ```
   ⏸️  PR 已创建：<PR URL>

       请在平台完成审查并合并 PR。
       合并完成后回复「继续」或「y」继续后续流程。
       回复其他内容将中止本次发布（已生成的 SQL/changelog/PR 会保留）。
   ```

   **这是强制交互点，必须等待用户输入，不得自动跳过或假设已合并。**

4. **拉取主分支最新状态**

   ```bash
   git checkout <main_branch>
   git pull --ff-only origin <main_branch>
   test -f docs/changelogs/<version>.md
   ```

   若文件不存在（详见 rationale §7.4）：
   - **不得**做补丁式 `git checkout develop -- ...`
   - **不得**直接 push master
   - 警告 PR 状态异常，回到 step 2 重新创建新 PR

5. **继续执行 step 9（打 tag）和 step 10（创建 Release）**：tag 在 `main_branch` HEAD 上；默认 draft 需用户在平台手工 publish。

> `flow_mode == "direct"` 跳过本步骤，进入 step 8.8。
> `flow_mode == "release-branch"` 跳过本步骤，进入 step 8.7。

### 8.7 发布分支前置流程（仅 `flow_mode == "release-branch"`）

走"双 PR"流程。本步处理 PR1；PR2 延后到 step 10.6（设计依据见 rationale §7.2）。

**整体时间线**：

```
[本步 8.7]  提交产物到 release 分支 → PR1 → 等合并 → checkout main
[step 9]    在 main 上打 tag
[step 10]   创建平台 Release
[step 10.6] checkout release 分支 → PR2 → 等合并（回流到 develop）
[step 10.7] 清理 release 分支（本地 + 远程，PR2 pending 时跳过）
```

**执行步骤**：

1. **提交产物到 release 分支**

   ```bash
   git add docs/migrations/released/<version>.sql \
           docs/migrations/released/<version>.rollback.sql \
           docs/changelogs/<version>.md
   git commit -m "chore(release): prepare <version>"
   git push origin <release_branch>
   ```

2. **创建 PR1：release 分支 → main**

   复用规则同 §8.5 step 2（详见 rationale §7.3）：`state=open` 才复用，`merged`/`closed` 必须新建。

   - PR 标题：`chore(release): <version> → main`
   - PR Body：需求清单 + changelog 摘要 + "合并后将在 `<main_branch>` HEAD 上创建 tag `<version>`，然后发 PR2 回流 `<develop_branch>`"

3. **等待用户确认 PR1 合并完成**

   ```
   ⏸️  PR1 已创建：<PR URL>

       请在平台完成审查并合并 PR1 到 <main_branch>。
       合并完成后回复「继续」或「y」继续后续流程（打 tag + Release + PR2 回流）。
       回复其他内容将中止本次发布（已生成的 SQL/changelog/PR1 会保留）。
   ```

   **这是强制交互点，必须等待用户输入，不得自动跳过。**

4. **拉取主分支最新状态**

   ```bash
   git checkout <main_branch>
   git pull --ff-only origin <main_branch>
   test -f docs/changelogs/<version>.md
   ```

   若文件不存在：警告 PR1 状态异常，回到 step 2 重新创建（同 §8.5 处理，详见 rationale §7.4）。

5. **继续执行 step 9（打 tag）和 step 10（创建 Release）**：`tag_target = main_branch`，tag 创建方式由 §9 `PUSH_TAG_FIRST` 矩阵决定。step 10 完成后进入 **step 10.6** 处理 PR2。

> `flow_mode == "direct"` 跳过本步骤，进入 step 8.8。
> `flow_mode == "cross-branch"` 跳过本步骤（已在 step 8.5 处理）。

### 8.8 提交产物（仅 `flow_mode == "direct"`）

direct 模式下，需在打 tag 前将所有产物和删除操作提交到当前分支：

```bash
git add docs/migrations/released/<version>.sql \
        docs/migrations/released/<version>.rollback.sql \
        docs/changelogs/<version>.md
git commit -m "chore(release): prepare <version>"
```

（若部分文件不存在则跳过添加；若无任何变更则跳过 commit）

> 跨分支模式已在 step 8.5 处理，发布分支模式已在 step 8.7 处理，均跳过本步骤。

### 9. 创建 Git Tag 或记录 target SHA

**先确认当前在正确的分支 HEAD 上，并计算 `push_tag_first`**：

```bash
# tag_target：
#   direct        = 当前分支 (main)
#   cross-branch  = main_branch
#   release-branch = main_branch
CURRENT=$(git branch --show-current)
if [ "$CURRENT" != "$tag_target" ]; then
    echo "❌ 当前分支 $CURRENT ≠ 预期 tag 目标 $tag_target，终止"
    exit 1
fi

# push_tag_first 决策矩阵（设计依据详见 rationale §6）：
#   非 draft + gitea   → false (Gitea API 现场生成 lightweight tag，本地推冗余)
#   非 draft + github  → true  (避免 GitHub API 用默认分支当 target，打错分支)
#   非 draft + other   → true  (无 Release API，本地 + push 是唯一路径)
#   draft + gitea      → true  (Gitea API draft=true 要求 tag 先存在)
#   draft + github     → false (gh --draft 懒创建，平台 publish 时生成 lightweight tag)
#   draft + other      → 不进入（step 1.5 已降级）
if [ "$IS_DRAFT" = "true" ]; then
    if [ "$REPO_TYPE" = "gitea" ]; then
        PUSH_TAG_FIRST=true
    else   # github (other 已在 step 1.5 处理)
        PUSH_TAG_FIRST=false
    fi
else
    if [ "$REPO_TYPE" = "gitea" ]; then
        PUSH_TAG_FIRST=false
    else   # github / other
        PUSH_TAG_FIRST=true
    fi
fi
```

#### 9a. `PUSH_TAG_FIRST=true`：创建 annotated tag 并 push

覆盖：非 draft + github、非 draft + other、draft + gitea。

```bash
TAG_MESSAGE="Release <version>

Includes:
- REQ-001 用户积分管理
- REQ-003 订单导出

See docs/changelogs/<version>.md for full notes."

git tag -a <version> -m "$TAG_MESSAGE"
git push origin <version>
```

#### 9b. `PUSH_TAG_FIRST=false`：跳过本地 tag 创建

覆盖：draft + github、非 draft + gitea。tag 创建完全托付给 step 10 的 Release API。

```bash
if [ "$IS_DRAFT" = "true" ] && [ "$REPO_TYPE" = "github" ]; then
    echo "📌 draft + github：跳过本地 tag，gh release create --draft 将懒创建"
    echo "   target_commitish = ${tag_target}（publish 时在该分支 HEAD 生成 lightweight tag）"
elif [ "$IS_DRAFT" = "false" ] && [ "$REPO_TYPE" = "gitea" ]; then
    echo "📌 非 draft + gitea：跳过本地 tag，Gitea Release API 将在 target_commitish 现场生成"
    echo "   target_commitish = ${tag_target}"
fi
```

### 10. 创建 Gitea / GitHub Release

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

**Token 检查**：从 `branchStrategy.giteaToken` 读取，缺失时输出提示并跳过 Release（tag 仍保留）。

**前置条件**：
- **draft + gitea**：step 9 已 push annotated tag。`target_commitish` 仅作备用信息
- **非 draft + gitea**：step 9 **未** push tag——API 会在 `target_commitish=tag_target` 分支 HEAD 生成 lightweight tag

**调用 API**：

⚠️ **body 必须用 `jq --rawfile` 从文件构造 JSON**，不要手工拼接（emoji 处理详见 rationale §11）。

```bash
TARGET_COMMITISH="${tag_target}"

jq -n \
  --arg tag "<version>" \
  --arg target "${TARGET_COMMITISH}" \
  --arg name "<version>" \
  --rawfile body "docs/changelogs/<version>.md" \
  --argjson draft "${IS_DRAFT}" \
  '{tag_name: $tag, target_commitish: $target, name: $name, body: $body, draft: $draft}' \
  > /tmp/release-body.json

curl -s -X POST "${GITEA_URL}/api/v1/repos/${OWNER}/${REPO}/releases" \
  -H "Authorization: token ${TOKEN}" \
  -H "Content-Type: application/json; charset=utf-8" \
  --data-binary @/tmp/release-body.json
```

> Gitea 在 `draft=true` 且 tag 不存在时返回 `422 Release is has no Tag`。这就是为什么 step 9 对 `draft + gitea` 强制先 push tag。若遇此错，检查：
> 1. step 9 push 是否成功（`git ls-remote --tags origin | grep <version>`）
> 2. Gitea 实例是否因受保护分支规则拦截了 tag push

**已存在时**（HTTP 409 或查询命中）：提示 Release 已存在，输出链接，不重复创建。

**SQL 文件上传**（若生成了 SQL）：
```bash
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
GH_EXTRA_ARGS=()
if [ "$IS_DRAFT" = "true" ]; then
    GH_EXTRA_ARGS+=(--draft --target "${tag_target}")
fi

gh release create <version> \
  --title "<version>" \
  --notes-file docs/changelogs/<version>.md \
  "${GH_EXTRA_ARGS[@]}" \
  docs/migrations/released/<version>.sql \
  docs/migrations/released/<version>.rollback.sql
```

（后两个文件参数仅在生成 SQL 时附加）

> draft 模式下 `gh release create` 本身不 push tag。非 draft 模式不传 `--target` 时 gh 默认用当前 HEAD，与 step 9a 已 push 的 annotated tag 一致。

**不可用时**：输出命令让用户手动执行。

---

#### repoType = "other" 或未配置

仅输出可手动执行的命令提示，不调用 API。

### 10.5 切回起始分支

无论 `flow_mode` 是 `direct` / `cross-branch` / `release-branch`，tag/Release 完成后都切回 `start_branch`：

```bash
if [ "$(git branch --show-current)" != "$start_branch" ]; then
    git checkout "$start_branch"
fi
```

**用途**：
- `cross-branch`：从 `main` 切回 `developBranch`，避免残留在主分支误操作
- `release-branch`：从 `main` 切回 `release_branch`，准备 step 10.6 PR2
- `direct`：等同空操作
- 切换前若工作区脏（不应该发生），警告并跳过

### 10.6 PR2 回流到 develop（仅 `flow_mode == "release-branch"`）

tag 和 Release 已在 `main_branch` 完成。发 PR2 把 release 准备 commit（changelog + SQL + 回滚）回流到 `develop_branch`，避免下次 release 重复生成。

**前置条件**：step 10.5 已切回 `release_branch`。

1. **验证当前分支**

   ```bash
   CURRENT=$(git branch --show-current)
   if [ "$CURRENT" != "$release_branch" ]; then
       echo "⚠️  当前分支 $CURRENT ≠ 预期 release 分支 $release_branch，跳过 PR2"
       echo "   tag 和 Release 已完成；如需回流，请手动在平台发 PR: $release_branch → $develop_branch"
       # 不阻断，进入 step 11
   fi
   ```

2. **创建 PR2：release 分支 → develop**

   复用/新建规则同 §8.5 step 2。

   - PR 标题：`chore(release): backmerge <version> → develop`
   - PR Body：「回流 release 准备 commit（changelog + SQL + 回滚脚本）到 develop，避免下次 release 重复生成产物。tag `<version>` 已在 main 上创建，此 PR 不影响已发版本。」

3. **等待用户确认 PR2 合并完成（非阻塞式）**

   ```
   ⏸️  PR2 已创建：<PR URL>

       这是回流 PR，把 release 准备 commit 合到 develop。
       合并完成后回复「继续」或「y」，将在最终报告中标记 PR2 已合并。
       回复「跳过」或其他内容，PR2 保留等用户后续手动合并，命令直接进入最终报告。

       ⚠️ PR2 未合并不影响 tag 和 Release（已经出好），但 develop 会少一个 release prep commit，
          下次在相同 develop 上跑 release 会重新生成 changelog/SQL，造成冗余。
   ```

   **这是交互点，但非强制——用户可选「跳过」直接进入报告。**

   ```python
   pr2_status = "merged" if reply.lower() in ("y", "继续") else "pending"
   ```

4. **进入 step 10.7**（清理 release 分支），然后打印最终报告。

> `flow_mode == "direct"` 或 `"cross-branch"` 跳过本步骤。

### 10.7 清理 release 分支（仅 `flow_mode == "release-branch"`）

PR2 已合并后，`release_branch` 的使命已经结束，本地和远程都该删掉，避免残留。

**执行条件**：

| pr2_status | 动作 |
|---|---|
| `merged` | 删本地 + 远程 `release_branch`，记录 `cleanup_status = "done"` |
| `pending` | 跳过清理，记录 `cleanup_status = "skipped"`（原因：PR2 未合，分支还在用） |

**执行逻辑**：

```bash
cleanup_status="skipped"
cleanup_reason=""

if [ "$pr2_status" = "merged" ]; then
    # 先切到安全分支，避免删当前所在分支
    if [ "$(git branch --show-current)" = "$release_branch" ]; then
        git checkout "$main_branch" 2>/dev/null || git checkout "$develop_branch"
    fi

    # 本地删除（-D 强删：PR 合并后本地通常没有跟踪，用 -d 可能报 not fully merged）
    if git show-ref --verify --quiet "refs/heads/$release_branch"; then
        if git branch -D "$release_branch" 2>/dev/null; then
            local_deleted=true
        else
            local_deleted=false
            cleanup_reason="本地删除失败"
        fi
    else
        local_deleted=true   # 本地本来就没有
    fi

    # 远程删除（幂等：远端 ref 已不存在时 git 会以非 0 退出，需按输出判断）
    push_output=$(git push origin --delete "$release_branch" 2>&1)
    push_exit=$?
    echo "$push_output" > /tmp/release-delete.log

    if [ "$push_exit" -eq 0 ]; then
        remote_deleted=true
    elif echo "$push_output" | grep -qiE "remote ref does not exist|unmatched refspec"; then
        # 平台配置「合并后自动删除源分支」场景：远端已没有这个 ref，视为成功
        remote_deleted=true
    else
        remote_deleted=false
        cleanup_reason="${cleanup_reason:+$cleanup_reason；}远程删除失败（见 /tmp/release-delete.log）"
    fi

    if [ "$local_deleted" = "true" ] && [ "$remote_deleted" = "true" ]; then
        cleanup_status="done"
    else
        cleanup_status="partial"
    fi
else
    cleanup_reason="PR2 未合并（pr2_status=pending），保留 release 分支待后续"
fi
```

**注意事项**：
- 只有 `release-branch` 模式会进入本步；`direct` / `cross-branch` 模式没有需要清理的分支
- **幂等**：如果 Gitea/GitHub 配置了「合并后自动删除源分支」，远程分支可能已经没了，`git push --delete` 会报 `remote ref does not exist`——视为成功，不阻断流程
- 切回 `start_branch` 的逻辑已经在 step 10.5 跑过，本步开头的 checkout 只是个兜底

> `flow_mode == "direct"` 或 `"cross-branch"` 跳过本步骤（`cleanup_status` 保持 `"n/a"`）。

### 11. 输出最终报告

**根据 `is_draft` 分叉：draft 模式（默认）见 §11b，非 draft 模式见 §11a。**

#### 11a. 非 draft 模式（`--no-draft`）

```
✅ 版本 <version> 已颁布！

═══════════════════════════════════════════════
🏷️  Release: <version>
═══════════════════════════════════════════════

📌 版本信息
├── 版本号：<version>
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

<若 flow_mode == release-branch>
🔀 PR2 回流
└── <pr2_status == merged ? "✅ 已合并" : "⏸️ 待合并">  <PR2 URL>
    <若 pending：⚠️ 请尽快合并，避免下次 release 重复生成 changelog/SQL>

🧹 分支清理
<若 cleanup_status == done>
└── ✅ 已删除 <release_branch>（本地 + 远程）
<若 cleanup_status == partial>
└── ⚠️  部分删除：<cleanup_reason>；请手动检查 `git branch -D <release_branch>` / `git push origin --delete <release_branch>`
<若 cleanup_status == skipped>
└── ⏸️  保留 <release_branch>：<cleanup_reason>

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
├── 类型：draft
├── target：<tag_target>（主分支名）
├── flow_mode：<direct / cross-branch / release-branch>
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
<若 repo_type == "gitea">
└── ✅ annotated tag <version> 已创建并 push（Gitea 要求 tag 先存在才能建 draft）
<若 repo_type == "github">
└── ⚠️  尚未创建。用户在平台 publish 时，平台在 SHA <前 8 位> 上创建 lightweight tag。

🚀 Draft Release
└── <Gitea/GitHub Draft Release URL>
    （仅作者 / 仓库管理员可见；publish 后对所有人可见）

<若 flow_mode == release-branch>
🔀 PR2 回流
└── <pr2_status == merged ? "✅ 已合并" : "⏸️ 待合并">  <PR2 URL>
    <若 pending：⚠️ 请尽快合并，避免下次 release 重复生成 changelog/SQL>

🧹 分支清理
<若 cleanup_status == done>
└── ✅ 已删除 <release_branch>（本地 + 远程）
<若 cleanup_status == partial>
└── ⚠️  部分删除：<cleanup_reason>；请手动检查 `git branch -D <release_branch>` / `git push origin --delete <release_branch>`
<若 cleanup_status == skipped>
└── ⏸️  保留 <release_branch>：<cleanup_reason>

═══════════════════════════════════════════════

⚠️  重要：本次发布停在 DRAFT 阶段，未完成！

    要最终发布 <version>，你必须手工操作：
      1. 打开上方 Draft Release URL
      2. 检查 release notes、附件（若有 SQL）
      3. 点 Publish Release
         <若 gitea：只是把 draft 标志翻为 false，tag 已存在>
         <若 github：平台会在 target SHA 上创建 lightweight tag>

    未 publish 前：
      <若 gitea：⚠️ tag 已推送到远程（但 release 仍为草稿，CI/CD 不会触发）>
      <若 github：❌ 没有 git tag>
      ❌ release 对外不可见
      ❌ CI/CD 不会触发（大多数工作流用 release:published 事件）
      ❌ 其他开发者在 release 列表看不到

💡 后续操作：
- 查看 draft：     <Draft Release URL>
- 查看版本说明：   cat docs/changelogs/<version>.md
- 放弃发布：
    <若 gitea>： 1) 在平台删除 draft release
                 2) 清理已推送的 tag：git push --delete origin <version> && git tag -d <version>
    <若 github>：在平台上删除 draft release（tag 尚未创建，无需清理）
- 修改 release notes：在平台直接编辑 draft，或删除后重新运行 /req:release <version>（gitea 场景别忘连 tag 一起删）
```

---

## 边界情况

**完整速查表见 [`release-rationale.md`](./release-rationale.md) §12**。下面只列最常见的几条：

| 场景 | 处理 |
|------|------|
| 当前在 feat/* / fix/* / hotfix/* 等 | **硬阻止**，提示切到 `mainBranch` / `release/*` / `developBranch` |
| 跨分支流程 PR 未合并用户中止 | 保留已生成的 SQL/changelog/PR，不打 tag |
| `release-branch` 流程 PR2 用户选「跳过」 | tag 和 Release 已完成；PR2 保留等用户手动合并，报告标记 ⏸️；**不清理 release 分支** |
| `release-branch` 流程 PR2 已合并但分支被平台自动删除（Gitea/GitHub 合并后自动删源分支） | `git push --delete` 会报 remote ref does not exist；视为成功，`cleanup_status = done` |
| `release-branch` 流程本地 `git branch -D` 失败（分支有未合并 commit 或保护） | `cleanup_status = partial`，报告提示手动清理命令，不阻断发版 |
| 用户未选择任何需求 | 取消整个发布 |
| Gitea Release API 返回 `Release is has no Tag` (422) | 仅发生在 **draft + gitea**。详见 rationale §12 |
| `--no-draft` 在受保护主分支 + 跨分支流程 | 按 repoType 分叉处理。详见 rationale §12 |
| 用户传 `--draft`（老语法） | 接受但不报错（向前兼容别名） |

## 用户输入

$ARGUMENTS
