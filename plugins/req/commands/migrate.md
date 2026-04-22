---
description: 迁移需求 - 将本地需求迁移到全局缓存
argument-hint: "<project-name>"
allowed-tools: Read, Write, Edit, Glob, Bash(ls:*, cp:*, mkdir:*)
model: claude-sonnet-4-6
---

# 迁移需求

将本地 `docs/requirements/` 中的需求迁移到全局缓存。

## 命令格式

```
/req:migrate <project-name> [--keep]
```

## 参数

- `project-name`: 目标项目名称（必填）
- `--keep`: 保留本地文件（可选，默认删除）

---

## 执行流程

### 1. 前置检查

```bash
# 检查本地需求目录是否存在
if [ ! -d "docs/requirements/active" ] && [ ! -d "docs/requirements/completed" ]; then
    echo "❌ 未找到本地需求目录 docs/requirements/"
    echo "💡 无需迁移，可直接使用 /req:init <project-name>"
    exit 1
fi

# 统计本地需求数量
LOCAL_ACTIVE=$(ls docs/requirements/active/*.md 2>/dev/null | wc -l)
LOCAL_COMPLETED=$(ls docs/requirements/completed/*.md 2>/dev/null | wc -l)
```

### 2. 检查目标项目

```bash
PROJECT_PATH=~/.claude-requirements/projects/<project-name>

if [ -d "$PROJECT_PATH" ]; then
    # 项目已存在，检查是否有冲突
    REMOTE_ACTIVE=$(ls $PROJECT_PATH/active/*.md 2>/dev/null | wc -l)
    REMOTE_COMPLETED=$(ls $PROJECT_PATH/completed/*.md 2>/dev/null | wc -l)

    if [ $REMOTE_ACTIVE -gt 0 ] || [ $REMOTE_COMPLETED -gt 0 ]; then
        echo "⚠️ 目标项目已有需求文档"
        echo "   活跃需求: $REMOTE_ACTIVE 个"
        echo "   已完成: $REMOTE_COMPLETED 个"
        echo ""
        echo "请选择合并策略："
        echo "1. 合并 - 保留两边，编号冲突时重新编号"
        echo "2. 覆盖 - 用本地覆盖远程"
        echo "3. 取消"
    fi
else
    # 项目不存在，自动创建
    mkdir -p $PROJECT_PATH/active
    mkdir -p $PROJECT_PATH/completed
fi
```

### 3. 显示迁移预览

```
📋 需求迁移预览

源目录: docs/requirements/
目标项目: <project-name>
目标路径: ~/.claude-requirements/projects/<project-name>/

📊 迁移内容:
- 活跃需求: X 个
- 已完成需求: Y 个
- 模板文件: 1 个

📁 文件列表:
活跃需求:
├── REQ-001-部门渠道关联.md
├── REQ-002-用户积分系统.md
└── REQ-003-订单导出优化.md

已完成:
└── REQ-000-初始化项目.md
```

### 4. 执行迁移

```bash
# 复制活跃需求
cp docs/requirements/active/*.md $PROJECT_PATH/active/ 2>/dev/null

# 复制已完成需求
cp docs/requirements/completed/*.md $PROJECT_PATH/completed/ 2>/dev/null

# 复制模板目录（如果存在且目标没有）
if [ -d "docs/requirements/templates" ]; then
    mkdir -p $PROJECT_PATH/templates
    cp docs/requirements/templates/*.md $PROJECT_PATH/templates/ 2>/dev/null
fi
```

### 5. 处理编号冲突（合并模式）

如果目标项目已有需求，检查编号冲突：

```
⚠️ 检测到编号冲突

冲突列表:
- REQ-001 (本地: 部门渠道关联 vs 远程: 用户管理)
- REQ-002 (本地: 用户积分系统 vs 远程: 权限配置)

处理方式:
- REQ-001 → 保留远程，本地重命名为 REQ-004
- REQ-002 → 保留远程，本地重命名为 REQ-005
```

### 6. 绑定当前仓库

> 写入规范见 [_storage.md](./_storage.md#settingslocaljson-写入规范)。

读取已有 `.claude/settings.local.json`，合并以下字段后写回（不覆盖已有的 `branchStrategy` 等字段）：

```json
{
  "requirementProject": "<project-name>"
}
```

### 7. 清理本地文件（默认行为）

```bash
# 如果没有 --keep 参数
rm -rf docs/requirements/active/
rm -rf docs/requirements/completed/
rm -rf docs/requirements/templates/

# 保留空目录结构（可选）
# mkdir -p docs/requirements/active
# mkdir -p docs/requirements/completed
```

如果指定 `--keep`：
```
💡 本地文件已保留，如需删除请手动执行：
   rm -rf docs/requirements/
```

### 8. 输出结果

```
✅ 迁移完成！

📊 迁移统计:
- 迁移活跃需求: X 个
- 迁移已完成需求: Y 个
- 重新编号: Z 个

📁 新位置: ~/.claude-requirements/projects/<project-name>/

🔗 当前仓库已绑定到项目 "<project-name>"

💡 下一步:
- 查看需求列表: /req
- 在其他仓库绑定: /req:use <project-name>
```

---

## 错误处理

| 错误场景 | 处理方式 |
|---------|---------|
| 本地无需求 | 提示使用 `/req:init` |
| 目标项目有冲突 | 提供合并策略选择 |
| 权限不足 | 提示检查目录权限 |
| 迁移中断 | 回滚已迁移文件 |

---

## 示例

```bash
# 基本迁移
/req:migrate my-saas-product

# 迁移但保留本地副本
/req:migrate my-saas-product --keep

# 迁移到已有项目（会提示合并策略）
/req:migrate existing-project
```

## 用户输入

$ARGUMENTS
