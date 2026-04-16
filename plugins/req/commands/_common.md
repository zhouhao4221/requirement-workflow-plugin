# 公共逻辑参考

> 此文档定义所有命令共用的逻辑，各命令直接引用，避免重复。

## settings.local.json 写入规范

所有插件配置统一存���在 `.claude/settings.local.json` 中。

**写入规则（强制）**：

1. **唯一配置文件**：所有配置（`requirementProject`、`requirementRole`、`branchStrategy` 等）必须写入 `.claude/settings.local.json`，**禁止**创建独立配置文件（如 `.claude/devflow.json`、`branchStrategy.json`、`requirement-config.json` 等）。独立文件不会被 Claude Code 识别
2. **合并写入**：先读取已有 `settings.local.json` 内容，合并需要更新的字段后写回，**不得覆盖已有字段**
3. **目录检查**：`.claude/` 目录不存在时先创建
4. **无写入权限的回退**：当 Write/Edit 工具被拒绝或无权限写入 `.claude/settings.local.json` 时，**不得**改写到其他文件，而应直接输出一段可复制执行的 shell 命令（使用 `python3 -c` 或 `jq`）让用户自己运行，例如：

   ```bash
   python3 -c "import json,os; p='.claude/settings.local.json'; os.makedirs('.claude',exist_ok=True); d=json.load(open(p)) if os.path.exists(p) else {}; d['requirementProject']='my-project'; d['requirementRole']='primary'; json.dump(d,open(p,'w'),indent=2,ensure_ascii=False)"
   ```

```python
# 正确写法
import json, os

path = ".claude/settings.local.json"
os.makedirs(".claude", exist_ok=True)

# 读取已有内容
existing = {}
if os.path.exists(path):
    with open(path) as f:
        existing = json.load(f)

# 合并更新
existing["branchStrategy"] = { ... }  # 只更新需要的字段

# 写回
with open(path, "w") as f:
    json.dump(existing, f, indent=2, ensure_ascii=False)
```

---

## 存储路径解析

```
本地存储（主）: docs/requirements/
├── modules/      # 模块文档
├── specs/        # 规范文档（数据类型、接口契约等，跨仓库共享）
├── active/       # 进行中需求
├── completed/    # 已完成需求
└── INDEX.md      # 索引

全局缓存（副）: ~/.claude-requirements/projects/<project>/
```

**解析规则**：
1. 读取 `.claude/settings.local.json` 的 `requirementProject` 和 `requirementRole`
2. 有值 → 使用全局缓存路径
3. 无值 → 使用本地 `docs/requirements/`

**仓库角色**（`requirementRole` 字段）：

| 角色 | 值 | 说明 |
|------|------|------|
| 主仓库 | `primary` | 拥有本地 `docs/requirements/`，可读写，修改后自动同步到缓存 |
| 只读仓库 | `readonly` | 无本地存储，仅从缓存读取需求，不可创建/编辑/变更状态 |

**读取策略**：
- `primary`：优先本地 → 本地不存在时从缓存读取
- `readonly`：直接从缓存读取

## 缓存同步规则（强制自动，无需确认）

**核心原则**：需求文档修改后**强制自动同步**到全局缓存，无需用户确认。

| 操作 | 本地 | 缓存同步 |
|-----|------|---------|
| 创建需求 | 写入 active/ | **强制**复制到缓存 active/ |
| 编辑需求 | 更新文件 | **强制**复制到缓存覆盖 |
| 状态变更 | 更新文件 | **强制**复制到缓存覆盖 |
| 完成归档 | 移动到 completed/ | **强制**缓存同步移动 |

**强制同步机制**：

通过 PostToolUse Hook **自动强制触发**，仅当命令涉及需求文档修改时触发缓存同步：

