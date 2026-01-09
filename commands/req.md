---
description: 需求工作流管理 - 列出所有需求及其状态
---

# 需求工作流管理

需求全流程管理主入口，列出所有需求及其状态。

## 命令格式

```
/req [子命令] [参数]
```

## 子命令

| 子命令 | 说明 | 示例 |
|-------|------|------|
| (空) | 列出所有需求 | `/req` |
| `new` | 创建新需求 | `/req new 用户积分系统` |
| `edit` | 编辑需求 | `/req edit REQ-001` |
| `review` | 评审需求 | `/req review REQ-001` |
| `dev` | 开发需求 | `/req dev REQ-001` |
| `test` | 测试需求 | `/req test REQ-001` |
| `done` | 完成需求 | `/req done REQ-001` |
| `status` | 查看状态 | `/req status REQ-001` |
| `init` | 初始化项目 | `/req init my-project` |
| `use` | 切换项目 | `/req use my-project` |
| `projects` | 列出所有项目 | `/req projects` |
| `migrate` | 迁移本地需求到全局缓存 | `/req migrate my-project` |
| `cache` | 缓存管理 | `/req cache clear my-project` |

---

## 需求存储路径解析

### 路径优先级

1. **全局缓存**（推荐）：`~/.claude-requirements/projects/<project-name>/`
2. **本地目录**（回退）：`docs/requirements/`

### 解析流程

```
1. 检查 .claude/settings.local.json 中的 requirementProject
2. 如果设置了 requirementProject:
   → 使用 ~/.claude-requirements/projects/<requirementProject>/
3. 如果未设置:
   → 回退到本地 docs/requirements/
```

### 目录结构

```
<需求根目录>/
├── active/        # 进行中的需求
├── completed/     # 已完成的需求
└── template.md    # 需求模板
```

---

## 执行流程（列表模式）

### 0. 解析需求路径

```bash
# 检查当前仓库绑定的项目
cat .claude/settings.local.json | jq -r '.requirementProject'

# 如果有绑定项目，使用全局缓存路径
REQ_PATH=~/.claude-requirements/projects/<project-name>/active/

# 如果没有绑定，使用本地路径
REQ_PATH=docs/requirements/active/
```

### 1. 扫描需求目录

```bash
ls $REQ_PATH
```

### 2. 解析每个需求文档

提取元信息：
- 编号（REQ-XXX）
- 标题
- 状态
- 功能点完成进度
- 更新时间

### 3. 展示需求列表

按状态分组输出：

```
📋 活跃需求列表

🔨 开发中
| 编号 | 标题 | 进度 | 更新时间 |
|------|------|------|----------|
| REQ-001 | 部门渠道关联 | 4/6 | 2026-01-07 |

👀 待评审
| 编号 | 标题 | 功能点 | 创建时间 |
|------|------|--------|----------|
| REQ-002 | ... | 3 | 2026-01-08 |

📝 草稿
| 编号 | 标题 | 创建时间 |
|------|------|----------|
| REQ-003 | ... | 2026-01-08 |
```

### 4. 提示可用操作

```
💡 可用命令：
- /req:new <标题> - 创建新需求
- /req:dev REQ-001 - 进入开发
- /req:status REQ-001 - 查看详情
```

---

## 子命令路由

根据参数路由到对应子命令：

```
参数解析：
- 无参数 → 列表模式
- new → /req-new
- edit REQ-XXX → /req-edit REQ-XXX
- review REQ-XXX → /req-review REQ-XXX
- dev REQ-XXX → /req-dev REQ-XXX
- test REQ-XXX → /req-test REQ-XXX
- done REQ-XXX → /req-done REQ-XXX
- status REQ-XXX → /req-status REQ-XXX
- init <project-name> → /req-init <project-name>
- use <project-name> → /req-use <project-name>
- projects → /req-projects
- migrate <project-name> → /req-migrate <project-name>
- cache <action> → /req-cache <action>
```

## 用户输入

$ARGUMENTS
