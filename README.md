# DevFlow

AI 驱动的软件全生命周期管理工具集，覆盖需求分析、开发引导、测试验证、项目管理、API 对接等完整流程。基于 Claude Code 插件体系构建。

## 插件列表

| 插件 | 说明 | 版本 |
|------|------|------|
| **req** | 需求全流程管理 — 从需求分析到测试归档的完整生命周期 | v3.0.1 |
| **pm** | 项目管理助手 — 周报、月报、统计、风险扫描、方案生成 | v0.1.0 |
| **api** | API 对接工具 — Swagger 解析、字段映射、代码生成 | v0.2.0 |

---

## 安装

> 要求：Claude Code v1.0.33 或更高版本（推荐 v2.1+）

> **从 aiforge 升级**：marketplace 名称已由 `aiforge` 改为 `devflow`，老用户需要先卸载再重装：
> ```bash
> claude plugins uninstall req@aiforge
> claude plugins marketplace remove aiforge
> claude plugins marketplace add https://github.com/zhouhao4221/devflow-claude
> claude plugins install req@devflow
> ```

```bash
# 从 GitHub 安装
claude plugins marketplace add https://github.com/zhouhao4221/devflow-claude
claude plugins install req@devflow    # 需求管理
claude plugins install pm@devflow     # 项目管理助手
claude plugins install api@devflow    # API 对接工具
```

```bash
# 本地安装（开发调试）
git clone https://github.com/zhouhao4221/devflow-claude.git
claude plugins marketplace add ./devflow-claude
claude plugins install req@devflow
```

```bash
# 插件管理
claude plugins list                   # 查看已安装插件
claude plugins update req@devflow     # 更新插件
claude plugins uninstall req@devflow  # 卸载插件
```

---

## 智能模型分级

所有命令通过 frontmatter 声明 `model` 字段，按复杂度自动选择模型，平衡响应速度与推理质量：

| 模型 | 定位 | 典型命令 |
|------|------|---------|
| **Haiku** | 纯读取 / 列表 / 帮助 | `/req`、`/req:status`、`/req:show`、`/pm:standup`、`/api:help` |
| **Sonnet** | 标准创建 / 编辑 / Git 操作 | `/req:new`、`/req:edit`、`/req:commit`、`/pm:stats`、`/api:config` |
| **Opus** | 深度分析 / 方案生成 / AI 审查 | `/req:dev`、`/req:fix`、`/req:review-pr`、`/pm:weekly`、`/api:gen` |

每个命令还通过 `allowed-tools` 白名单限定可用工具，只读命令不会触发写入操作。

---

## req 插件 — 需求管理

覆盖从需求分析、评审、开发、测试到归档的完整生命周期。

### 核心特性

- **AI 提问式需求分析**：AI 逐轮提问收集信息，一次性生成完整需求文档
- **完整生命周期**：草稿 → 待评审 → 评审通过 → 开发中 → 测试中 → 已完成
- **双轨需求**：正式需求（REQ）和快速修复（QUICK）两套流程
- **智能开发**：`/req:do` 描述意图即可开发，AI 自动分析、选流程、建分支、生成方案
- **开发引导**：读取项目 CLAUDE.md 的分层架构，按配置顺序逐层引导（支持任意技术栈）
- **开发中文档维护**：AI 发现偏差时主动提示更新需求文档
- **分支管理**：GitHub Flow / Git Flow / Trunk-Based 三种策略
- **前后端协作**：前端 REQ 描述交互逻辑，dev 阶段自动匹配后端接口
- **PR 审查与合并**：AI 代码审查、自动提交评论、一键合并
- **Git issue 集成**：`--from-issue=#N` 直接从 Gitea/GitHub issue 创建需求，分支/commit/done 全链路自动关联和关闭 issue
- **跨仓库共享**：前后端多仓库共享同一套需求（本地优先 + 全局缓存）
- **规范提交**：自动关联需求编号的 Conventional Commits
- **版本说明**：基于 Git 记录自动生成 Changelog

### 快速开始

```bash
# 1. 初始化项目
/req:init my-project

# 2. 创建需求（AI 提问收集信息 → 一次性生成文档）
/req:new 用户积分系统

# 3. 评审
/req:review pass

# 4. 开发（AI 生成实现方案，按分层架构引导）
/req:dev

# 5. 测试
/req:test

# 6. 完成归档
/req:done
```

### 命令一览

#### 需求管理

| 命令 | 说明 |
|------|------|
| `/req` | 列出所有需求，支持 `--type` 和 `--module` 筛选 |
| `/req:new [标题]` | 创建正式需求（AI 提问 → 生成文档） |
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
| `/req:split [描述]` | 需求粒度分析和拆分建议 |

