# 使用教程

本教程以一个完整示例，演示从安装插件到完成需求的全流程。

> 示例场景：为一个后端项目开发「用户积分规则管理」功能。

---

## 一、安装与初始化

### 1.1 安装插件

```bash
# 1. 添加插件仓库为 marketplace
claude plugins marketplace add https://github.com/zhouhao4221/devflow-claude

# 2. 从 marketplace 安装插件
claude plugins install req@devflow

# 验证安装
claude plugins list
```

### 1.2 初始化需求项目

在项目根目录启动 Claude Code，执行：

```
/req:init my-saas
```

这会：
- 创建本地目录 `docs/requirements/`（active/、completed/、modules/、templates/）
- 创建全局缓存 `~/.claude-requirements/projects/my-saas/`
- 生成 PRD 文档模板 `docs/requirements/PRD.md`
- 在 `.claude/settings.local.json` 中记录项目名和角色

### 1.3 CLAUDE.md 架构描述

初始化时会检查项目 CLAUDE.md 是否包含架构信息。如果缺失，引导你选择预置模板：

```
📋 选择项目类型，生成 CLAUDE.md 建议片段：

  1. Go 后端（Gin + GORM 分层架构）
  2. Java 后端（Spring Boot 分层架构）
  3. 前端项目（React/Vue + TypeScript）
  4. 自定义（生成空白模板，手动填写）
  5. 跳过
```

选择后会将架构片段追加到项目 CLAUDE.md，包含技术栈、分层架构表、开发规范、测试规范等。
`/req:dev` 和 `/req:test` 依赖这些信息来生成实现方案和定位测试文件。

> **后续修改**：直接编辑项目 CLAUDE.md 的「项目架构」章节即可。

### 1.4 配置分支策略（可选）

```
/req:branch init
```

选择团队的分支管理策略：
- **GitHub Flow**（推荐）：所有分支从 main 拉，合回 main
- **Git Flow**：功能分支从 develop 拉，合回 develop
- **Trunk-Based**：短期分支，主干开发

然后选择仓库托管类型：
- **GitHub**：`/req:pr` 时提示 `gh pr create` 命令
- **Gitea**：`/req:pr` 时自动调用 Gitea REST API 创建 PR
- **其他**：仅展示 `git merge` 合并命令

配置后 `/req:dev`、`/req:commit`、`/req:done`、`/req:pr` 会自动遵循策略。不配置也能用，使用默认行为。

### 1.5 重新初始化

已有项目补充缺失文件（不覆盖已有内容）：

```
/req:init my-saas --reinit
```

用途：
- 插件更新后补充新增的模板文件
- 补充缺失的目录结构（如 modules/、templates/）
- 重新引导 CLAUDE.md 架构描述
- 恢复被误删的 PRD.md 或模块文档

### 1.6 缓存重建

全局缓存损坏或丢失时，从本地存储重建：

```
/req:cache rebuild
```

其他缓存操作：

```
/req:cache info          # 查看缓存状态
/req:cache clear         # 清理当前项目缓存
/req:cache clear-all     # 清理所有项目缓存
/req:cache export        # 导出缓存数据
```

### 1.7 同步模板（可选）

如果插件更新了模板，可以同步最新版：

```
/req:update-template
```

### 1.8 配置 Gitea Token（Gitea 仓库必须）

如果 `/req:branch init` 选择了 Gitea 仓库类型，需要配置 API Token 才能自动创建 PR。

**获取 Token：**

1. 登录 Gitea → 右上角头像 → **设置**
2. 左侧菜单 → **应用**
3. 「管理 Access Token」→ 输入令牌名称（如 `claude-pr`）
4. 选择权限范围：

| 权限类别 | 权限项 | 必须 | 说明 |
|---------|-------|------|------|
| issue | 读写 | ✅ | PR 本质是 issue 的扩展，创建/查询 PR 需要 |
| repository | 读写 | ✅ | 读取仓库信息、分支列表、推送代码 |
| user | 读取 | 可选 | 用于验证 Token 有效性 |

5. 点击 **生成令牌** → 复制保存（只显示一次）

**配置 Token：**

在项目的 `.claude/settings.local.json` 中，将 token 写入 `branchStrategy.giteaToken` 字段：

```json
{
  "branchStrategy": {
    "repoType": "gitea",
    "giteaUrl": "https://your-gitea.com",
    "giteaToken": "your-token-here"
  }
}
```

> **安全提示**：`settings.local.json` 不应提交到 Git，确认已加入 `.gitignore`。

**验证 Token：**

```bash
curl -s -H "Authorization: token your-token-here" \
  https://your-gitea.com/api/v1/user
```

返回用户信息表示配置成功。

---

## 二、创建需求

### 2.1 正式需求（REQ）

```
/req:new 用户积分规则管理 --type=后端
```

