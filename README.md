# Dev Workflow Plugin

Claude Code 开发流程工具集，包含多个插件，覆盖需求管理、项目汇报、API 对接等开发全流程。

## 插件列表

| 插件 | 说明 | 版本 |
|------|------|------|
| **req** | 需求全流程工作流管理 | v1.9.0 |
| **pm** | 项目管理助手 — 汇报、统计、方案等项目内容生成 | v0.1.0 |
| **api** | 前端 API 对接工具 — Swagger 解析、字段映射、代码生成 | v0.1.0 |

---

## req 插件 — 需求管理

覆盖从需求分析、评审、开发、测试到归档的完整生命周期。

### 功能特性

- **完整生命周期**：草稿 → 待评审 → 评审通过 → 开发中 → 测试中 → 已完成
- **双轨需求**：正式需求（REQ）和快速修复（QUICK）两套流程
- **智能开发**：`/req:do` 描述意图即可开发，AI 自动分析、选流程、建分支、生成方案
- **智能分析**：AI 辅助完善需求文档、生成实现方案、分析变更影响
- **开发引导**：读取项目 CLAUDE.md 的分层架构，按配置顺序逐层引导（支持 Go/Java/前端等任意技术栈）
- **分支管理**：支持 GitHub Flow / Git Flow / Trunk-Based 三种策略，保护分支严格禁止直接提交
- **PR 审查与合并**：AI 代码审查、自动提交评论到 Gitea/GitHub、一键合并
- **规范文档共享**：主仓库维护数据类型、接口契约等规范，只读仓库实时查阅
- **测试管理**：回归测试 + 新建测试用例（UT/API/E2E）
- **PRD 管理**：产品需求文档编辑，支持从现有需求反推内容
- **跨仓库共享**：前后端多仓库共享同一套需求（本地优先 + 全局缓存）
- **规范提交**：自动关联需求编号的 Conventional Commits
- **版本说明**：基于 Git 记录自动生成 Changelog

### 安装

> 要求：Claude Code v1.0.33 或更高版本（推荐 v2.1+）

```bash
# 从 GitHub 安装
claude plugins marketplace add https://github.com/zhouhao4221/requirement-workflow-plugin
claude plugins install req@dev-workflow    # 需求管理
claude plugins install pm@dev-workflow     # 项目管理助手
claude plugins install api@dev-workflow    # API 对接工具
```

```bash
# 本地安装（开发调试）
git clone https://github.com/zhouhao4221/requirement-workflow-plugin.git
claude plugins marketplace add ./requirement-workflow-plugin
claude plugins install req@dev-workflow
```

```bash
# 插件管理
claude plugins list                              # 查看已安装插件
claude plugins update req@dev-workflow            # 更新插件
claude plugins uninstall req@dev-workflow          # 卸载插件
```

### 快速开始

#### 1. 初始化项目

```
/req:init my-project
```

#### 2. 创建需求

```
/req:new 用户积分系统
```

AI 会引导你完善：需求描述、功能清单、业务规则、使用场景、API 设计、测试要点。

#### 3. 评审流程

```
/req:review          # 提交评审
/req:review pass     # 通过评审
/req:review reject   # 驳回
```

#### 4. 启动开发

```
/req:dev
```

AI 按分层架构引导开发，自动生成实现方案和文件改动清单。

#### 5. 测试验证

```
/req:test              # 综合测试
/req:test_regression   # 回归测试
/req:test_new          # 创建新测试用例
```

#### 6. 完成归档

```
/req:done
```

### 命令列表

#### 需求管理

| 命令 | 说明 |
|------|------|
| `/req` | 列出所有需求，支持 `--type` 和 `--module` 筛选 |
| `/req:new [标题]` | 创建正式需求 |
| `/req:new-quick [标题]` | 创建快速修复（小 bug / 小功能） |
| `/req:do <描述>` | 智能开发（优化/重构/升级/小调整，无文档） |
| `/req:fix <描述>` | 轻量修复（bug 修复，无文档） |
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

#### PR 审查与合并

| 命令 | 说明 |
|------|------|
| `/req:review-pr` | 查看 PR 状态 |
| `/req:review-pr review` | AI 代码审查，提交评论到 Gitea/GitHub |
| `/req:review-pr merge` | 合并 PR（支持 merge/squash/rebase） |

#### 规范文档

| 命令 | 说明 |
|------|------|
| `/req:specs` | 列出所有规范文档 |
| `/req:specs new <名称>` | 创建规范文档（仅主仓库） |
| `/req:specs show <名称>` | 查看规范文档详情 |
| `/req:specs edit <名称>` | 编辑规范文档（仅主仓库） |

#### PRD 管理

| 命令 | 说明 |
|------|------|
| `/req:prd` | 查看 PRD 状态概览 |
| `/req:prd-edit [章节]` | 编辑 PRD 文档，支持 AI 智能补充 |

#### 模块管理

| 命令 | 说明 |
|------|------|
| `/req:modules` | 列出所有模块 |
| `/req:modules new <名称>` | 创建模块文档 |
| `/req:modules show <名称>` | 查看模块详情 |

#### 版本管理

| 命令 | 说明 |
|------|------|
| `/req:commit [消息]` | 规范提交，自动关联需求编号 |
| `/req:changelog <version>` | 生成版本升级说明 |

#### 项目配置

