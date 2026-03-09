# Requirement Workflow Plugin

Claude Code 插件 — 需求全流程工作流管理，覆盖从需求分析、评审、开发、测试到归档的完整生命周期。

## 功能特性

- **完整生命周期**：草稿 → 待评审 → 评审通过 → 开发中 → 测试中 → 已完成
- **双轨需求**：正式需求（REQ）和快速修复（QUICK）两套流程
- **智能分析**：AI 辅助完善需求文档、生成实现方案、分析变更影响
- **开发引导**：按项目分层架构（Model → Store → Biz → Controller → Router）逐层引导
- **测试管理**：回归测试 + 新建测试用例（UT/API/E2E）
- **PRD 管理**：产品需求文档编辑，支持从现有需求反推内容
- **跨仓库共享**：前后端多仓库共享同一套需求（本地优先 + 全局缓存）
- **规范提交**：自动关联需求编号的 Conventional Commits
- **版本说明**：基于 Git 记录自动生成 Changelog

## 安装

> 要求：Claude Code v1.0.33 或更高版本（推荐 v2.1+）

### 从 GitHub 安装（推荐）

```bash
claude plugin add github:zhouhao4221/requirement-workflow-plugin
```

### 本地安装（开发调试）

```bash
git clone https://github.com/zhouhao4221/requirement-workflow-plugin.git
claude plugin add ./requirement-workflow-plugin
```

### 插件管理

```bash
claude plugin list                    # 查看已安装插件
claude plugin update --all            # 更新所有插件
claude plugin remove req              # 卸载插件
```

## 快速开始

### 1. 初始化项目

```
/req:init my-project
```

### 2. 创建需求

```
/req:new 用户积分系统
```

AI 会引导你完善：需求描述、功能清单、业务规则、使用场景、API 设计、测试要点。

### 3. 评审流程

```
/req:review          # 提交评审
/req:review pass     # 通过评审
/req:review reject   # 驳回
```

### 4. 启动开发

```
/req:dev
```

AI 按分层架构引导开发，自动生成实现方案和文件改动清单。

### 5. 测试验证

```
/req:test              # 综合测试
/req:test_regression   # 回归测试
/req:test_new          # 创建新测试用例
```

### 6. 完成归档

```
/req:done
```

## 命令列表

### 需求管理

| 命令 | 说明 |
|------|------|
| `/req` | 列出所有需求，支持 `--type` 和 `--module` 筛选 |
| `/req:new [标题]` | 创建正式需求 |
| `/req:new-quick [标题]` | 创建快速修复（小 bug / 小功能） |
| `/req:edit [REQ-XXX]` | 编辑需求文档 |
| `/req:show [REQ-XXX]` | 查看需求详情（只读） |
| `/req:status [REQ-XXX]` | 查看需求状态 |
| `/req:review [pass\|reject]` | 提交 / 通过 / 驳回评审 |
| `/req:dev [REQ-XXX]` | 启动或继续开发 |
| `/req:test [REQ-XXX]` | 综合测试验证 |
| `/req:test_regression` | 运行已有自动化测试 |
| `/req:test_new` | 为新功能创建测试用例 |
| `/req:done [REQ-XXX]` | 完成需求并归档 |
| `/req:upgrade <QUICK-XXX>` | 快速修复升级为正式需求 |

### PRD 管理

| 命令 | 说明 |
|------|------|
| `/req:prd` | 查看 PRD 状态概览 |
| `/req:prd-edit [章节]` | 编辑 PRD 文档，支持 AI 智能补充 |

### 模块管理

| 命令 | 说明 |
|------|------|
| `/req:modules` | 列出所有模块 |
| `/req:modules new <名称>` | 创建模块文档 |
| `/req:modules show <名称>` | 查看模块详情 |

### 版本管理

| 命令 | 说明 |
|------|------|
| `/req:commit [消息]` | 规范提交，自动关联需求编号 |
| `/req:changelog <version>` | 生成版本升级说明 |

