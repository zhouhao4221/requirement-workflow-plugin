# 公共逻辑参考

> 此文档定义所有命令共用的逻辑，各命令直接引用，避免重复。

## 存储路径解析

```
本地存储（主）: docs/requirements/
├── modules/      # 模块文档
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

不触发同步的命令（只读操作）：`/req`、`/req:status`、`/req:show`、`/req:projects`、`/req:cache`、`/req:use`、`/req:init`、`/req:migrate`、`/req:test_regression`、`/req:test_new`、`/req:prd`、`/req:changelog`、`/req:commit`

同步配置：
- Hook 脚本：`scripts/sync-cache.sh`
- 触发条件：**Write 或 Edit 工具**操作 `docs/requirements/` 目录下的文件后
- 同步范围：REQ-XXX、QUICK-XXX 需求文档、模块文档（modules/）及 PRD.md，不含 INDEX.md、template.md
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

## 元信息字段

| 字段 | 说明 |
|------|------|
| 编号 | REQ-XXX |
| 类型 | 后端/前端/全栈 |
| 状态 | 当前状态 |
| 模块 | 所属模块 |
| 关联需求 | 前后端对应需求 |
| branch | 开发分支名（/req:dev 首次进入时生成） |
