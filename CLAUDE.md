# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

这是一个 Claude Code 插件，用于需求全流程工作流管理。提供命令、技能和钩子来管理软件需求从草稿到完成的完整生命周期。

## 架构

插件遵循 Claude Code 的插件结构：

```
.claude-plugin/plugin.json    # 插件清单和配置
commands/                     # 命令定义（Markdown 文件）
skills/                       # 自动触发的 AI 技能（SKILL.md 文件）
hooks/hooks.json             # 工具拦截的事件钩子
scripts/                     # 验证和工具脚本
templates/                   # 需求文档模板
```

### 存储架构（本地优先 + 缓存同步）

需求采用**双存储**架构，本地为主、缓存为辅：

**1. 项目本地存储（主存储）**
- 存储目录：`docs/requirements/`
- 模块文档：`docs/requirements/modules/`
- 进行中的需求：`docs/requirements/active/`
- 已完成的需求：`docs/requirements/completed/`
- 需求索引：`docs/requirements/INDEX.md`（自动生成）
- 模板文件：`docs/requirements/template.md`
- 优势：纳入 git 版本控制，团队可审查

**2. 全局缓存（同步副本）**
- 缓存目录：`~/.claude-requirements/`
- 项目缓存路径：`~/.claude-requirements/projects/<project-name>/`
- 仓库绑定配置：`.claude/settings.local.json` 中的 `requirementProject` 和 `requirementRole`
- 优势：支持跨仓库共享同一套需求

**仓库角色**（`requirementRole` 字段）：
- `primary`：主仓库，拥有本地 `docs/requirements/`，可读写，修改后自动同步到缓存
- `readonly`：只读仓库，无本地存储，仅从缓存读取需求，不可创建/编辑/变更状态

**更新策略（强制自动同步）：**
1. 创建/修改需求 → 先写入本地 `docs/requirements/`（仅 `primary` 角色）
2. 本地写入成功 → **强制自动同步**到全局缓存（通过 PostToolUse Hook，无需用户确认）
3. 读取需求 → `primary` 优先读本地，`readonly` 直接读缓存
4. **只读仓库禁止写操作**：`readonly` 仓库不执行创建、编辑、状态更新、缓存同步
5. **以本地为准**：同步时直接用本地版本覆盖缓存，不进行冲突检测
6. **触发工具**：Write 和 Edit 工具都会触发缓存同步（包括 active/ 和 completed/ 目录，仅 `primary`）

### 命令结构

命令通过 `/req` 子命令模式调用：

**需求管理命令（编号可选，自动识别当前需求）：**
- `/req` - 列出所有需求
- `/req:new [标题] [--type=后端|前端|全栈]` - 创建新需求
- `/req:new-quick [标题]` - 创建快速修复（小bug/小功能）
- `/req:upgrade <QUICK-XXX>` - 将快速修复升级为正式需求
- `/req:edit` - 编辑需求
- `/req:review [pass|reject]` - 提交/通过评审
- `/req:dev` - 启动开发
- `/req:test` - 综合测试（回归 + 新测试）
- `/req:test_regression` - 运行已有自动化测试用例
- `/req:test_new` - 为新功能创建测试用例（UT/API/E2E）
- `/req:done` - 完成需求
- `/req:status` - 查看需求状态
- `/req --type=后端` - 按类型筛选需求列表

**模块管理命令：**
- `/req:modules` - 列出所有模块及其需求概览
- `/req:modules new <模块名>` - 创建新模块文档
- `/req:modules show <模块名>` - 查看模块详情
- `/req --module=<模块名>` - 按模块筛选需求列表

**项目管理命令（全局缓存模式）：**
- `/req:init <project-name>` - 初始化项目，创建全局缓存
- `/req:use <project-name>` - 切换当前仓库绑定的项目
- `/req:projects` - 列出所有项目
- `/req:migrate <project-name>` - 将本地需求迁移到全局缓存
- `/req:cache <action>` - 缓存管理（info/clear/clear-all/rebuild/export）
- `/req:update-template [模板名] [--force]` - 将插件最新模板同步到项目本地

### 技能（自动触发）

- `requirement-analyzer` - 创建/编辑需求时触发，帮助完善文档各章节
- `dev-guide` - 执行 `/req:dev` 时触发，按分层架构引导代码实现
- `code-impact-analyzer` - 需求变更时触发，分析受影响的代码
- `test-guide` - 执行测试命令时触发，支持两种模式：
  - `/req:test_regression` - 运行已有自动化测试，生成回归报告
  - `/req:test_new` - 创建新测试用例（UT/API/E2E）

### 钩子

在 `hooks/hooks.json` 中配置的前置/后置钩子：
- **PostToolUse（Write/Edit 后）**：
  - `validate-requirement.sh` - 验证需求文档格式
  - `sync-cache.sh` - **强制自动同步**到全局缓存（无需用户确认，以本地为准）

**缓存同步触发规则**：

仅当命令涉及需求文档修改时触发缓存同步：

| 触发同步的命令 | 操作说明 |
|--------------|---------|
| `/req:new` | 创建需求文档 |
| `/req:new-quick` | 创建快速修复文档 |
| `/req:edit` | 编辑需求文档 |
| `/req:review` | 更新评审状态 |
| `/req:dev` | 更新开发状态和进度 |
| `/req:test` | 更新测试状态和结果 |
| `/req:done` | 完成归档（移动到 completed/） |
| `/req:upgrade` | 升级 QUICK 为 REQ |
| `/req:modules new` | 创建模块文档 |

不触发同步的命令（只读操作）：`/req`、`/req:status`、`/req:projects`、`/req:cache`、`/req:use`、`/req:init`、`/req:migrate`、`/req:test_regression`、`/req:test_new`、`/req:update-template`