| 命令 | 说明 |
|------|------|
| `/req:init <项目名>` | 初始化项目 |
| `/req:use <项目名>` | 切换绑定项目 |
| `/req:projects` | 列出所有项目 |
| `/req:migrate <项目名>` | 迁移本地需求到全局缓存 |
| `/req:cache <action>` | 缓存管理（info / clear / rebuild） |
| `/req:update-template` | 同步插件最新模板到项目 |

### 需求生命周期

#### 正式需求（REQ）

```
草稿 → 待评审 → 评审通过 → 开发中 → 测试中 → 已完成
```

#### 快速修复（QUICK）

```
草稿 → 方案确认 → 开发中 → 已完成
```

### 跨仓库共享

支持前后端多仓库共享同一套需求：

```
~/backend/                         # 主仓库（primary）
├── docs/requirements/             # 本地存储，纳入 git
│   ├── active/                    # 进行中的需求
│   ├── completed/                 # 已完成的需求
│   ├── modules/                   # 模块文档
│   ├── specs/                     # 规范文档（数据类型、接口契约等）
│   ├── templates/                 # 模板文件
│   └── PRD.md                     # 产品需求文档
└── .claude/settings.local.json    # requirementRole: "primary"

~/frontend/                        # 只读仓库（readonly）
└── .claude/settings.local.json    # requirementRole: "readonly"
  # 可执行 /req:specs show order-types 查看后端定义的数据类型

~/.claude-requirements/            # 全局缓存（自动同步）
└── projects/my-project/
```

**使用流程：**
1. 主仓库 `/req:init my-project` 初始化
2. 只读仓库 `/req:use my-project` 绑定
3. 主仓库创建 / 编辑需求 → 自动同步到缓存 → 只读仓库可读取
4. 主仓库创建规范文档 `/req:specs new` → 只读仓库 `/req:specs show` 查阅

### 智能技能

req 插件包含 7 个自动触发的 AI 技能：

| 技能 | 触发场景 |
|------|---------|
| `requirement-analyzer` | 创建 / 编辑需求时，辅助完善文档 |
| `dev-guide` | 开发阶段，按分层架构引导实现 |
| `quick-fix-guide` | 快速修复，快速分析问题并生成方案 |
| `test-guide` | 测试阶段，回归测试和新建测试用例 |
| `prd-analyzer` | 编辑 PRD 时，辅助完善各章节 |
| `code-impact-analyzer` | 需求变更时，分析代码影响范围 |
| `changelog-generator` | 生成版本说明 |

---

## pm 插件 — 项目管理助手

从 PRD、需求文档和 Git 记录中提取项目数据，按不同场景和受众生成汇报、统计、方案等内容。

- **只读消费**：读取 req 插件产出的数据，不修改需求文档
- **无需 req 即可工作**：没有需求数据时仍可使用 Git 统计和自由提问
- **纯文本输出**：不使用 emoji 和进度条，便于导出为 Word / PDF
- **可选保存**：所有输出均可选择保存到 `docs/reports/` 目录

### 命令列表

| 命令 | 说明 |
|------|------|
| `/pm` | 项目概况仪表盘 |
| `/pm:weekly [--from] [--to]` | 周报 |
| `/pm:monthly [--month=YYYY-MM]` | 月报 |
| `/pm:milestone <版本号>` | 里程碑 / 版本总结 |
| `/pm:stats [--from] [--to]` | 多维度数据统计（需求 / 代码 / 贡献者） |
| `/pm:progress` | 项目总进度 |
| `/pm:plan <主题>` | 生成方案文档（排期 / 技术 / 资源） |
| `/pm:brief [--lang=zh\|en]` | 项目简介（新人 / 客户 / 外部） |
| `/pm:risk` | 风险扫描（延期 / 阻塞 / 异常检测） |
| `/pm:standup` | 站会摘要（昨天 / 今天 / 阻塞） |
| `/pm:ask <问题>` | 基于项目数据自由提问 |
| `/pm:export <命令>` | 导出内容到 docs/reports/ |
| `/pm:help` | 使用帮助 |

### 数据来源

| 来源 | 内容 |
|------|------|
| PRD.md | 产品愿景、功能规划、技术选型 |
| active/*.md | 进行中需求的状态、进度 |
| completed/*.md | 已完成需求、时间线 |
| modules/*.md | 模块职责和需求分布 |
| git log | 提交记录、贡献者、分支活动 |
| git tag | 版本里程碑 |

---

## 目录结构

```
requirement-workflow/
├── .claude-plugin/
│   └── marketplace.json          # 工具集清单
├── plugins/
│   ├── req/                      # 需求管理插件
│   │   ├── .claude-plugin/
│   │   ├── commands/             # 25+ 个命令
│   │   ├── skills/               # 7 个 AI 技能
│   │   ├── hooks/                # PostToolUse 钩子
│   │   ├── templates/            # 文档模板
│   │   └── scripts/              # 辅助脚本
│   ├── pm/                       # 项目管理助手
│   │   ├── .claude-plugin/
│   │   ├── commands/             # 14 个命令
│   │   ├── skills/               # 1 个 AI 技能
│   │   └── scripts/              # Git 统计脚本
│   └── api/                      # API 对接工具
│       ├── .claude-plugin/
│       ├── commands/             # 8 个命令
│       ├── skills/               # 1 个 AI 技能
│       └── scripts/              # Swagger 解析脚本
├── CLAUDE.md
├── LICENSE
└── README.md
```

## 使用教程

完整的分步使用教程见 [docs/tutorial.md](docs/tutorial.md)，包含从安装到完成需求的全流程演示。

## 许可证

[Apache License 2.0](LICENSE)
