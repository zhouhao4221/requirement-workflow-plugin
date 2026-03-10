---
description: 生成版本说明 - 基于 Git 记录生成 Changelog
---

# 生成版本说明

根据 Git 提交记录和已完成需求，生成版本升级说明文档。

> 此命令**不受仓库角色限制**，readonly 仓库也可执行。
> 生成的文件保存在 `docs/changelogs/` 目录，不触发缓存同步。

## 命令格式

```
/req:changelog <version> [--from=<tag|commit>] [--to=<tag|commit>]
```

**参数说明：**
- `<version>`：**必填**，版本号（如 `v1.2.0`、`1.2.0`）
- `--from`：可选，起始点（tag 或 commit hash），默认为上一个 git tag
- `--to`：可选，结束点（tag 或 commit hash），默认为 HEAD

**示例：**
- `/req:changelog v1.2.0` — 从上一个 tag 到 HEAD
- `/req:changelog v1.2.0 --from=v1.1.0` — 从 v1.1.0 到 HEAD
- `/req:changelog v1.2.0 --from=v1.1.0 --to=v1.2.0` — 指定完整范围
- `/req:changelog v1.2.0 --from=abc1234` — 从某个 commit 开始

---

## 执行流程

### 1. 参数校验

```python
if not version:
    print("❌ 请指定版本号")
    print("用法：/req:changelog <version> [--from=<tag|commit>] [--to=<tag|commit>]")
    print("示例：/req:changelog v1.2.0")
    exit()
```

### 2. 确定 Git 范围

```bash
# --to 参数，默认 HEAD
TO_REF=${to:-HEAD}

# --from 参数，默认上一个 tag
if [ -z "$FROM_REF" ]; then
    # 自动检测上一个 tag
    FROM_REF=$(git describe --tags --abbrev=0 $TO_REF^ 2>/dev/null)
fi

if [ -z "$FROM_REF" ]; then
    # 没有任何 tag，使用第一个 commit
    FROM_REF=$(git rev-list --max-parents=0 HEAD)
    echo "⚠️ 未找到 git tag，将从仓库首次提交开始"
fi

echo "📌 版本范围：$FROM_REF..$TO_REF"
```

### 3. 读取 Git 提交记录

```bash
# 获取提交列表（hash、日期、消息）
git log $FROM_REF..$TO_REF --pretty=format:"%h|%ai|%s" --no-merges
```

提取信息：
- 提交 hash（短）
- 提交日期
- 提交消息（用于分类和展示）

### 4. 按提交前缀分类

将提交按前缀分类（中文优先，兼容英文）：

| 中文前缀 | 英文前缀 | 分类 |
|---------|---------|------|
| `新功能` | `feat` | 新功能 (Features) |
| `修复` | `fix` | 问题修复 (Bug Fixes) |
| `重构` | `refactor` | 重构优化 (Refactoring) |
| `优化` | `perf` | 性能优化 (Performance) |
| `文档` | `docs` | 文档更新 (Documentation) |
| `测试` | `test` | 测试 (Tests) |
| `构建`/`样式` | `chore`/`ci`/`build`/`style` | 其他变更 (Others) |
| 无前缀/不识别 | 无前缀/不识别 | 其他变更 (Others) |

**分类规则：**
- 按 `前缀: 描述` 格式解析（中文或英文前缀均可）
- 无法识别前缀的统一归入「其他变更」
- 空分类不输出对应章节

### 5. 关联已完成需求

```python
# 解析存储路径
PROJECT = read_settings("requirementProject")
ROLE = read_settings("requirementRole")

if ROLE == "readonly":
    completed_dir = f"~/.claude-requirements/projects/{PROJECT}/completed/"
elif ROLE == "primary":
    completed_dir = "docs/requirements/completed/"
    # 本地不存在时回退到缓存
    if not exists(completed_dir) and PROJECT:
        completed_dir = f"~/.claude-requirements/projects/{PROJECT}/completed/"
else:
    completed_dir = "docs/requirements/completed/"

# 从 commit messages 中提取 REQ-XXX / QUICK-XXX 编号
req_ids = extract_req_ids_from_commits(commits)  # 正则匹配 REQ-\d+ 和 QUICK-\d+

# 读取对应的需求文档，提取标题和类型
related_reqs = []
for req_id in req_ids:
    doc = find_requirement(completed_dir, req_id)
    if doc:
        related_reqs.append({
            "id": req_id,
            "title": extract_title(doc),
            "type": extract_type(doc)
        })
```

也扫描 active/ 目录中的需求（可能需求尚未完成但已有 commit）。

### 6. 检查目标文件

```bash
OUTPUT_DIR=docs/changelogs
OUTPUT_FILE=$OUTPUT_DIR/<version>.md

# 创建目录（如不存在）
mkdir -p $OUTPUT_DIR

# 检查是否已存在
if [ -f "$OUTPUT_FILE" ]; then
    echo "⚠️ 版本说明已存在：$OUTPUT_FILE"
    # 用户确认后继续，否则终止
fi
```

### 7. 生成版本说明文档

使用 Write 工具生成 `docs/changelogs/<version>.md`，格式如下：

```markdown
# <version> 版本说明

> 发布日期：YYYY-MM-DD
> 版本范围：<from-ref>..<to-ref>
> 提交数量：N

## 关联需求

| 编号 | 标题 | 类型 |
|------|------|------|
| REQ-XXX | 需求标题 | 后端 |
| QUICK-XXX | 快速修复标题 | 全栈 |

## 新功能 (Features)

- 描述 (`hash`)

## 问题修复 (Bug Fixes)

- 描述 (`hash`)

## 重构优化 (Refactoring)

- 描述 (`hash`)

## 性能优化 (Performance)

- 描述 (`hash`)

## 其他变更

- 描述 (`hash`)

---
*由 /req:changelog 自动生成*
```

**格式规则：**
- 没有匹配提交的分类章节**不输出**（不保留空章节）
- 没有关联需求时**不输出**「关联需求」章节
- 每条提交包含简短 hash 方便回溯
- 提交按时间倒序排列（最新在前）

### 8. 输出生成报告

```
✅ 版本说明已生成！

═══════════════════════════════════════════════
📋 Changelog：<version>
═══════════════════════════════════════════════

📌 版本信息
├── 版本号：<version>
├── 发布日期：YYYY-MM-DD
├── 版本范围：<from-ref>..<to-ref>
└── 提交数量：N

📊 变更统计
├── 新功能：X
├── 问题修复：X
├── 重构优化：X
├── 性能优化：X
└── 其他变更：X

📋 关联需求：X 个
├── REQ-001 需求标题
└── QUICK-003 快速修复标题

📁 文件位置
docs/changelogs/<version>.md

═══════════════════════════════════════════════

💡 后续操作：
- 查看文件：cat docs/changelogs/<version>.md
- 重新生成：/req:changelog <version> --from=<tag>
- 创建 git tag：git tag <version>
```

---

## 边界情况处理

| 场景 | 处理方式 |
|------|---------|
| 没有 git tag | 从仓库首次提交开始，显示警告 |
| 范围内无提交 | 终止操作，提示范围无效 |
| 文件已存在 | 询问用户是否覆盖 |
| 无关联需求 | 省略「关联需求」章节 |
| commit 不遵循 conventional commits | 归入「其他变更」 |
| docs/changelogs/ 目录不存在 | 自动创建 |

## 用户输入

$ARGUMENTS
