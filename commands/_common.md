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

不触发同步的命令（只读操作）：`/req`、`/req:status`、`/req:projects`、`/req:cache`、`/req:use`、`/req:init`、`/req:migrate`、`/req:test_regression`、`/req:test_new`

同步配置：
- Hook 脚本：`scripts/sync-cache.sh`
- 触发条件：**Write 或 Edit 工具**操作 `docs/requirements/` 目录下的文件后
- 同步范围：REQ-XXX、QUICK-XXX 需求文档及模块文档（modules/），不含 INDEX.md、template.md
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
| `/req:test` | 开发中 → 测试中 | 执行命令即为确认 |
| `/req:done` | 测试中 → 已完成 | **必须明确确认（y/n）** |

## 需求编号生成

扫描 active/ 和 completed/ 目录，找最大编号 +1，格式 `REQ-XXX`

## 状态流转

```
📝 草稿 → 👀 待评审 → ✅ 评审通过 → 🔨 开发中 → 🧪 测试中 → 🎉 已完成
```

## 元信息字段

| 字段 | 说明 |
|------|------|
| 编号 | REQ-XXX |
| 类型 | 后端/前端/全栈 |
| 状态 | 当前状态 |
| 模块 | 所属模块 |
| 关联需求 | 前后端对应需求 |
