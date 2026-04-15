---
description: 规范文档管理 - 团队共享的数据类型、接口契约、业务规则等规范文档
argument-hint: "[new|show|edit] [名称]"
allowed-tools: Read, Write, Edit, Glob, Grep
---

# 规范文档管理

管理团队共享的规范文档（数据类型定义、接口契约、编码规则等），通过缓存同步实现跨仓库实时共享。

**典型场景**：后端定义数据类型 → 前端（readonly 仓库）随时查阅最新定义。

## 命令格式

```
/req:specs [子命令] [文档名]
```

## 子命令

| 子命令 | 说明 | 权限 | 示例 |
|--------|------|------|------|
| (空) | 列出所有规范文档 | 所有角色 | `/req:specs` |
| `new` | 创建规范文档 | 仅 primary | `/req:specs new 订单数据类型` |
| `show` | 查看规范文档 | 所有角色 | `/req:specs show order-types` |
| `edit` | 编辑规范文档 | 仅 primary | `/req:specs edit order-types` |

---

## 存储路径

```
<需求根目录>/
├── specs/             # 规范文档目录
│   ├── order-types.md       # 订单数据类型定义
│   ├── api-contract.md      # 接口契约
│   ├── error-codes.md       # 错误码规范
│   └── ...
├── modules/
├── active/
├── completed/
└── INDEX.md
```

缓存同步路径：`~/.claude-requirements/projects/<project>/specs/`

---

## 权限控制

```
primary  → 读写（new / edit / show / 列表）
readonly → 只读（show / 列表）
```

**readonly 仓库执行写操作时**：
```
❌ 只读仓库不可创建/编辑规范文档

💡 规范文档由主仓库维护，只读仓库可通过以下命令查阅：
  /req:specs              - 查看规范列表
  /req:specs show <名称>  - 查看规范详情
```

---

## 执行流程（列表模式）

### 1. 确定读取路径

```
primary:  优先读本地 docs/requirements/specs/
readonly: 直接读缓存 ~/.claude-requirements/projects/$PROJECT/specs/
```

### 2. 扫描规范文档

读取 `specs/` 目录下所有 `.md` 文件，从每个文件提取：
- 文档标题（首个 `# ` 标题）
- 分类标签（元信息 `category` 字段）
- 最后更新时间（元信息 `updated` 字段）
- 简要描述（元信息 `description` 字段）

### 3. 展示列表

```
📋 规范文档

| 文档 | 分类 | 描述 | 更新时间 |
|------|------|------|----------|
| order-types | 数据类型 | 订单相关枚举和结构体定义 | 2026-03-25 |
| api-contract | 接口契约 | 前后端 API 请求/响应格式 | 2026-03-20 |
| error-codes | 错误码 | 全局错误码定义和使用规范 | 2026-03-15 |

共 3 份规范文档

💡 可用操作：
- /req:specs show order-types - 查看详情
- /req:specs new <名称> - 创建新规范
- /req:specs edit <名称> - 编辑规范
```

无文档时：
```
📋 规范文档

  （暂无规范文档）

💡 创建第一份规范文档：/req:specs new <名称>
   例如：/req:specs new 订单数据类型
```

---

## 创建规范文档（new）

> 仅 primary 仓库可执行。

### 流程

1. **检查权限**：readonly 仓库 → 拒绝并提示
2. **解析文档名**：用户输入中文名 → 生成 kebab-case 英文文件名（如 `订单数据类型` → `order-types.md`）
3. **检查重复**：同名文件已存在 → 提示并建议 edit
4. **创建文档**：使用下方模板创建到 `docs/requirements/specs/`
5. **引导填写**：AI 根据文档名推断内容结构，引导用户填充

### 文档模板

```markdown
---
category: <分类>
description: <一句话描述>
updated: <YYYY-MM-DD>
---

# <文档标题>

> <简要说明用途和适用范围>

## 内容

（根据文档类型，AI 自动生成合适的结构）
```

**常见分类**：数据类型、接口契约、错误码、业务规则、编码规范、配置说明

### 示例

```
/req:specs new 订单数据类型
```

输出：
```
📋 创建规范文档：订单数据类型

已创建：docs/requirements/specs/order-types.md

请描述需要定义的内容，例如：
- 订单有哪些状态？各状态含义？
- 订单包含哪些字段？类型和约束？
- 有哪些枚举值需要前后端统一？

💡 创建后自动同步到缓存，readonly 仓库可通过 /req:specs show order-types 查看
```

---

## 查看规范文档（show）

> 所有角色均可执行。

### 流程

1. **确定读取路径**：primary → 本地，readonly → 缓存
2. **查找文档**：支持中文名或文件名匹配（模糊匹配）
3. **展示完整内容**：直接输出文档全文

### 示例

```
/req:specs show order-types
```

输出文档完整内容，末尾附操作提示：
```
💡 可用操作：
- /req:specs edit order-types - 编辑此文档（仅 primary）
- /req:specs - 返回规范列表
```

**文档不存在时**：
```
❌ 未找到规范文档：order-types

💡 可用的规范文档：
  - api-contract
  - error-codes

或创建新文档：/req:specs new order-types
```

---

## 编辑规范文档（edit）

> 仅 primary 仓库可执行。

### 流程

1. **检查权限**：readonly 仓库 → 拒绝
2. **查找文档**：支持模糊匹配
3. **读取现有内容**
4. **根据用户指示编辑**：用户说明修改意图 → AI 执行修改
5. **更新 `updated` 字段**为当天日期

### 示例

```
/req:specs edit order-types
```

AI 读取文档后等待用户说明修改内容：
```
📋 编辑规范文档：order-types

当前内容已读取，请描述需要修改的内容：
- 新增字段/类型？
- 修改现有定义？
- 补充说明？
```

---

## 缓存同步

规范文档通过现有的 PostToolUse Hook 自动同步：

- **触发条件**：Write/Edit 操作 `docs/requirements/specs/` 下的文件
- **同步方向**：本地 → 缓存（以本地为准）
- **同步目标**：`~/.claude-requirements/projects/<project>/specs/`
- **仅 primary 仓库**执行同步，readonly 跳过

---

## 用户输入

$ARGUMENTS