**同步范围**：`docs/requirements/` 目录下的 REQ-XXX、QUICK-XXX 需求文档及模块文档（modules/），其他文件（INDEX.md、template.md）不同步。

## 需求生命周期状态

```
📝 草稿 → 👀 待评审 → ✅ 评审通过 → 🔨 开发中 → 🧪 测试中 → 🎉 已完成
```

### 状态更新确认机制

不同命令对状态更新有不同的确认要求：

| 命令 | 状态变更 | 确认机制 | 说明 |
|-----|---------|---------|------|
| `/req:review pass/reject` | 待评审 → 评审通过/驳回 | 显式参数即为确认 | 必须带参数执行 |
| `/req:dev` | 评审通过 → 开发中 | 首次进入时自动更新 | REQ 必须先通过评审，QUICK 跳过 |
| `/req:test` | 开发中 → 测试中 | 执行命令即为确认 | 自动更新状态 |
| `/req:done` | 测试中 → 已完成 | **必须明确确认（y/n）** | 最终状态，必须用户确认 |

**重要规则**：
1. 所有状态更新操作都遵循"本地优先"原则，若本地不存在需求文档则跳过更新
2. **开发前检查**：
   - 正式需求 (REQ-XXX)：必须先通过评审，草稿或待评审状态会被拒绝
   - 快速修复 (QUICK-XXX)：跳过评审，方案确认后可直接开发

## 跨仓库共享需求

支持前后端等多个仓库共享同一套需求：

```
~/backend/                         # 后端仓库（主仓库）
├── docs/requirements/             # 本地存储（主存储，纳入 git）
│   ├── modules/                   # 模块文档
│   │   ├── user.md
│   │   └── order.md
│   ├── active/
│   │   └── REQ-001-用户积分.md
│   ├── completed/
│   └── INDEX.md                   # 需求索引
└── .claude/settings.local.json    # { "requirementProject": "my-saas-product", "requirementRole": "primary" }

~/frontend/                        # 前端仓库（关联仓库）
└── .claude/settings.local.json    # { "requirementProject": "my-saas-product", "requirementRole": "readonly" }

~/.claude-requirements/            # 全局缓存（同步副本）
└── projects/
    └── my-saas-product/
        ├── modules/               # 模块文档同步
        ├── active/
        │   └── REQ-001-用户积分.md
        ├── completed/
        └── INDEX.md
```

**使用流程：**
1. 在主仓库执行 `/req:init my-saas-product` 初始化项目
2. 创建需求时：先写入 `docs/requirements/` → 同步到全局缓存
3. 在其他仓库执行 `/req:use my-saas-product` 绑定同一项目
4. 关联仓库读取需求时从全局缓存获取

## 模块与需求关系

**模块（Module）**：按技术架构划分的功能域，相对稳定
- 描述模块职责、业务规则、核心功能
- 记录关键文件路径和 API 概览
- 作为 AI 理解业务上下文的入口

**需求（Requirement）**：按业务目标划分的可交付单元，不断新增
- 可能涉及一个或多个模块
- 有明确的完成态和生命周期
- 每个需求在元信息中标记所属模块
- **粒度规则**：一个 REQ 对应一个可独立交付的业务功能，不按技术层或开发步骤拆分（详见 `_common.md` 需求粒度规则）

**AI 使用场景：**
1. 开发新功能时，先读取模块文档了解业务上下文
2. 通过索引快速定位相关需求
3. 按模块筛选需求，聚焦特定领域

## PRD 与 REQ 的关系

**PRD**（产品需求文档）是项目级的，一个项目一份，描述产品愿景、功能规划、技术选型。
**REQ** 是功能级的，从 PRD 派生，每个可独立交付的业务功能一个 REQ。

```
PRD.md（产品规划）
├── 9. 需求追踪              ← 自动维护的索引
│   ├── REQ-001 用户积分规则管理-后端   草稿
│   ├── REQ-002 用户积分规则管理-前端   开发中
│   └── REQ-003 积分兑换-后端          已完成
```

**自动维护**：
- `/req:new` 创建需求时 → 在 PRD.md「需求追踪」章节追加记录
- `/req:done` 完成需求时 → 更新对应记录的状态和完成日期

## REQ 模板章节划分

REQ 模板分为三个区域，在不同阶段填充：

| 区域 | 章节 | 填充阶段 | 填充方式 |
|------|------|---------|---------|
| 需求定义 | 一~六（需求描述、功能清单、业务规则、使用场景、API 设计、测试要点） | `/req:new` | 用户 + AI |
| 流程记录 | 七~九（评审记录、变更记录、关联信息） | 各命令自动 | 自动 |
| 实现方案 | 十（数据模型、文件改动清单、实现步骤） | `/req:dev` | AI 分析代码后生成 |

## 前后端需求管理

前后端需求**分开管理**，通过关联字段链接：

**需求类型：**
- `后端` - 仅涉及后端 API、数据库、业务逻辑
- `前端` - 仅涉及前端页面、组件、交互
- `全栈` - 前后端都涉及（适合小功能）

**典型流程：**
```
1. 产品提出业务需求
2. 拆分为后端需求 + 前端需求
3. 各自独立开发、评审
4. 通过「关联需求」字段互相引用
5. 联调测试
```

**示例：**
```
REQ-001 用户积分-后端    类型=后端  关联=REQ-002
REQ-002 用户积分-前端    类型=前端  关联=REQ-001
```

**筛选命令：**
```bash
/req --type=后端              # 只看后端需求
/req --type=前端 --module=用户  # 前端 + 用户模块
```

## 目标项目架构

本插件针对分层架构的 Go 项目设计：
```
Model → Store → Biz → Controller → Router
```

文件命名规范：kebab-case（如 `sys-dept-channel.go`）