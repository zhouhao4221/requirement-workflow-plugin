---
description: 规范提交 - 生成 Conventional Commits 格式的 Git 提交
---

# 规范提交

生成符合 Conventional Commits 规范的 Git 提交，自动关联当前需求编号，便于后续 `/req:changelog` 生成版本说明。

> 此命令**不受仓库角色限制**，readonly 仓库也可执行。
> 不触发缓存同步。

## 命令格式

```
/req:commit [消息]
```

**示例：**
- `/req:commit` — 交互式选择类型并生成提交
- `/req:commit 实现部门渠道关联` — 自动分析变更并生成提交

---

## 执行流程

> **⚠️ 重要：步骤 1（分支检查）必须最先执行，在任何 git add / git commit 之前完成。**

### 1. 🔀 分支保护检查（最高优先级，第一步执行）

**本步骤必须在 git add 之前执行。** 读取 `.claude/settings.local.json` 的 `branchStrategy`，未配置时跳过本步骤。

**🚫 核心规则：保护分支上严格禁止直接提交，必须先切换到功能分支。**

**执行动作：**

1. 读取当前分支：`git branch --show-current`
2. 读取策略配置中的 `mainBranch`、`developBranch`、`branchFrom`
3. **判断当前分支是否为保护分支**：

| 条件 | 是否保护分支 |
|------|------------|
| 当前分支 == `mainBranch`（如 `main`、`master`） | **是** |
| 当前分支 == `developBranch`（如 `develop`） | **是** |
| 其他分支（`feat/*`、`fix/*`、`hotfix/*` 等） | 否，跳到步骤 2 |

4. **如果在保护分支上 → 禁止提交，必须切换分支**：

   先扫描活跃需求（状态为「开发中」或「测试中」）：

   - **有 1 个活跃需求** → 自动切换到该需求分支（见下方步骤 5）
   - **有多个活跃需求** → 展示列表让用户选择（无"跳过"选项）：
     ```
     🚫 当前在保护分支 <current_branch>，不允许直接提交。请选择需求分支：

       1. REQ-001 用户积分规则管理
       2. REQ-002 订单状态流转

     请选择：
     ```
   - **无活跃需求** → 拒绝提交，提示用户先创建分支：
     ```
     🚫 当前在保护分支 <current_branch>，不允许直接提交。

     💡 请先创建功能分支：
       git checkout -b <分支名>
     或通过需求创建分支：
       /req:new → /req:dev
     ```
     **终止流程，不执行后续步骤。**

5. **切换/创建分支**（用户选择需求后，或只有一个活跃需求时自动执行）：

   **需求已有 branch 字段（非空且非 `-`）→ 切换到已有分支：**
   ```bash
   git stash
   git checkout <req.branch>
   git stash pop
   ```
   输出：`🔀 已从 <current_branch> 切换到 <req.branch>`

   **需求无 branch 字段（为 `-` 或缺失）→ 创建新分支：**
   ```bash
   # 分支命名：<prefix><REQ-ID>-<english-slug>
   # 例：feat/REQ-001-user-points、fix/QUICK-003-login-error
   git stash
   git checkout -b <new_branch> <branchFrom>
   git stash pop
   # 更新需求文档的 branch 字段为 <new_branch>
   ```
   输出：`🔀 已从 <current_branch> 创建并切换到 <new_branch>`

**各场景行为总结：**