#### PR 审查与合并

| 命令 | 说明 |
|------|------|
| `/req:pr [REQ-XXX]` | 创建 PR（自动适配 GitHub / Gitea） |
| `/req:review-pr` | 查看 PR 状态 |
| `/req:review-pr review` | AI 代码审查，提交评论 |
| `/req:review-pr merge` | 合并 PR（支持 merge/squash/rebase） |

#### 文档管理

| 命令 | 说明 |
|------|------|
| `/req:prd` | 查看 PRD 状态概览 |
| `/req:prd-edit [章节]` | 编辑 PRD 文档 |
| `/req:modules` | 列出所有模块 |
| `/req:specs` | 规范文档管理（数据类型、接口契约等） |

#### 版本与分支

| 命令 | 说明 |
|------|------|
| `/req:commit [消息]` | 规范提交，自动关联需求编号 |
| `/req:changelog <version>` | 生成版本升级说明 |
| `/req:branch init` | 配置分支策略 |
| `/req:branch hotfix [描述]` | 创建紧急修复分支 |

#### 项目配置

| 命令 | 说明 |
|------|------|
| `/req:init <项目名>` | 初始化项目 |
| `/req:use <项目名>` | 切换绑定项目 |
| `/req:projects` | 列出所有项目 |
| `/req:cache <action>` | 缓存管理 |
| `/req:update-template` | 同步插件最新模板 |

### 需求生命周期

```
正式需求（REQ）：草稿 → 待评审 → 评审通过 → 开发中 → 测试中 → 已完成
快速修复（QUICK）：草稿 → 方案确认 → 开发中 → 已完成
```

### 需求文档结构

| 区域 | 章节 | 填充方式 |
|------|------|---------|
| 需求定义 | 一~六（需求描述、功能清单、业务规则、使用场景、数据与交互、测试要点） | AI 提问收集 → 一次性生成 |
| 流程记录 | 七~九（评审记录、变更记录、关联信息） | 各命令自动填充 |
| 实现方案 | 十（数据模型、API 设计、文件改动、实现步骤） | `/req:dev` 阶段 AI 分析代码生成 |

### 跨仓库共享

```
~/backend/   (primary)  → docs/requirements/  本地存储，纳入 git
~/frontend/  (readonly) → 从全局缓存读取需求，dev 阶段自动匹配后端接口
~/.claude-requirements/  → 全局缓存（自动同步）
```

### AI 技能（自动触发）

| 技能 | 触发场景 |
|------|---------|
| `requirement-analyzer` | 创建/编辑需求时，AI 提问收集 → 生成文档 |
| `dev-guide` | 开发阶段，按分层架构引导 + 开发中文档维护 |
| `quick-fix-guide` | 快速修复，快速分析并生成方案 |
| `test-guide` | 测试阶段，回归测试和新建测试 |
| `prd-analyzer` | 编辑 PRD 时，辅助完善各章节 |
| `code-impact-analyzer` | 需求变更时，分析代码影响范围 |
| `changelog-generator` | 生成版本说明 |

---

## pm 插件 — 项目管理助手

从 PRD、需求文档和 Git 记录中提取项目数据，按不同场景和受众生成汇报、统计、方案等内容。

- **只读消费**：读取 req 插件产出的数据，不修改需求文档
- **无需 req 即可工作**：没有需求数据时仍可使用 Git 统计和自由提问
- **可选保存**：所有输出均可保存到 `docs/reports/`

| 命令 | 说明 |
|------|------|
| `/pm` | 项目概况仪表盘 |
| `/pm:weekly` | 周报 |
| `/pm:monthly` | 月报 |
| `/pm:milestone <版本>` | 里程碑总结 |
| `/pm:stats` | 多维度数据统计 |
| `/pm:progress` | 项目总进度 |
| `/pm:plan <主题>` | 方案文档（排期/技术/资源） |
| `/pm:risk` | 风险扫描 |
| `/pm:standup` | 站会摘要 |
| `/pm:ask <问题>` | 基于项目数据自由提问 |

---

## api 插件 — API 对接工具

前端 API 对接工具，支持 Swagger/OpenAPI 解析、字段映射、代码生成。

| 命令 | 说明 |
|------|------|
| `/api:import` | 导入 Swagger 文档 |
| `/api:search <关键词>` | 搜索接口 |
| `/api:gen` | 生成 TypeScript 类型和请求函数 |
| `/api:map` | 字段映射分析 |

---

## 使用教程

完整的分步教程见 [docs/tutorial.md](docs/tutorial.md)。

## 许可证

[Apache License 2.0](LICENSE)