触发同步的命令：
- `/req:new` - 创建需求文档
- `/req:new-quick` - 创建快速修复文档
- `/req:edit` - 编辑需求文档
- `/req:review` - 更新评审状态
- `/req:dev` - 更新开发状态和进度
- `/req:test` - 更新测试状态和结果
- `/req:done` - 完成归档
- `/req:upgrade` - 升级 QUICK 为 REQ
- `/req:modules new` - 创建模块文档
- `/req:prd-edit` - 编辑 PRD 文档
- `/req:specs new` - 创建规范文档
- `/req:specs edit` - 编辑规范文档

不触发同步的命令（只读操作）：`/req`、`/req:status`、`/req:show`、`/req:specs`（列表/show）、`/req:projects`、`/req:cache`、`/req:use`、`/req:init`、`/req:migrate`、`/req:test_regression`、`/req:test_new`、`/req:prd`、`/req:changelog`、`/req:commit`、`/req:fix`、`/req:do`、`/req:review-pr`

同步配置：
- Hook 脚本：`scripts/sync-cache.sh`
- 触发条件：**Write 或 Edit 工具**操作 `docs/requirements/` 目录下的文件后
- 同步范围：REQ-XXX、QUICK-XXX 需求文档、模块文档（modules/）、规范文档（specs/）及 PRD.md，不含 INDEX.md、template.md
- **执行方式**：静默自动执行，仅输出同步状态提示

**重要原则**：
1. **强制同步**：缓存同步是强制行为，不可跳过，不需要用户确认
2. **本地优先**：所有修改需求的命令（new、edit、review、dev、test、done）都必须先更新本地 `docs/requirements/` 中的文档
3. **本地成功后立即同步**：本地操作成功后**立即自动**同步到全局缓存
4. **只读仓库禁止写操作**：`requirementRole=readonly` 的仓库不执行创建、编辑、状态更新、缓存同步等写操作，仅允许读取和查看
5. **以本地为准**：同步时直接用本地版本覆盖缓存，不进行冲突检测

## 状态更新确认机制

不同命令对状态更新的确认要求：

| 命令 | 状态变更 | 确认机制 |
|-----|---------|---------|
| `/req:review pass/reject` | 待评审 → 评审通过/驳回 | 显式参数即为确认 |
| `/req:dev` | 评审通过 → 开发中 | 首次进入时自动更新 |
| `/req:test` | 开发中 → 测试中 | 测试完成后自动更新 |
| `/req:done` | 测试中 → 已完成 | **必须明确确认（y/n）** |

## 确认操作规范

确认操作通过 **PreToolUse Hook** 自动保障，不依赖文本提示。

### Hook 原生确认（自动触发）

PreToolUse Hook 在以下操作执行前自动弹出原生确认对话框：

| 操作 | Hook 脚本 | 触发条件 |
|------|----------|---------|
| 写入需求文档 | confirm-before-write.sh | Write/Edit 目标为 docs/requirements/ |
| 覆盖模板 | confirm-before-write.sh | Write/Edit 目标为 templates/ |
| 覆盖版本说明 | confirm-before-write.sh | Write/Edit 已存在的 changelogs/ 文件 |
| git commit | confirm-before-commit.sh | Bash 命令包含 git commit |
| 移动需求文件 | confirm-before-commit.sh | Bash 命令包含 mv ... REQ-/QUICK- |
| 删除需求文件 | confirm-before-commit.sh | Bash 命令包含 rm ... REQ-/QUICK- |

### 执行规则

1. **展示预览后直接执行** — 不输出"回车继续"等文本确认提示
2. **Hook 自动拦截** — 关键操作由 Hook 弹出原生对话框，用户在对话框中确认
3. **需要用户输入的场景仍需等待** — 选择章节编号、选择目标需求、描述修改意图等

## 需求编号生成

扫描 active/ 和 completed/ 目录，找最大编号 +1，格式 `REQ-XXX`

## 状态流转

```
📝 草稿 → 👀 待评审 → ✅ 评审通过 → 🔨 开发中 → 🧪 测试中 → 🎉 已完成
```

## Memory 隔离规则（强制）

