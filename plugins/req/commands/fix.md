---
description: 轻量修复 - 无文档的 bug 修复流程，AI 辅助定位问题
argument-hint: "<问题描述>"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(git:*)
---

# 轻量修复

创建修复分支，AI 辅助分析定位 bug，修复后直接提交和 PR。不创建需求文档。

> 此命令**不受仓库角色限制**，readonly 仓库也可执行。
> 不触发缓存同步（无需求文档）。

## 命令格式

```
/req:fix <问题描述>
```

示例：
- `/req:fix 登录超时后 token 未清除`
- `/req:fix 订单列表分页数据重复`
- `/req:fix 导出 Excel 中文文件名乱码`

---

## 执行流程

### 1. AI 辅助分析 bug

> 读取项目 CLAUDE.md 的「项目架构」章节，了解分层结构和目录布局。
> **此阶段在当前分支上进行，不创建新分支。**

根据用户描述的问题，AI 进行定位分析：

#### 1.1 问题分析

```
🔍 Bug 分析：登录超时后 token 未清除

📋 问题理解：
- 现象：用户登录超时后，本地 token 未被清除，导致后续请求携带过期 token
- 影响范围：认证流程、请求拦截器

🔎 可能涉及的代码：
```

#### 1.2 定位相关文件

AI 搜索代码库，定位可能相关的文件：

```
📂 相关文件定位：

| 文件 | 相关度 | 原因 |
|------|-------|------|
| src/utils/auth.ts | 高 | token 存取逻辑 |
| src/interceptors/request.ts | 高 | 请求拦截，超时处理 |
| src/store/user.ts | 中 | 用户状态管理 |
```

#### 1.3 关联需求匹配（自动，低成本）

**目的**：找出可能引入此 bug 的需求，获取业务上下文辅助定位。

**流程**（只读索引 + 按需读正文，控制 token 消耗）：

```python
# 第 1 步：读 INDEX.md（几十行，~500 token）
index = read_file("docs/requirements/INDEX.md")

# 第 2 步：用 bug 相关文件路径匹配需求
#   从步骤 1.2 拿到的相关文件列表，在 INDEX.md 中模糊匹配
#   INDEX.md 包含：编号、标题、状态、模块
related_files = ["src/utils/auth.ts", "src/interceptors/request.ts"]
keywords = extract_keywords(bug_description)  # "登录", "token", "超时"

# 匹配策略（满足任一即命中）：
#   a. 需求标题包含关键词（如「登录认证」）
#   b. 需求所属模块与 bug 相关（如「用户」模块）
matched_reqs = match_index(index, keywords)
```

```
# 第 3 步：命中时，仅读该需求的「十一、实现方案」中的文件改动清单（~1k token）
#   未命中 → 跳过，不额外消耗
if matched_reqs:
    for req in matched_reqs[:2]:  # 最多读 2 个
        file_list = read_section(req, "11.3 文件改动清单")
```

**命中时展示**：

```
📎 关联需求：

| 需求 | 标题 | 关联原因 |
|------|------|---------|
| REQ-003 | 登录认证优化 | 修改了 src/interceptors/request.ts |

💡 此 bug 可能由 REQ-003 引入，已读取其文件改动清单辅助定位。
```

**未命中时**：静默跳过，不输出任何内容，不消耗额外 token。

**成本控制**：

| 步骤 | Token 消耗 | 条件 |
|------|-----------|------|
| 读 INDEX.md | ~500 | 始终执行 |
| 匹配关键词 | ~0 | AI 内部处理 |
| 读命中需求节选 | ~1k/个 | 仅命中时，最多 2 个 |
| **总计** | **500 ~ 2500** | 远低于全量读取（~50k） |

#### 1.4 根因分析

AI 综合代码搜索结果和关联需求上下文，给出根因判断：

```
🎯 根因分析：

在 src/interceptors/request.ts:45，响应拦截器捕获 401 状态码时
调用了 router.push('/login')，但未调用 removeToken()。
（REQ-003 登录认证优化 新增了 401 拦截逻辑，但遗漏了 token 清除）

建议修复：在跳转登录页前清除 token。
```

#### 1.5 修复建议

```
💡 修复建议：

1. src/interceptors/request.ts
   - 在 401 处理分支中，跳转前调用 removeToken()

2. 建议同时检查：
   - token 过期的其他入口（如定时刷新失败）

是否按以上方案修复？（可以补充说明或调整方向）
```

**等待用户确认**。用户可以：
- 确认方案 → 进入步骤 2
- 补充信息 / 调整方向 → AI 重新分析
- 放弃 → 结束，不创建分支

---

### 2. 创建修复分支

> **用户确认修复方案后**才创建分支，避免分析后放弃导致残留空分支。

#### 2.1 工作区检查

```bash
git status --porcelain
```

有未提交改动时终止，提示先 commit 或 stash。

#### 2.2 读取分支策略

```python
strategy = read_settings("branchStrategy")

if strategy:
    MAIN_BRANCH = strategy["mainBranch"]
    BRANCH_FROM = strategy.get("branchFrom", MAIN_BRANCH)
    FIX_PREFIX = strategy.get("fixPrefix", "fix/")
else:
    MAIN_BRANCH = detect_main_branch()
    BRANCH_FROM = MAIN_BRANCH
    FIX_PREFIX = "fix/"
```

#### 2.3 创建分支

AI 根据问题描述生成英文 slug（lowercase kebab-case，最多 5 词）：

```
🌿 创建修复分支：fix/login-token-not-cleared
   基于：main（来源：branchStrategy.branchFrom）
```

```bash
git fetch origin $BRANCH_FROM
git checkout -b ${FIX_PREFIX}<slug> origin/$BRANCH_FROM
```

---

### 3. 执行修复

AI 按确认的方案修改代码。

---

### 4. 修复完成提示

```
✅ 修复完成！

🌿 分支：fix/login-token-not-cleared
📝 修改文件：
- src/interceptors/request.ts（+3 -1）

💡 后续操作：
- /req:commit - 提交修复代码
- /req:pr - 创建 PR
```

---

## 与其他修复方式的区别

| 方式 | 命令 | 文档 | 分支 | 适用场景 |
|------|------|------|------|---------|
| 轻量修复 | `/req:fix` | 无 | fix/slug | 日常小 bug，改动 < 5 个文件 |
| 有记录的修复 | `/req:new-quick` | QUICK 文档 | fix/QUICK-XXX-slug | 需要记录的修复，方便追溯 |
| 紧急修复 | `/req:branch hotfix` | 无 | hotfix/slug | 线上紧急问题，从主分支拉 |

**选择依据：**
- 改完就忘的小 bug → `/req:fix`
- 需要测试和记录的修复 → `/req:new-quick`
- 线上出问题了 → `/req:branch hotfix`

---

## 用户输入

$ARGUMENTS
