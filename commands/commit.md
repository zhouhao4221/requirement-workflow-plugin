---
description: 规范提交 - 生成 Conventional Commits 格式的 Git 提交
---

# 规范提交

生成符合 Conventional Commits 规范的 Git 提交，自动关联当前需求编号，便于后续 `/req:changelog` 生成版本说明。

> 此命令**不受仓库角色限制**，readonly 仓库也可执行。
> 不触发缓存同步。

## 命令格式

```
/req:commit [消息]
```

**示例：**
- `/req:commit` — 交互式选择类型并生成提交
- `/req:commit 实现部门渠道关联` — 自动分析变更并生成提交

---

## 执行流程

### 1. 检查工作区状态

```bash
git status --short
git diff --cached --stat
```

**无变更时：**
```
❌ 没有可提交的变更

💡 请先暂存文件：
- git add <file>       暂存指定文件
- git add -A           暂存所有变更
```

**有未暂存变更时：**
自动将所有变更暂存（`git add -A`），展示暂存结果：

```
📁 已暂存所有变更：
  M  internal/sys/biz/dept_channel.go
  A  internal/sys/model/sys_dept_channel_model.go
  M  internal/sys/controller/v1/sys_dept.go
  M  internal/sys/router.go
```

### 2. Code Review 提醒

提交前展示代码审查提醒（信息展示，不等待回复）：

```
⚠️ 提交前请确认已完成 Code Review
   检查要点：逻辑正确性、安全隐患、错误处理、代码规范、调试代码清理
```

### 3. 检测当前需求

```python
# 查找当前活跃的需求（状态为开发中/测试中）
PROJECT = read_settings("requirementProject")
ROLE = read_settings("requirementRole")

if ROLE == "readonly":
    active_dir = f"~/.claude-requirements/projects/{PROJECT}/active/"
elif ROLE == "primary":
    active_dir = "docs/requirements/active/"
else:
    active_dir = "docs/requirements/active/"

# 扫描开发中/测试中的需求
active_reqs = find_requirements(active_dir, status=["开发中", "测试中"])

if len(active_reqs) == 1:
    CURRENT_REQ = active_reqs[0]  # 自动选择
elif len(active_reqs) > 1:
    # 多个活跃需求，让用户选择或跳过
    print("检测到多个活跃需求：")
    for i, req in enumerate(active_reqs):
        print(f"  {i+1}. {req}")
    print(f"  {len(active_reqs)+1}. 不关联需求")
else:
    CURRENT_REQ = None  # 无活跃需求
```

### 4. 分析变更内容

读取 `git diff --cached` 的内容，分析暂存的代码变更：

- 变更性质（新增功能、修复问题、重构等）
- 变更描述（从代码差异中提炼）

### 5. 生成提交信息

#### 5.1 选择提交类型

如果用户未提供消息，交互式选择：

```
📝 选择提交类型：

  1. 新功能     新增功能
  2. 修复       问题修复
  3. 重构       代码重构
  4. 优化       性能优化
  5. 文档       文档更新
  6. 测试       测试相关
  7. 构建       构建/工具/依赖
  8. 样式       代码格式（不影响逻辑）
```

如果用户已提供消息，根据变更内容和消息自动推断类型。

#### 5.2 组装提交消息

**格式：**
```
前缀: 描述 (REQ-XXX)
```

**规则：**
- `前缀`：必填，中文类型前缀
- 描述：简洁的中文描述
- `(REQ-XXX)`：自动追加当前需求编号（如有）

**前缀映射：**

| 前缀 | 含义 | Changelog 分类 |
|------|------|---------------|
| `新功能` | 新增功能 | 新功能 (Features) |
| `修复` | 问题修复 | 问题修复 (Bug Fixes) |
| `重构` | 代码重构 | 重构优化 (Refactoring) |
| `优化` | 性能优化 | 性能优化 (Performance) |
| `文档` | 文档更新 | 文档更新 (Documentation) |
| `测试` | 测试相关 | 测试 (Tests) |
| `构建` | 构建/工具/依赖 | 其他变更 (Others) |
| `样式` | 代码格式 | 其他变更 (Others) |

**示例：**
```
新功能: 实现部门渠道关联 (REQ-001)
修复: 订单渠道过滤逻辑错误 (REQ-001)
重构: 部门服务层代码 (QUICK-003)
文档: 更新 API 文档
构建: 升级依赖版本
```

### 6. 确认并提交

展示完整提交预览：

```
📋 提交预览：

  类型：新功能
  描述：实现部门渠道关联
  关联：REQ-001

  完整消息：
  新功能: 实现部门渠道关联 (REQ-001)

  变更文件（4）：
  A  internal/sys/model/sys_dept_channel_model.go
  A  internal/sys/store/sys_dept_channel_store.go
  A  internal/sys/biz/dept_channel.go
  M  internal/sys/router.go

```

展示预览后直接执行提交（Hook 会弹出原生确认对话框）：

```bash
git commit -m "新功能: 实现部门渠道关联 (REQ-001)"
```

### 7. 提交结果

```
✅ 提交成功！

  commit abc1234
  新功能: 实现部门渠道关联 (REQ-001)

  4 files changed, 156 insertions(+), 3 deletions(-)

💡 后续操作：
- 继续开发：/req:dev
- 再次提交：/req:commit
- 推送远程：git push
- 生成版本说明：/req:changelog <version>
```

---

## Breaking Change 支持

如果变更包含破坏性改动，在前缀后添加 `!` 标记：

```
新功能!: 重构部门 API 返回结构 (REQ-005)
```

交互式流程中增加确认：

```
如果变更涉及 API 返回结构变更、数据库 schema 变更等，自动标记为 Breaking Change。
```

---

## 多行提交消息

对于需要详细说明的提交，支持添加 body：

```
新功能: 实现部门渠道关联 (REQ-001)

- 新增 sys_dept_channel 表及 Model/Store 层
- 实现渠道范围校验逻辑
- 添加获取可选渠道接口
```

当变更涉及多个文件或逻辑复杂时，自动添加 body 说明。

---

## 与 Changelog 的对应关系

本命令生成的提交消息使用中文前缀，`/req:changelog` 可直接解析：

| 提交格式 | Changelog 分类 |
|---------|---------------|
| `新功能: 描述 (REQ-XXX)` | 新功能 (Features) |
| `修复: 描述 (REQ-XXX)` | 问题修复 (Bug Fixes) |
| `重构: 描述` | 重构优化 (Refactoring) |
| `优化: 描述` | 性能优化 (Performance) |
| `文档: 描述` | 文档更新 (Documentation) |
| `测试: 描述` | 测试 (Tests) |
| `构建/样式: 描述` | 其他变更 (Others) |

**需求编号关联**：commit message 中的 `(REQ-XXX)` / `(QUICK-XXX)` 会被 changelog 自动提取并归入「关联需求」章节。

## 用户输入

$ARGUMENTS
