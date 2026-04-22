---
description: 初始化需求项目 - 创建本地存储和全局缓存
argument-hint: "<project-name>"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(mkdir:*, ls:*, cp:*)
model: claude-sonnet-4-6
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
mkdir -p $LOCAL_ROOT/templates
```

### 3. 复制模板文件到本地

将所有模板文件复制到 `docs/requirements/templates/` 目录：

```bash
TEMPLATE_DIR=$LOCAL_ROOT/templates

# 仅当文件不存在时复制（--reinit 模式下保护已有文件）
if [ ! -f $TEMPLATE_DIR/requirement-template.md ]; then
  cp <plugin-path>/templates/requirement-template.md $TEMPLATE_DIR/requirement-template.md
fi

if [ ! -f $TEMPLATE_DIR/quick-template.md ]; then
  cp <plugin-path>/templates/quick-template.md $TEMPLATE_DIR/quick-template.md
fi

if [ ! -f $TEMPLATE_DIR/prd-template.md ]; then
  cp <plugin-path>/templates/prd-template.md $TEMPLATE_DIR/prd-template.md
fi
```

### 4. 生成 PRD 文档

从本地模板生成项目 PRD 文档，替换变量：

```bash
# 仅当 PRD.md 不存在时生成（--reinit 模式下保护已有文件）
if [ ! -f $LOCAL_ROOT/PRD.md ]; then
  cp $TEMPLATE_DIR/prd-template.md $LOCAL_ROOT/PRD.md
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
mkdir -p $CACHE_ROOT/templates
[ -f $TEMPLATE_DIR/requirement-template.md ] && cp $TEMPLATE_DIR/requirement-template.md $CACHE_ROOT/templates/
[ -f $TEMPLATE_DIR/quick-template.md ] && cp $TEMPLATE_DIR/quick-template.md $CACHE_ROOT/templates/
[ -f $TEMPLATE_DIR/prd-template.md ] && cp $TEMPLATE_DIR/prd-template.md $CACHE_ROOT/templates/
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

> 写入规范见 [_storage.md](./_storage.md#settingslocaljson-写入规范)。

读取已有 `.claude/settings.local.json`，合并以下��段后写回（不覆盖已有的 `branchStrategy` 等字段）：

```json
{
  "requirementProject": "<project-name>",
  "requirementRole": "primary"
}
```

### 8. CLAUDE.md 架构引导

检查项目 CLAUDE.md 是否包含架构信息，引导用户补充。

#### 8.1 检查 CLAUDE.md

```python
claude_md_path = "CLAUDE.md"  # 项目根目录
has_architecture = False

if os.path.exists(claude_md_path):
    content = read_file(claude_md_path)
    # 检查是否包含架构关键章节
    has_architecture = any(keyword in content for keyword in [
        "分层架构", "目录结构", "技术栈", "项目架构",
        "Architecture", "Tech Stack"
    ])
```

#### 8.2 引导选择（仅当 CLAUDE.md 缺少架构信息时）

```
📋 CLAUDE.md 中未检测到项目架构描述
   需求开发引导（/req:dev）依赖架构信息来生成实现方案

   选择项目类型，生成 CLAUDE.md 建议片段：

   1. Go 后端（Gin + GORM 分层架构）
   2. Java 后端（Spring Boot 分层架构）
   3. 前端项目（React/Vue + TypeScript）
   4. 自定义（生成空白模板，手动填写）
   5. 跳过（稍后手动添加）

请选择（1-5）：
```

#### 8.3 生成建议片段

根据用户选择，读取对应模板：

```python
snippets = {
    "1": "<plugin-path>/templates/claude-md-snippets/go-backend.md",
    "2": "<plugin-path>/templates/claude-md-snippets/java-backend.md",
    "3": "<plugin-path>/templates/claude-md-snippets/frontend-react.md",
    "4": "<plugin-path>/templates/claude-md-snippets/generic.md",
}
```

展示片段内容，追加到项目 CLAUDE.md 末尾（如文件不存在则创建）。

```
✅ 已将架构片段追加到 CLAUDE.md

💡 请根据实际项目情况修改以下内容：
   - 技术栈版本号
   - 分层架构的目录路径
   - 开发规范和测试规范

   后续 /req:dev 会读取这些信息引导开发
```

#### 8.4 已有架构信息时

```
✅ CLAUDE.md 已包含项目架构描述，跳过引导
```

### 9. 输出结果

**初始化成功**：
```
✅ 项目 "<project-name>" 初始化成功！

📁 本地存储（主存储，纳入 git）:
   docs/requirements/
   ├── active/         # 进行中的需求
   ├── completed/      # 已完成的需求
   ├── modules/        # 模块文档
   │   └── quick-fix.md  # 快速修复模块（预置）
   ├── templates/      # 模板文件
   │   ├── requirement-template.md  # 需求模板
   │   ├── quick-template.md        # 快速修复模板
   │   └── prd-template.md          # PRD 模板
   └── PRD.md          # 产品需求文档

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
   1. 检查 CLAUDE.md 中的架构描述是否准确
   2. 编辑 PRD.md 完善产品规划
   3. /req:branch init  配置分支策略
   4. /req:new <标题>   创建具体需求
```

**重新初始化成功**（使用 `--reinit` 参数）：
```
✅ 项目 "<project-name>" 重新初始化完成！

📁 检查并补充缺失内容:
   ✓ docs/requirements/active/      目录已存在
   ✓ docs/requirements/completed/   目录已存在
   ✓ docs/requirements/modules/     目录已存在
   + docs/requirements/templates/   模板目录
   + docs/requirements/templates/requirement-template.md  已复制
   + docs/requirements/templates/quick-template.md        已复制
   + docs/requirements/templates/prd-template.md          已复制
   + docs/requirements/modules/quick-fix.md  已生成（新增）
   + docs/requirements/PRD.md       已生成（新增）

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
