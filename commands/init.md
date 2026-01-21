---
description: 初始化需求项目 - 创建本地存储和全局缓存
---

# 初始化需求项目

初始化需求项目，创建本地存储目录和全局缓存，并绑定当前仓库。

## 命令格式

```
/req:init <project-name>
```

## 参数

- `project-name`: 项目名称（建议使用 kebab-case，如 `my-saas-product`）

---

## 执行流程

### 1. 解析参数

```
项目名称: $ARGUMENTS
本地存储路径: docs/requirements
全局缓存路径: ~/.claude-requirements/projects/<project-name>
```

### 2. 创建本地存储目录（主存储）

```bash
# 在当前仓库创建本地需求目录
LOCAL_ROOT=docs/requirements
mkdir -p $LOCAL_ROOT/active
mkdir -p $LOCAL_ROOT/completed
```

### 3. 复制模板文件到本地

```bash
cp <plugin-path>/templates/requirement-template.md $LOCAL_ROOT/template.md
```

### 4. 生成 PRD 文档

从模板生成项目 PRD 文档，替换变量：

```bash
# 复制 PRD 模板并替换变量
cp <plugin-path>/templates/prd-template.md $LOCAL_ROOT/PRD.md

# 替换模板变量
sed -i 's/{{PROJECT_NAME}}/<project-name>/g' $LOCAL_ROOT/PRD.md
sed -i 's/{{DATE}}/$(date +%Y-%m-%d)/g' $LOCAL_ROOT/PRD.md
```

### 5. 创建全局缓存目录（同步副本）

```bash
# 确保全局缓存目录存在
CACHE_ROOT=~/.claude-requirements/projects/<project-name>
mkdir -p $CACHE_ROOT/active
mkdir -p $CACHE_ROOT/completed

# 复制模板和 PRD 到缓存
cp $LOCAL_ROOT/template.md $CACHE_ROOT/template.md
cp $LOCAL_ROOT/PRD.md $CACHE_ROOT/PRD.md
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
  "requirementProject": "<project-name>"
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

**项目已存在时**：
```
⚠️ 项目 "<project-name>" 已存在

📊 项目状态:
   - 活跃需求: X 个
   - 已完成: Y 个
   - 主仓库: /path/to/primary/repo
   - 关联仓库: Z 个

是否将当前仓库绑定到此项目？(y/n)
```

---

## 错误处理

| 错误场景 | 处理方式 |
|---------|---------|
| 未提供项目名 | 提示：请提供项目名称，如 `/req:init my-project` |
| 项目名包含非法字符 | 提示：项目名只能包含字母、数字、连字符 |
| 本地目录已存在 | 提示：本地需求目录已存在，是否继续？ |
| 权限不足 | 提示：无法创建目录，请检查权限 |

---

## 用户输入

$ARGUMENTS