AI 会引导你逐章完善需求文档：

| 章节 | 内容 | 你需要做什么 |
|------|------|------------|
| 一、需求描述 | 背景、目标、客户场景、价值 | 描述业务背景，AI 帮你结构化 |
| 二、功能清单 | 可勾选的功能点列表 | 确认功能范围 |
| 三、业务规则 | 校验规则、状态转换、权限 | 补充业务细节 |
| 四、使用场景 | 角色、流程、异常处理 | 描述典型操作流程 |
| 五、接口需求 | 接口能力、输入输出、业务语义 | 确认接口需求 |
| 六、测试要点 | 需要验证的场景 | 补充测试关注点 |

完成后生成 `docs/requirements/active/REQ-001-用户积分规则管理.md`。

### 2.2 快速修复（QUICK）

适合小 bug 或小功能，流程更轻量：

```
/req:new-quick 修复积分计算精度丢失
```

QUICK 模板更简洁：问题描述 → 实现方案 → 验证方式。

### 2.3 需求拆分建议

不确定粒度是否合适？用拆分分析：

```
/req:split 用户积分系统
```

AI 会分析粒度并建议拆分方案（只读，不创建文档）。

### 2.4 从 Git issue 创建需求

如果团队使用 Gitea / GitHub issue 作为需求入口，可以直接从 issue 创建需求文档，省去二次录入：

```
/req:new --from-issue=#12           # 正式需求
/req:new-quick --from-issue=#5      # 快速修复
/req:do --from-issue=#42            # 无文档，仅把 issue 内容作为描述跑智能开发
```

**AI 的行为**：
1. 按 `branchStrategy.repoType` 调用对应 API 拉取 issue（Gitea → REST API + `giteaToken`；GitHub → `gh issue view`）
2. issue 标题作为需求默认标题，正文作为「问题与现状」的初始输入
3. 创建的文档元信息 `issue` 字段记录 `#N`，用于后续自动关联

**Gitea 仓库的前提**：`branchStrategy.giteaUrl` 和 `giteaToken` 必须配置（见 1.8）。AI **不会**从 git remote SSH 地址猜测 HTTPS URL，必须走配置。

#### issue 与分支/提交的自动关联

有 issue 关联时，整条链路都会自动带上 issue 编号：

| 环节 | 表现 |
|------|------|
| `/req:dev` 创建分支 | 末尾自动追加 `-iN`（如 `feat/REQ-001-user-points-i12`） |
| `/req:commit` 提交代码 | commit message 末尾自动追加 `closes #N`（PR 合并时 Git 平台自动关闭 issue） |
| `/req:done` 归档 | 询问是否通过 API 直接关闭 issue |
| `/req:do --from-issue` | 创建带 `-iN` 的分支；完成时询问关闭 issue |

**读取优先级**：需求文档 `issue` 字段 > 分支名 `-iN` 后缀。这样即使是无文档的 `/req:do`，commit 和 done 也能从分支名推断 issue 编号。

---

## 三、评审流程

> QUICK 跳过评审，可直接进入开发。

### 3.1 提交评审

```
/req:review
```

状态从「草稿」变为「待评审」。

### 3.2 评审决议

```
/req:review pass     # 通过，进入「评审通过」
/req:review reject   # 驳回，回到「草稿」
```

驳回后需要 `/req:edit` 修改再重新提审。

---

## 四、开发阶段

### 4.1 启动开发

```
/req:dev
```

执行流程：

```
前置检查（REQ 必须通过评审）
    ↓
分支管理（自动创建 feat/REQ-001-user-points-rule）
    ↓
读取 CLAUDE.md 项目架构（分层顺序、目录结构）
    ↓
加载需求上下文（章节一~六）
    ↓
生成实现方案（Plan Mode）
    ├── 10.1 数据模型
    ├── 10.2 API 设计（基于接口需求 + 项目代码生成）
    ├── 10.3 文件改动清单（按 CLAUDE.md 分层架构列出）
    └── 10.4 实现步骤（按 CLAUDE.md 分层顺序拆解）
    ↓
确认方案 → 状态改为「开发中」
    ↓
按 CLAUDE.md 分层架构逐步实现
```

### 4.2 分支管理

首次执行 `/req:dev` 时，AI 自动：

1. 检查工作区是否干净（有未提交改动会终止）
2. 读取分支策略配置（如已配置 `/req:branch init`）
3. 从需求标题生成英文分支名，供你确认：
   ```
   将创建开发分支：feat/REQ-001-user-points-rule
   基于分支：main（来源：branchStrategy.branchFrom）
   ```
4. 确认后创建分支并写入需求文档的 `branch` 字段

再次执行 `/req:dev` 时，直接切换到已记录的分支。