| 当前分支 | 有活跃需求 | 行为 |
|---------|-----------|------|
| `main`（mainBranch） | 1个，已有需求分支 | 🔀 stash → 切换到需求分支 → stash pop |
| `main`（mainBranch） | 1个，无需求分支 | 🔀 stash → 创建需求分支 → stash pop |
| `main`（mainBranch） | 多个 | 让用户选择需求（无跳过选项） |
| `main`（mainBranch） | 无 | 🚫 拒绝提交，提示创建分支 |
| `develop`（developBranch） | 1个，已有需求分支 | 🔀 stash → 切换到需求分支 → stash pop |
| `develop`（developBranch） | 1个，无需求分支 | 🔀 stash → 创建需求分支 → stash pop |
| `develop`（developBranch） | 多个 | 让用户选择需求（无跳过选项） |
| `develop`（developBranch） | 无 | 🚫 拒绝提交，提示创建分支 |
| hotfix/* 分支 | — | 正常继续，自动建议「修复」类型 |
| feat/REQ-XXX-* | — | 正常继续，自动关联对应 REQ |
| fix/QUICK-XXX-* | — | 正常继续，自动关联对应 QUICK |

### 2. 检查工作区状态

```bash
git status --short
git diff --cached --stat
```

**无变更时：**
```
❌ 没有可提交的变更

💡 请先暂存文件：
- git add <file>       暂存指定文件
- git add -A           暂存所有变更
```

**有未暂存变更时：**
自动将所有变更暂存（`git add -A`），展示暂存结果：

```
📁 已暂存所有变更：
  M  internal/sys/biz/dept_channel.go
  A  internal/sys/model/sys_dept_channel_model.go
  M  internal/sys/controller/v1/sys_dept.go
  M  internal/sys/router.go
```

### 3. Code Review 提醒

提交前展示代码审查提醒（信息展示，不等待回复）：

```
⚠️ 提交前请确认已完成 Code Review
   检查要点：逻辑正确性、安全隐患、错误处理、代码规范、调试代码清理
```

### 4. 检测当前需求

**优先从分支名匹配**（步骤 1 已获取当前分支信息）：

```python
current_branch = git("branch --show-current")

# 优先：从分支名提取需求编号
import re
branch_match = re.search(r'(REQ-\d+|QUICK-\d+)', current_branch)
if branch_match:
    CURRENT_REQ = branch_match.group(1)
else:
    # 回退：扫描活跃需求
    PROJECT = read_settings("requirementProject")
    ROLE = read_settings("requirementRole")

    if ROLE == "readonly":
        active_dir = f"~/.claude-requirements/projects/{PROJECT}/active/"
    else:
        active_dir = "docs/requirements/active/"

    active_reqs = find_requirements(active_dir, status=["开发中", "测试中"])

    if len(active_reqs) == 1:
        CURRENT_REQ = active_reqs[0]
    elif len(active_reqs) > 1:
        print("检测到多个活跃需求：")
        for i, req in enumerate(active_reqs):
            print(f"  {i+1}. {req}")
        print(f"  {len(active_reqs)+1}. 不关联需求")
    else:
        CURRENT_REQ = None
```

### 5. 分析变更内容

读取 `git diff --cached` 的内容，分析暂存的代码变更：

- 变更性质（新增功能、修复问题、重构等）
- 变更描述（从代码差异中提炼）

### 6. 生成提交信息

#### 6.1 选择提交类型

如果用户未提供消息，交互式选择：

```
📝 选择提交类型：

  1. 新功能     新增功能
  2. 修复       问题修复
  3. 重构       代码重构
  4. 优化       性能优化
  5. 文档       文档更新
  6. 测试       测试相关
  7. 构建       构建/工具/依赖
  8. 样式       代码格式（不影响逻辑）
```

如果用户已提供消息，根据变更内容和消息自动推断类型。

#### 6.2 组装提交消息

**格式：**
```
前缀: 描述 (REQ-XXX)
```

**规则：**
- `前缀`：必填，中文类型前缀
- 描述：简洁的中文描述
- `(REQ-XXX)`：自动追加当前需求编号（如有）

**前缀映射：**

| 前缀 | 含义 | Changelog 分类 |
|------|------|---------------|
| `新功能` | 新增功能 | 新功能 (Features) |
| `修复` | 问题修复 | 问题修复 (Bug Fixes) |
| `重构` | 代码重构 | 重构优化 (Refactoring) |
| `优化` | 性能优化 | 性能优化 (Performance) |
| `文档` | 文档更新 | 文档更新 (Documentation) |
| `测试` | 测试相关 | 测试 (Tests) |
| `构建` | 构建/工具/依赖 | 其他变更 (Others) |
| `样式` | 代码格式 | 其他变更 (Others) |

**示例：**
```
新功能: 实现部门渠道关联 (REQ-001)
修复: 订单渠道过滤逻辑错误 (REQ-001)
重构: 部门服务层代码 (QUICK-003)
文档: 更新 API 文档
构建: 升级依赖版本
```

### 7. 确认并提交

展示完整提交预览：

```
📋 提交预览：

  类型：新功能
  描述：实现部门渠道关联
  关联：REQ-001

  完整消息：
  新功能: 实现部门渠道关联 (REQ-001)

  变更文件（4）：
  A  internal/sys/model/sys_dept_channel_model.go
  A  internal/sys/store/sys_dept_channel_store.go
  A  internal/sys/biz/dept_channel.go
  M  internal/sys/router.go

```

展示预览后直接执行提交（Hook 会弹出原生确认对话框）：

```bash
git commit -m "新功能: 实现部门渠道关联 (REQ-001)"
```

### 8. 提交结果

```
✅ 提交成功！

  commit abc1234
  新功能: 实现部门渠道关联 (REQ-001)

  4 files changed, 156 insertions(+), 3 deletions(-)

💡 是否创建 PR？
- /req:pr           创建 PR
- 继续开发          稍后再说
```

---

## Breaking Change 支持

如果变更包含破坏性改动，在前缀后添加 `!` 标记：

```
新功能!: 重构部门 API 返回结构 (REQ-005)
```

交互式流程中增加确认：

```
如果变更涉及 API 返回结构变更、数据库 schema 变更等，自动标记为 Breaking Change。
```

---

## 多行提交消息

对于需要详细说明的提交，支持添加 body：

```
新功能: 实现部门渠道关联 (REQ-001)

- 新增 sys_dept_channel 表及 Model/Store 层
- 实现渠道范围校验逻辑
- 添加获取可选渠道接口
```

当变更涉及多个文件或逻辑复杂时，自动添加 body 说明。

---

## 与 Changelog 的对应关系

本命令生成的提交消息使用中文前缀，`/req:changelog` 可直接解析：

| 提交格式 | Changelog 分类 |
|---------|---------------|
| `新功能: 描述 (REQ-XXX)` | 新功能 (Features) |
| `修复: 描述 (REQ-XXX)` | 问题修复 (Bug Fixes) |
| `重构: 描述` | 重构优化 (Refactoring) |
| `优化: 描述` | 性能优化 (Performance) |
| `文档: 描述` | 文档更新 (Documentation) |
| `测试: 描述` | 测试 (Tests) |
| `构建/样式: 描述` | 其他变更 (Others) |

**需求编号关联**：commit message 中的 `(REQ-XXX)` / `(QUICK-XXX)` 会被 changelog 自动提取并归入「关联需求」章节。

## 用户输入

$ARGUMENTS
