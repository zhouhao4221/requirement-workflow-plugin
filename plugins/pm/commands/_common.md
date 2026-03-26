# 公共逻辑参考

> 此文档定义 pm 插件所有命令共用的数据采集逻辑，各命令直接引用。

## 与 req 插件的关系

pm 插件是 req 插件产出数据的**只读消费者**：
- 读取 PRD、需求文档、模块文档、INDEX.md
- 读取 Git 提交记录、分支、Tag
- **不修改**任何需求文档，不触发缓存同步
- 支持 `primary` 和 `readonly` 仓库角色

## 需求数据路径解析

```python
# 读取项目配置
PROJECT = read_settings("requirementProject")  # .claude/settings.local.json
ROLE = read_settings("requirementRole")

if ROLE == "readonly":
    ROOT = f"~/.claude-requirements/projects/{PROJECT}"
elif ROLE == "primary":
    ROOT = "docs/requirements"
    CACHE_ROOT = f"~/.claude-requirements/projects/{PROJECT}" if PROJECT else None
else:
    ROOT = "docs/requirements"
    CACHE_ROOT = None

# 关键路径
ACTIVE = f"{ROOT}/active/"
COMPLETED = f"{ROOT}/completed/"
MODULES = f"{ROOT}/modules/"
PRD = f"{ROOT}/PRD.md"
INDEX = f"{ROOT}/INDEX.md"
```

**读取策略**：
- `primary`：优先本地 → 本地不存在时从缓存读取
- `readonly`：直接从缓存读取

## 数据采集层

所有命令共享以下数据采集能力，按需调用：

### 1. 需求数据采集

```python
def collect_requirements():
    """采集所有需求的元信息和状态"""
    reqs = []

    # 扫描 active/ 和 completed/ 目录
    for dir in [ACTIVE, COMPLETED]:
        for file in glob(f"{dir}/*.md"):
            doc = read_file(file)
            reqs.append({
                "id": extract_id(doc),           # REQ-XXX / QUICK-XXX
                "title": extract_title(doc),       # 标题
                "type": extract_type(doc),         # 后端/前端/全栈
                "status": extract_status(doc),     # 当前状态
                "module": extract_module(doc),     # 所属模块
                "priority": extract_priority(doc), # 优先级
                "created": extract_created(doc),   # 创建日期
                "updated": extract_updated(doc),   # 最后更新日期
                "progress": extract_progress(doc), # 功能点完成进度 (done/total)
                "test_progress": extract_test(doc),# 测试进度 (done/total)
                "branch": extract_branch(doc),     # 关联分支
                "related": extract_related(doc),   # 关联需求
                "is_completed": "completed" in file.path,
            })

    return reqs
```

### 2. PRD 数据采集

```python
def collect_prd():
    """采集 PRD 文档信息"""
    if not exists(PRD):
        return None

    doc = read_file(PRD)
    return {
        "vision": extract_section(doc, "产品愿景"),
        "features": extract_section(doc, "功能规划"),
        "tech_stack": extract_section(doc, "技术选型"),
        "req_tracking": extract_section(doc, "需求追踪"),
        "sections_filled": count_filled_sections(doc),
        "sections_total": count_total_sections(doc),
    }
```

### 3. Git 数据采集

```python
def collect_git_stats(from_date=None, to_date=None, from_ref=None, to_ref=None):
    """采集 Git 统计数据"""

    # 时间范围参数
    date_args = ""
    if from_date:
        date_args += f" --since='{from_date}'"
    if to_date:
        date_args += f" --until='{to_date}'"

    # ref 范围参数
    ref_range = ""
    if from_ref and to_ref:
        ref_range = f"{from_ref}..{to_ref}"
    elif from_ref:
        ref_range = f"{from_ref}..HEAD"

    return {
        # 提交统计
        "total_commits": git_count_commits(date_args, ref_range),
        "commits_by_author": git_commits_by_author(date_args, ref_range),
        "commits_by_date": git_commits_by_date(date_args, ref_range),
        "commits_by_type": git_commits_by_type(date_args, ref_range),  # feat/fix/refactor...

        # 代码变更统计
        "insertions": git_stat_insertions(date_args, ref_range),
        "deletions": git_stat_deletions(date_args, ref_range),
        "files_changed": git_stat_files_changed(date_args, ref_range),

        # 分支统计
        "active_branches": git_active_branches(),
        "recent_merges": git_recent_merges(date_args),

        # Tag 统计
        "tags": git_tags(),
        "latest_tag": git_latest_tag(),
    }
```

### 4. 模块数据采集