分支命名规则（前缀可通过策略配置自定义）：
- REQ → `feat/REQ-XXX-<english-slug>[-iN]`
- QUICK → `fix/QUICK-XXX-<english-slug>[-iN]`
- `/req:do --from-issue` → `<prefix><slug>-iN`（前缀由 AI 分析意图决定）
- 紧急修复 → `hotfix/<english-slug>`（通过 `/req:branch hotfix` 创建）
- `-iN`：可选的 issue 后缀（如 `-i12`），当需求关联了 Git 平台 issue 时自动追加，用于后续命令识别关联（详见 2.8）

### 4.2.1 分支策略命令

```
/req:branch              # 查看当前策略和分支状态
/req:branch init         # 交互式配置分支策略 + 仓库类型
/req:branch status       # 查看策略配置和各需求分支状态
/req:branch hotfix 描述  # 从主分支创建紧急修复分支
```

### 4.2.2 创建 PR

开发完成后，创建 PR：

```
/req:pr              # 根据当前分支自动匹配需求，创建 PR
/req:pr REQ-001      # 指定需求创建 PR
```

根据 `/req:branch init` 配置的仓库类型：
- **Gitea**：自动调用 Gitea REST API 创建 PR（需配置 `giteaToken`，见 1.8）
- **GitHub**：调用 `gh` CLI 创建 PR
- **其他**：推送分支到远程，展示合并命令

Git Flow 的 hotfix 分支会自动创建两个 PR（→ main + → develop）。

### 4.2.3 PR 审查与合并

PR 创建后，使用 AI 代码审查和合并：

```
/req:review-pr              # 查看 PR 状态
/req:review-pr review       # AI 代码审查
/req:review-pr merge        # 合并 PR
```

**审查流程：**
1. AI 获取 PR diff，逐文件审查（正确性、安全性、规范、需求匹配）
2. 问题分三级：🔴 阻塞（必须修复）、🟡 建议、🔵 信息
3. 审查报告自动提交为 PR 评论（Gitea/GitHub 网页可见）
4. 无阻塞问题 → 可执行 merge

**合并方式：** 读取 `branchStrategy.mergeMethod` 配置（默认 `merge`），支持 `merge` / `squash` / `rebase`。

### 4.2.4 智能开发（/req:do）

对于优化、重构、升级等无需创建需求文档的任务，使用智能开发命令：

```
/req:do 优化订单查询性能
/req:do 重构用户服务层
/req:do 升级 Go 到 1.23
/req:do 统一错误码格式
```

AI 自动：
1. **分析意图** — 判断类型（优化/重构/升级/规范/小功能/修复）和规模
2. **搜索代码** — 定位相关文件，生成修改方案
3. **确认方案** — 用户确认后创建分支（`improve/`、`feat/`、`fix/` 按类型自动选择）
4. **执行修改** — 按方案修改代码

规模较大时会建议切换到 `/req:new-quick` 或 `/req:new`。

**与 `/req:fix` 的区别：**
- `/req:fix` — 专门修 bug，AI 会做根因分析
- `/req:do` — 优化/重构/升级等非 bug 场景，AI 分析意图后选择合适流程

### 4.3 继续开发

中断后再次进入，会恢复进度：

```
/req:dev REQ-001
```

加 `--reset` 可以重新生成实现方案：

```
/req:dev REQ-001 --reset
```

### 4.4 规范提交

开发过程中使用规范提交，自动关联需求编号：

```
/req:commit
```

AI 分析改动内容，生成 Conventional Commits 格式的提交信息：

```
新功能: 实现积分规则 CRUD 接口 (REQ-001)
```

---

## 五、测试阶段

### 5.1 综合测试

```
/req:test
```

包含回归测试 + 新功能测试，状态改为「测试中」。

### 5.2 分步测试

```
/req:test_regression    # 运行已有自动化测试，生成回归报告
/req:test_new           # 为新功能创建测试用例（UT/API/E2E）
```

---

## 六、完成归档

```
/req:done
```

流程：
1. 检查测试完成情况
2. 展示完成摘要（功能点、测试点、文件统计、时间线）
3. 确认后归档：`active/REQ-001-*.md` → `completed/`
4. 更新 PRD 索引
5. 提醒合并开发分支

---

## 七、查看与管理

### 7.1 需求列表

```
/req                          # 列出所有需求
/req --type=后端              # 按类型筛选
/req --module=用户            # 按模块筛选
/req --type=前端 --module=用户 # 组合筛选
```

### 7.2 查看详情

```
/req:show REQ-001     # 查看需求完整内容（只读）
/req:status REQ-001   # 查看状态和进度
```

### 7.3 编辑需求

```
/req:edit REQ-001     # 修改已有需求
```

---

## 八、模块管理

模块是按功能域划分的业务文档，帮助 AI 理解上下文。

```
/req:modules                  # 列出所有模块
/req:modules new 用户         # 创建用户模块文档
/req:modules show 用户        # 查看模块详情
```