涉及模板的命令和 skill **禁止受 auto-memory 影响**。模板化输出必须完全由模板结构和用户当前输入决定，不得因 memory 中的偏好、历史记录或反馈而改变文档结构、章节内容或格式。

**适用范围**：
- 命令：`/req:new`、`/req:new-quick`、`/req:edit`、`/req:upgrade`、`/req:prd-edit`
- skill：`requirement-analyzer`、`prd-analyzer`

**具体禁止行为**：
1. 不得根据 memory 中的偏好跳过或合并模板章节
2. 不得根据 memory 中的历史需求自动填充当前需求内容
3. 不得根据 memory 中的反馈调整模板格式（如章节顺序、表格列数）
4. 不得读取 `~/.claude/projects/*/memory/` 目录下的文件来辅助文档生成

**允许的行为**：memory 可影响**交互风格**（如提问的详略程度），但不得影响**文档产出物**。

---

## 模板格式约束（强制）

创建和编辑需求文档时，**必须严格遵循模板格式**：

### 模板读取优先级

| 需求类型 | 优先读取 | 回退读取 |
|---------|---------|---------|
| REQ-XXX | `docs/requirements/templates/requirement-template.md` | `<plugin-path>/templates/requirement-template.md` |
| QUICK-XXX | `docs/requirements/templates/quick-template.md` | `<plugin-path>/templates/quick-template.md` |
| PRD | `docs/requirements/templates/prd-template.md` | `<plugin-path>/templates/prd-template.md` |

**模板不存在时终止**：两个路径都不存在时，**必须终止操作**，提示用户执行 `/req:update-template` 恢复模板。不得在无模板的情况下创建或编辑文档。

### 格式规则

1. **章节结构不可变**：不得新增、删除、合并或重命名模板中的章节
2. **层级标题不可变**：章节标题、编号（一、二、三...）必须与模板完全一致
3. **表格格式不可变**：表格的列名、列数必须与模板一致
4. **保留空章节**：未涉及的章节保留模板占位文本，不得删除
5. **仅填充内容**：在模板对应章节的占位文本处填充实际内容

### 适用命令

- `/req:new` - 创建时严格按模板生成
- `/req:new-quick` - 创建时严格按快速模板生成
- `/req:edit` - 编辑时保持模板结构不变
- `/req:upgrade` - 转换时按目标模板结构生成

### 验证机制

`scripts/validate-requirement.sh` 在 Write/Edit 后自动验证：
- REQ-XXX：检查所有章节（元信息、生命周期、一~十）
- QUICK-XXX：检查简化模板的所有章节（元信息、生命周期、问题描述、实现方案、验证方式、开发记录）

## 需求粒度规则

### 基本原则

一个 REQ **对应一个可独立交付的业务功能**，不按技术层拆分，不按开发步骤拆分。

判断标准：**这个需求完成后，用户能感知到一个完整的功能变化吗？** 如果能，粒度合适；如果不能，说明拆得太细。

### 粒度参考

| 粒度 | 是否合适 | 说明 |
|------|---------|------|
| 「用户积分系统」含积分规则+积分查询+积分兑换+积分排行 | 太大 | 拆为多个 REQ |
| 「用户积分-积分规则管理」含 CRUD + 规则校验 | 合适 | 一个完整功能 |
| 「用户积分-积分规则-新增接口」仅一个 API | 太小 | 合并到功能级 REQ |
| 「用户积分-新增 model 层」按技术层拆分 | 错误 | 按功能拆，不按层拆 |

### 拆分建议

**应该拆分的情况：**
- 功能可独立上线、独立使用（如：积分规则管理 vs 积分兑换）
- 不同功能由不同人负责
- 功能之间无强时序依赖（可并行开发）
- 单个需求涉及文件超过 15 个

**不应该拆分的情况：**
- CRUD 属于同一业务实体（增删改查放一个 REQ）
- 功能之间强耦合，必须同时上线
- 拆开后单个 REQ 无法独立验证

