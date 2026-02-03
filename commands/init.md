---
description: 初始化需求项目 - 创建本地存储和全局缓存
---

# 初始化需求项目

初始化需求项目，创建本地存储目录和全局缓存，并绑定当前仓库。

## 命令格式

```
/req:init <project-name> [--reinit]
```

## 参数

- `project-name`: 项目名称（建议使用 kebab-case，如 `my-saas-product`）
- `--reinit`: 重新初始化模式，为已有项目补充缺失的目录和文件（不覆盖已有内容）

---

## 执行流程

### 1. 解析参数

```
参数: $ARGUMENTS
项目名称: 从参数中提取（排除 --reinit）
重新初始化模式: 参数包含 --reinit 时为 true
本地存储路径: docs/requirements
全局缓存路径: ~/.claude-requirements/projects/<project-name>
```

**判断逻辑**：
- 若参数包含 `--reinit`，进入重新初始化模式
- 重新初始化模式下，只补充缺失内容，不覆盖已有文件

### 2. 创建本地存储目录（主存储）

```bash
# 在当前仓库创建本地需求目录
LOCAL_ROOT=docs/requirements
mkdir -p $LOCAL_ROOT/active
mkdir -p $LOCAL_ROOT/completed
mkdir -p $LOCAL_ROOT/modules
```

### 3. 复制模板文件到本地

```bash
# 仅当文件不存在时复制（--reinit 模式下保护已有文件）
if [ ! -f $LOCAL_ROOT/template.md ]; then
  cp <plugin-path>/templates/requirement-template.md $LOCAL_ROOT/template.md
fi
```

### 4. 生成 PRD 文档

从模板生成项目 PRD 文档，替换变量：

```bash
# 仅当 PRD.md 不存在时生成（--reinit 模式下保护已有文件）
if [ ! -f $LOCAL_ROOT/PRD.md ]; then
  cp <plugin-path>/templates/prd-template.md $LOCAL_ROOT/PRD.md
  # 替换模板变量
  sed -i 's/{{PROJECT_NAME}}/<project-name>/g' $LOCAL_ROOT/PRD.md
  sed -i 's/{{DATE}}/$(date +%Y-%m-%d)/g' $LOCAL_ROOT/PRD.md
fi
```

### 4.1 创建「快速修复」模块

自动创建「快速修复」模块文档，用于归档快速修复类需求：

```bash
# 仅当模块文档不存在时创建
QUICK_FIX_MODULE=$LOCAL_ROOT/modules/quick-fix.md
if [ ! -f $QUICK_FIX_MODULE ]; then
  cat > $QUICK_FIX_MODULE << 'EOF'
# 快速修复

## 概述

本模块用于归档所有快速修复类需求，包括：
- 小 bug 修复
- 小功能增强
- 代码优化
- UI 微调

这些改动通常不需要完整的需求评审流程，可快速完成。

---

## 核心功能

> 快速修复按时间顺序记录，无需细分功能点

| 编号 | 描述 | 状态 | 完成日期 |
|------|------|------|----------|
| - | 暂无记录 | - | - |

---

## 业务规则

| 规则 | 说明 |
|------|------|
| 改动范围 | 建议 <5 个文件 |
| 数据库变更 | 不涉及表结构变更 |
| 影响范围 | 不影响核心业务流程 |
| 验证方式 | 自测即可 |

---

## 相关需求

| 编号 | 标题 | 状态 | 更新时间 |
|------|------|------|----------|
| - | 暂无 | - | - |

---

## 变更记录

| 日期 | 变更内容 |
|------|----------|
| {{DATE}} | 初始版本 |
EOF
  # 替换日期
  sed -i 's/{{DATE}}/$(date +%Y-%m-%d)/g' $QUICK_FIX_MODULE
fi
```

### 5. 创建全局缓存目录（同步副本）