```python
def collect_modules():
    """采集模块文档信息"""
    modules = []
    for file in glob(f"{MODULES}/*.md"):
        doc = read_file(file)
        modules.append({
            "name": extract_module_name(doc),
            "description": extract_module_desc(doc),
            "req_count": count_related_reqs(doc),
        })
    return modules
```

## Git 统计命令参考

以下是各采集项对应的 Git 命令：

```bash
# 提交总数
git log --oneline $REF_RANGE $DATE_ARGS --no-merges | wc -l

# 按作者统计提交
git shortlog -sn --no-merges $REF_RANGE $DATE_ARGS

# 按日期统计提交（每天）
git log --format='%ad' --date=short $REF_RANGE $DATE_ARGS --no-merges | sort | uniq -c

# 按提交类型统计（feat/fix/refactor/...）
git log --oneline $REF_RANGE $DATE_ARGS --no-merges | \
  sed 's/^[a-f0-9]* //' | \
  grep -oE '^(feat|fix|refactor|perf|docs|test|chore|style|ci|build|新功能|修复|重构|优化|文档|测试|构建)' | \
  sort | uniq -c | sort -rn

# 代码变更统计（增删行数）
git diff --shortstat $REF_RANGE
# 或按时间范围
git log --shortstat $DATE_ARGS --no-merges | grep 'files changed' | \
  awk '{ins+=$4; del+=$6} END {print ins, del}'

# 变更文件数
git diff --name-only $REF_RANGE | wc -l

# 活跃分支（最近有提交的）
git branch -a --sort=-committerdate | head -20

# 最近合并
git log --merges --oneline $DATE_ARGS | head -10

# Tag 列表
git tag --sort=-creatordate | head -10

# 最新 tag
git describe --tags --abbrev=0 2>/dev/null
```

## 输出保存机制

所有命令生成内容后，统一提供保存选项：

```python
def offer_save(content, suggested_path):
    """提供保存选项"""
    print(f"\n内容已生成。是否保存到项目文档？")
    print(f"   保存路径：{suggested_path}")
    print(f"   [回车] 保存  |  [n] 不保存")

    # 等待用户输入
    choice = input()
    if choice.lower() != 'n':
        # 确保目录存在
        mkdir_p(dirname(suggested_path))
        write_file(suggested_path, content)
        print(f"已保存到 {suggested_path}")
    else:
        print("已跳过保存")
```

**保存路径约定**：

```
docs/reports/
├── weekly/              # 周报
│   └── 2026-03-26.md
├── monthly/             # 月报
│   └── 2026-03.md
├── milestone/           # 里程碑报告
│   └── v1.6.0.md
├── stats/               # 统计报告
│   └── 2026-03-26.md
├── plans/               # 方案文档
│   └── <主题>.md
├── risk/                # 风险报告
│   └── 2026-03-26.md
└── custom/              # 自定义内容
    └── <标题>.md
```

## 时间范围解析

多个命令支持 `--from` 和 `--to` 参数，统一解析逻辑：

```python
def parse_date_range(from_arg=None, to_arg=None, default_range="week"):
    """解析时间范围"""
    today = date.today()

    if from_arg and to_arg:
        return (from_arg, to_arg)

    if from_arg:
        return (from_arg, today.isoformat())

    # 默认范围
    if default_range == "week":
        # 本周一到今天
        monday = today - timedelta(days=today.weekday())
        return (monday.isoformat(), today.isoformat())
    elif default_range == "month":
        # 本月1日到今天
        first_day = today.replace(day=1)
        return (first_day.isoformat(), today.isoformat())
    elif default_range == "all":
        return (None, None)
```

## 输出格式规范

### 格式原则

**禁止使用 emoji**：所有输出内容不使用任何 emoji 图标，便于导出为 Word、PDF 等文档格式。
使用**加粗文字**替代图标来标记重点和分类。

### 标题栏

所有命令输出统一使用以下标题栏格式：

```
═══════════════════════════════════════════════
<命令标题>
═══════════════════════════════════════════════
项目：<project> (<role>) | 日期：YYYY-MM-DD
───────────────────────────────────────────────
```

### 数据呈现

- 表格：用 Markdown 表格展示结构化数据
- 树形：用 `├──` `└──` 展示层级关系
- 进度：用百分比展示完成度，不使用进度条字符
- 趋势：用文字描述趋势（数据量不大时不强制图表）
- 强调：用 `**加粗**` 标记分类和重点，不用 emoji
- 级别：风险级别用 **严重** / **警告** / **提示** 纯文字标记

### 尾部操作提示

```
═══════════════════════════════════════════════

**相关命令：**
- /pm:xxx - 说明
- /pm:xxx - 说明
```