### 已有需求的功能扩展

当 REQ 已存在，需要新增功能点时，按以下规则判断是修改原 REQ 还是新建：

**核心问题：去掉这个功能点，原需求还能独立交付吗？**
- **能** → 新建 REQ，通过关联字段链接
- **不能** → 修改原 REQ（`/req:edit`），在功能清单中补充

| 场景 | 建议 | 原因 |
|------|------|------|
| 新功能是原需求的自然延伸，缺少则不完整 | 修改原 REQ | 属于同一个可交付单元 |
| 新功能可独立上线，不依赖原 REQ | 新建 REQ | 独立交付，独立测试 |
| 原 REQ 已 `已完成` | 必须新建 REQ | 已归档需求不应回退状态 |
| 原 REQ 在 `开发中`/`测试中`，新功能会影响已写代码 | 新建 REQ | 避免范围蔓延，保持进度可控 |

**修改原 REQ 时**：使用 `/req:edit`，在变更记录章节说明新增内容。
**新建 REQ 时**：使用 `/req:new`，在关联信息中填写原 REQ 编号。

### 前后端拆分

前后端按类型字段区分，不按 REQ 编号拆分同一端的功能：

```
正确：
  REQ-001 用户积分规则管理-后端    （含 CRUD 全部接口）
  REQ-002 用户积分规则管理-前端    （含 CRUD 全部页面）

错误：
  REQ-001 用户积分规则-新增接口
  REQ-002 用户积分规则-查询接口
  REQ-003 用户积分规则-修改接口
```

### REQ 与 QUICK 的选择

| 场景 | 使用 | 理由 |
|------|------|------|
| 新业务功能（CRUD、新页面） | REQ | 需完整设计和评审 |
| 已有功能的小调整（加字段、改逻辑） | QUICK | 改动范围小、风险低 |
| Bug 修复 | QUICK | 除非修复涉及重构 |
| 重构/优化（不改变功能） | QUICK 或 REQ | 按改动范围判断，超过 5 个文件用 REQ |

### 创建时的 AI 辅助判断

`/req:new` 创建需求时，AI 应根据以上规则辅助判断粒度是否合适：
- 标题过于宽泛（如「XX系统」「XX模块」） → 建议拆分，列出子功能
- 标题过于具体（如「新增XX接口」「修改XX字段」） → 建议合并或改用 QUICK
- 不确定时询问用户业务目标，再给出建议

## 分支策略配置

分支策略存储在 `.claude/settings.local.json` 的 `branchStrategy` 字段中，通过 `/req:branch init` 初始化。

### 配置结构

```jsonc
{
  "branchStrategy": {
    "model": "github-flow",       // github-flow | git-flow | trunk-based
    "repoType": "github",         // github | gitea | other（仓库托管类型）
    "giteaUrl": null,             // Gitea 实例地址（repoType=gitea 时必填，如 https://git.example.com）
    "giteaToken": null,           // Gitea API Token（直接填写 token 值）
    "mainBranch": "main",         // 生产分支
    "developBranch": null,        // git-flow 模式下的开发分支
    "featurePrefix": "feat/",     // REQ-XXX 分支前缀
    "fixPrefix": "fix/",          // QUICK-XXX 分支前缀
    "hotfixPrefix": "hotfix/",    // 紧急修复前缀
    "branchFrom": "main",         // 功能/修复分支的拉取基准
    "mergeTarget": "main",        // 默认合并目标
    "mergeMethod": "merge",       // 合并方式：merge | squash | rebase
    "deleteBranchAfterMerge": true
  }
}
```

### 三种策略预设

| 配置项 | GitHub Flow | Git Flow | Trunk-Based |
|--------|------------|----------|-------------|
| branchFrom | main | develop | main |
| mergeTarget | main | develop | main |
| developBranch | null | develop | null |
| hotfix 合并目标 | main | main + develop | main |