```bash
# 确保全局缓存目录存在
CACHE_ROOT=~/.claude-requirements/projects/<project-name>
mkdir -p $CACHE_ROOT/active
mkdir -p $CACHE_ROOT/completed
mkdir -p $CACHE_ROOT/modules

# 同步模板和 PRD 到缓存（仅当本地存在时）
[ -f $LOCAL_ROOT/template.md ] && cp $LOCAL_ROOT/template.md $CACHE_ROOT/template.md
[ -f $LOCAL_ROOT/PRD.md ] && cp $LOCAL_ROOT/PRD.md $CACHE_ROOT/PRD.md

# 同步快速修复模块到缓存
[ -f $LOCAL_ROOT/modules/quick-fix.md ] && cp $LOCAL_ROOT/modules/quick-fix.md $CACHE_ROOT/modules/
```

### 6. 更新全局索引

更新 `~/.claude-requirements/index.json`：

```json
{
  "projects": {
    "<project-name>": {
      "created": "2026-01-08",
      "primaryRepo": "/path/to/current/repo",
      "repos": ["/path/to/current/repo"]
    }
  }
}
```

### 7. 绑定当前仓库

在当前仓库创建/更新配置文件 `.claude/settings.local.json`：

```json
{
  "requirementProject": "<project-name>",
  "requirementRole": "primary"
}
```

### 8. 输出结果

**初始化成功**：
```
✅ 项目 "<project-name>" 初始化成功！

📁 本地存储（主存储，纳入 git）:
   docs/requirements/
   ├── active/      # 进行中的需求
   ├── completed/   # 已完成的需求
   ├── modules/     # 模块文档
   │   └── quick-fix.md  # 快速修复模块（预置）
   ├── PRD.md       # 产品需求文档
   └── template.md  # 需求模板

🔄 全局缓存（同步副本，跨仓库共享）:
   ~/.claude-requirements/projects/<project-name>/

🔗 当前仓库已绑定到此项目

📋 已生成 PRD 文档: docs/requirements/PRD.md
   请填写以下关键内容:
   - 产品愿景和目标用户
   - 核心功能列表（P0/P1/P2 优先级）
   - 技术架构选型
   - 版本规划和里程碑

💡 下一步:
   1. 编辑 PRD.md 完善产品规划
   2. /req:new <标题>  创建具体需求
   3. /req             查看需求列表
```

**重新初始化成功**（使用 `--reinit` 参数）：
```
✅ 项目 "<project-name>" 重新初始化完成！

📁 检查并补充缺失内容:
   ✓ docs/requirements/active/      目录已存在
   ✓ docs/requirements/completed/   目录已存在
   ✓ docs/requirements/modules/     目录已存在
   + docs/requirements/modules/quick-fix.md  已生成（新增）
   + docs/requirements/PRD.md       已生成（新增）
   ✓ docs/requirements/template.md  文件已存在（保留）

🔗 当前仓库已绑定到此项目

📋 已生成 PRD 文档: docs/requirements/PRD.md
   请填写以下关键内容:
   - 产品愿景和目标用户
   - 核心功能列表（P0/P1/P2 优先级）
   - 技术架构选型
   - 版本规划和里程碑

💡 提示: --reinit 模式不会覆盖已有文件，仅补充缺失内容
```

**项目已存在时**（未使用 `--reinit`）：
```
⚠️ 项目 "<project-name>" 已存在

📊 项目状态:
   - 活跃需求: X 个
   - 已完成: Y 个
   - 主仓库: /path/to/primary/repo
   - 关联仓库: Z 个

💡 若要为历史项目补充缺失文件，请使用:
   /req:init <project-name> --reinit

是否将当前仓库绑定到此项目？(y/n)
```

---

## 错误处理

| 错误场景 | 处理方式 |
|---------|---------|
| 未提供项目名 | 提示：请提供项目名称，如 `/req:init my-project` |
| 项目名包含非法字符 | 提示：项目名只能包含字母、数字、连字符 |
| 本地目录已存在（无 --reinit） | 提示：本地需求目录已存在，可使用 `--reinit` 补充缺失文件 |
| 权限不足 | 提示：无法创建目录，请检查权限 |

---

## 用户输入

$ARGUMENTS