### 项目管理

| 命令 | 说明 |
|------|------|
| `/req:init <项目名>` | 初始化项目 |
| `/req:use <项目名>` | 切换绑定项目 |
| `/req:projects` | 列出所有项目 |
| `/req:migrate <项目名>` | 迁移本地需求到全局缓存 |
| `/req:cache <action>` | 缓存管理（info / clear / rebuild） |
| `/req:update-template` | 同步插件最新模板到项目 |

## 需求生命周期

### 正式需求（REQ）

```
📝 草稿 → 👀 待评审 → ✅ 评审通过 → 🔨 开发中 → 🧪 测试中 → 🎉 已完成
```

### 快速修复（QUICK）

```
📝 草稿 → ✅ 方案确认 → 🔨 开发中 → 🎉 已完成
```

## 跨仓库共享

支持前后端多仓库共享同一套需求：

```
~/backend/                         # 主仓库（primary）
├── docs/requirements/             # 本地存储，纳入 git
│   ├── active/                    # 进行中的需求
│   ├── completed/                 # 已完成的需求
│   ├── modules/                   # 模块文档
│   ├── templates/                 # 模板文件
│   └── PRD.md                     # 产品需求文档
└── .claude/settings.local.json    # requirementRole: "primary"

~/frontend/                        # 只读仓库（readonly）
└── .claude/settings.local.json    # requirementRole: "readonly"

~/.claude-requirements/            # 全局缓存（自动同步）
└── projects/my-project/
```

**使用流程：**
1. 主仓库 `/req:init my-project` 初始化
2. 只读仓库 `/req:use my-project` 绑定
3. 主仓库创建 / 编辑需求 → 自动同步到缓存 → 只读仓库可读取

## 智能技能

插件包含 7 个自动触发的 AI 技能：

| 技能 | 触发场景 |
|------|---------|
| `requirement-analyzer` | 创建 / 编辑需求时，辅助完善文档 |
| `dev-guide` | 开发阶段，按分层架构引导实现 |
| `quick-fix-guide` | 快速修复，快速分析问题并生成方案 |
| `test-guide` | 测试阶段，回归测试和新建测试用例 |
| `prd-analyzer` | 编辑 PRD 时，辅助完善各章节 |
| `code-impact-analyzer` | 需求变更时，分析代码影响范围 |
| `changelog-generator` | 生成版本说明 |

## 目录结构

```
requirement-workflow/
├── .claude-plugin/
│   └── plugin.json              # 插件清单
├── commands/                    # 命令定义（25 个命令）
│   ├── _common.md               # 公共规则
│   ├── req.md                   # 需求列表
│   ├── new.md                   # 创建需求
│   ├── new-quick.md             # 快速修复
│   ├── edit.md                  # 编辑需求
│   ├── review.md                # 评审
│   ├── dev.md                   # 开发
│   ├── test.md                  # 测试
│   ├── done.md                  # 完成
│   ├── commit.md                # 规范提交
│   ├── changelog.md             # 版本说明
│   └── ...
├── skills/                      # 智能技能（7 个）
│   ├── requirement-analyzer/
│   ├── dev-guide/
│   ├── quick-fix-guide/
│   ├── test-guide/
│   ├── prd-analyzer/
│   ├── code-impact-analyzer/
│   └── changelog-generator/
├── hooks/
│   └── hooks.json               # PostToolUse 钩子
├── templates/                   # 文档模板
│   ├── requirement-template.md
│   ├── quick-template.md
│   ├── prd-template.md
│   ├── module-template.md
│   └── index-template.md
├── scripts/                     # 辅助脚本
│   ├── validate-requirement.sh
│   ├── sync-cache.sh
│   ├── parse-requirement.sh
│   ├── update-status.sh
│   ├── check-requirement-link.sh
│   └── check-conflict.sh
├── CLAUDE.md
├── LICENSE
└── README.md
```

## 许可证

[Apache License 2.0](LICENSE)