### 读取规则

1. 读取 `.claude/settings.local.json` 的 `branchStrategy`
2. **有配置** → 使用配置值
3. **无配置** → 使用默认行为（`feat/`、`fix/` 前缀，自动检测主分支）

### 各命令的策略消费

| 命令 | 读取的配置 | 用途 |
|------|-----------|------|
| `/req:dev` | `branchFrom`、`featurePrefix`、`fixPrefix` | 创建分支时的基准和前缀 |
| `/req:commit` | `mainBranch`、`developBranch` | 检查当前分支是否合规 |
| `/req:done` | `mergeTarget`、`deleteBranchAfterMerge`、`repoType`、`giteaUrl` | 合并提醒、PR 创建（Gitea）|
| `/req:branch hotfix` | `mainBranch`、`hotfixPrefix` | 从主分支创建紧急修复 |
| `/req:branch status` | `repoType` | 显示仓库托管类型 |

## Issue 拉取规范

`--from-issue=#N` 参数用于从 Git 平台拉取 issue 信息。各命令统一使用以下逻辑：

### 变量来源

| 变量 | 来源 | 说明 |
|------|------|------|
| `GITEA_URL` | `branchStrategy.giteaUrl` | Gitea 实例地址，**必须从配置读取，禁止从 git remote 猜测** |
| `TOKEN` | `branchStrategy.giteaToken` | Gitea API Token |
| `OWNER/REPO` | `git remote get-url origin` 解析 | 从 remote URL 提取，支持 SSH 和 HTTPS 格式 |
| `repoType` | `branchStrategy.repoType` | 决定使用 Gitea API 还是 gh CLI |

### OWNER/REPO 解析

从 `git remote get-url origin` 的结果中提取：
```
ssh://git@gitea.example.com:10022/owner/repo.git  →  owner/repo
git@github.com:owner/repo.git                     →  owner/repo
https://github.com/owner/repo.git                 →  owner/repo
```

去掉 `.git` 后缀，取最后两段路径作为 `OWNER/REPO`。

### 拉取逻辑

**repoType = "gitea"**：
```bash
curl -s "${GITEA_URL}/api/v1/repos/${OWNER}/${REPO}/issues/${N}" \
  -H "Authorization: token ${TOKEN}"
```
- `GITEA_URL` 和 `TOKEN` 未配置时提示：`❌ Gitea 未配置 giteaUrl 或 giteaToken，请先执行 /req:branch init`

**repoType = "github"**：
```bash
gh issue view ${N} --json title,body,number,url,labels
```

**repoType = "other" 或未配置**：
```
❌ 未配置支持的 Git 平台（需 repoType=github 或 gitea）
💡 请先执行 /req:branch init 配置
```

## Issue 与分支/提交的关联

### Issue 编号在分支名中的传递

当需求或任务来自 `--from-issue=#N`，分支名末尾追加 `-iN` 后缀，使 issue 编号可从分支名推断：

```
feat/REQ-001-user-points-i12       ← /req:dev，需求文档 issue=#12
fix/QUICK-003-fix-login-i5         ← /req:dev，快速修复 issue=#5
fix/optimize-order-query-i42       ← /req:do --from-issue=#42
feat/REQ-001-user-points           ← 无 issue 关联，不加后缀
```

**规则**：
- `-iN` 仅当 issue 编号存在时追加（需求文档 `issue` 字段非 `-`，或 `/req:do` 的 `--from-issue` 参数）
- `N` 为纯数字，不带 `#`
- 位于分支名最末尾，不影响 REQ-XXX / QUICK-XXX 的提取

### Issue 编号的读取优先级

各命令需要获取当前 issue 编号时，按以下顺序查找：

| 优先级 | 来源 | 适用场景 |
|-------|------|---------|
| 1 | 需求文档元信息 `issue` 字段 | `/req:done`、`/req:commit`（有需求文档时） |
| 2 | 当前分支名的 `-iN` 后缀 | `/req:commit`、`/req:do` 完成时（无需求文档时） |