模块文档描述：职责边界、核心功能、数据模型、API 概览、关键文件路径。

---

## 九、PRD 管理

PRD 是项目级的产品需求文档，一个项目一份。

```
/req:prd                      # 查看 PRD 状态概览，分析各章节填充情况
/req:prd-edit                 # 编辑 PRD，AI 辅助补充内容
/req:prd-edit 产品概述         # 编辑指定章节
```

PRD 的「需求追踪」章节会自动维护：
- `/req:new` 时追加记录
- `/req:done` 时更新状态和完成日期

---

## 十、版本管理

### 10.1 生成版本说明

```
/req:changelog v1.2.0                          # 自动检测范围
/req:changelog v1.2.0 --from=v1.1.0 --to=HEAD # 指定范围
```

AI 根据 Git 提交记录分类生成结构化 Changelog。

### 10.2 快速修复升级

QUICK 做到一半发现范围变大，可以升级为正式需求：

```
/req:upgrade QUICK-003
```

---

## 十一、跨仓库协作

适用于前后端分仓的项目。

### 主仓库（后端）

```
# 初始化项目
/req:init my-saas

# 正常创建和管理需求
/req:new 用户积分-后端 --type=后端
```

### 关联仓库（前端）

```
# 绑定到同一项目
/req:use my-saas

# 可以查看需求（只读）
/req
/req:show REQ-001

# 可以基于需求开发（从缓存读取）
/req:dev REQ-002
```

关联仓库的角色为 `readonly`：
- 可以查看和读取需求
- 可以基于已完成需求开发
- 不能创建、编辑、变更需求状态

### 11.1 规范文档共享

主仓库可创建规范文档（数据类型定义、接口契约、错误码等），只读仓库可实时查阅：

**主仓库（后端）：**

```
/req:specs new 订单数据类型        # 创建规范文档
/req:specs edit order-types       # 编辑
/req:specs                        # 列出所有规范
```

**只读仓库（前端）：**

```
/req:specs                        # 查看规范列表
/req:specs show order-types       # 查看订单数据类型定义
```

规范文档存储在 `docs/requirements/specs/`，通过缓存自动同步。后端修改后，前端下次查看即为最新版本。

典型用途：
- 后端定义数据类型 → 前端查阅字段定义
- 统一错误码规范 → 前后端各自实现
- 接口契约约定 → 保证前后端一致

---

## 十二、完整流程图

```
                    创建需求
                /req:new 标题
                      │
                      ▼
               ┌─────────────┐
               │   📝 草稿    │ ← /req:edit 修改
               └──────┬──────┘
                      │ /req:review
                      ▼
               ┌─────────────┐
               │  👀 待评审   │
               └──────┬──────┘
                      │ /req:review pass
                      ▼
               ┌─────────────┐
               │ ✅ 评审通过  │
               └──────┬──────┘
                      │ /req:dev（自动创建分支）
                      ▼
               ┌─────────────┐
               │  🔨 开发中   │ ← /req:commit 提交代码
               │             │ ← /req:pr 创建 PR
               │             │ ← /req:review-pr review 审查
               │             │ ← /req:review-pr merge 合并
               └──────┬──────┘
                      │ /req:test
                      ▼
               ┌─────────────┐
               │  🧪 测试中   │
               └──────┬──────┘
                      │ /req:done（提醒合并分支）
                      ▼
               ┌─────────────┐
               │  🎉 已完成   │ → archived to completed/
               └─────────────┘
```

---

## 常用命令速查

| 场景 | 命令 |
|------|------|
| 看看有哪些需求 | `/req` |
| 创建正式需求 | `/req:new 标题 --type=后端` |
| 创建小修复（有文档） | `/req:new-quick 标题` |
| 轻量修复（无文档） | `/req:fix 问题描述` |
| 智能开发（优化/重构） | `/req:do 描述` |
| 编辑需求 | `/req:edit` |
| 提交评审 | `/req:review` |
| 通过评审 | `/req:review pass` |
| 启动开发 | `/req:dev` |
| 提交代码 | `/req:commit` |
| 创建 PR | `/req:pr` |
| AI 代码审查 | `/req:review-pr review` |
| 合并 PR | `/req:review-pr merge` |
| 运行测试 | `/req:test` |
| 完成归档 | `/req:done` |
| 查看 PRD | `/req:prd` |
| 生成 Changelog | `/req:changelog v1.0.0` |
| 配置分支策略 | `/req:branch init` |
| 查看分支状态 | `/req:branch status` |
| 紧急修复 | `/req:branch hotfix 描述` |
| 重新初始化 | `/req:init my-project --reinit` |
| 缓存重建 | `/req:cache rebuild` |
| 查看规范文档 | `/req:specs show <名称>` |
| 创建规范文档 | `/req:specs new <名称>` |
