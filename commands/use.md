---
description: 切换需求项目 - 将当前仓库绑定到不同的项目
---

# 切换需求项目

将当前仓库绑定到另一个已存在的需求项目。

## 命令格式

```
/req:use <project-name>
```

## 参数

- `project-name`: 要切换到的项目名称

---

## 执行流程

### 1. 解析参数

```
目标项目: $ARGUMENTS
全局缓存路径: ~/.claude-requirements
```

### 2. 检查目标项目是否存在

```bash
ls ~/.claude-requirements/projects/<project-name>/
```

**如果项目不存在**：
- 列出所有可用项目
- 提示使用 `/req:init` 创建新项目

### 3. 读取当前绑定

检查当前仓库的 `.claude/settings.local.json`：

```json
{
  "requirementProject": "old-project"
}
```

### 4. 更新仓库绑定

更新 `.claude/settings.local.json`：

```json
{
  "requirementProject": "<project-name>",
  "requirementRole": "readonly"
}
```

> `/req:use` 绑定的仓库默认为 `readonly` 角色，仅从缓存读取需求。如需升级为主仓库，使用 `/req:init <project-name>` 初始化本地存储。

### 5. 更新全局索引

更新 `~/.claude-requirements/index.json`：
- 从旧项目的 repos 列表移除当前仓库
- 添加到新项目的 repos 列表

### 6. 输出结果

```
✅ 已切换到项目 "<project-name>"

📊 项目状态:
   - 活跃需求: X 个
   - 已完成: Y 个

📋 活跃需求列表:
   | 编号 | 标题 | 状态 |
   |------|------|------|
   | REQ-001 | ... | 🔨 开发中 |
   | REQ-002 | ... | 👀 待评审 |

💡 使用 /req 查看完整列表
```

---

## 无参数模式

当不带参数执行 `/req:use` 时：

### 显示当前绑定

```
📂 当前项目: <project-name>
📁 路径: ~/.claude-requirements/projects/<project-name>/

💡 可用命令:
   - /req:use <project-name>  切换到其他项目
   - /req:projects            查看所有项目
```

---

## 错误处理

| 错误场景 | 处理方式 |
|---------|---------|
| 项目不存在 | 列出可用项目，提示使用 `/req:init` 创建 |
| 全局缓存未初始化 | 提示先运行 `/req:init <project-name>` |

---

## 用户输入

$ARGUMENTS