**解析正则**：`-i(\d+)$` 匹配分支名末尾的 issue 编号。

### Issue 在 commit message 中的关联

当检测到 issue 编号时，`/req:commit` 在 commit message 末尾追加 `closes #N`：

```
优化: 订单查询添加索引 closes #42
新功能: 实现用户积分规则 (REQ-001) closes #12
```

Git 平台（GitHub / Gitea）会自动将该 commit 关联到 issue，并在合并时关闭 issue。

### Issue 关闭策略

| 场景 | issue 来源 | 关闭方式 | 关闭时机 |
|------|-----------|---------|---------|
| `/req:new --from-issue` | 需求文档 `issue` 字段 | `/req:done` 询问 + API 关闭 | 需求完成时 |
| `/req:new-quick --from-issue` | 需求文档 `issue` 字段 | `/req:done` 询问 + API 关闭 | 需求完成时 |
| `/req:do --from-issue` | 分支名 `-iN` | `/req:do` 完成时询问 + API 关闭 | 任务完成时 |
| 以上所有 | commit message `closes #N` | Git 平台自动关闭 | PR 合并时 |

## CLAUDE.md 架构检查

### 为什么需要

插件不硬编码任何项目架构细节（如分层顺序、目录结构、命名规范）。这些信息由项目自己的 CLAUDE.md 提供。dev-guide、test-guide 等 skill 读取 CLAUDE.md 后适配引导。

### 检查时机

以下命令执行前检查 CLAUDE.md 是否包含架构信息：

| 命令 | 依赖的架构信息 | 缺失时影响 |
|------|--------------|-----------|
| `/req:dev` | 分层架构、目录结构 | 无法生成准确的实现方案和文件清单 |
| `/req:test`、`/req:test_new` | 测试规范、测试目录 | 无法定位测试文件和生成测试代码 |
| `/req:new`（后端/全栈类型） | API 风格 | 无法生成准确的接口需求章节 |

### 检查规则

```python
claude_md_path = "CLAUDE.md"  # 项目根目录
architecture_keywords = [
    "分层架构", "目录结构", "技术栈", "项目架构",
    "Architecture", "Tech Stack", "Project Structure"
]

if os.path.exists(claude_md_path):
    content = read_file(claude_md_path)
    has_architecture = any(kw in content for kw in architecture_keywords)
else:
    has_architecture = False
```

### 缺失时的提醒（非阻断，仅警告）

```
⚠️ CLAUDE.md 中未检测到项目架构描述

   /req:dev 需要架构信息来生成实现方案（分层顺序、目录结构、开发规范）
   /req:test 需要测试规范来定位测试文件和生成测试代码

   💡 添加方式：
   - /req:init <project> --reinit  交互式生成架构片段
   - 手动在 CLAUDE.md 中添加「项目架构」章节

   继续执行，但生成的方案可能不够准确。
```

### 架构片段模板

插件提供预置模板供用户选择（存放在 `templates/claude-md-snippets/`）：

| 模板 | 文件 | 适用场景 |
|------|------|---------|
| Go 后端 | `go-backend.md` | Gin + GORM 分层架构 |
| Java 后端 | `java-backend.md` | Spring Boot 分层架构 |
| 前端 React | `frontend-react.md` | React/Next.js + TypeScript |
| 通用 | `generic.md` | 空白模板，手动填写 |

## 元信息字段

| 字段 | 说明 |
|------|------|
| 编号 | REQ-XXX |
| 类型 | 后端/前端/全栈 |
| 状态 | 当前状态 |
| 模块 | 所属模块 |
| 关联需求 | 前后端对应需求 |
| branch | 开发分支名（/req:dev 首次进入时生成） |
| issue | 关联的 Git 平台 issue 编号（如 `#123`），无关联为 `-`。`/req:new --from-issue` 自动填充，`/req:done` 读取后可选关闭 |
