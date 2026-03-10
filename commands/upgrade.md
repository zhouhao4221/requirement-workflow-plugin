---
description: 升级需求 - 将快速修复升级为正式需求
---

# 升级快速修复为正式需求

将 QUICK 快速修复升级为 REQ 正式需求，适用于范围扩大或需要完整评审的场景。

## 命令格式

```
/req:upgrade <QUICK-XXX>
```

---

## 执行流程

### 0. 解析存储路径

```bash
# 本地存储路径（主存储）
LOCAL_ROOT=docs/requirements
LOCAL_ACTIVE=$LOCAL_ROOT/active
LOCAL_COMPLETED=$LOCAL_ROOT/completed

# 检查当前仓库绑定的项目（用于缓存同步）
PROJECT=$(cat .claude/settings.local.json 2>/dev/null | jq -r '.requirementProject // empty')

if [ -n "$PROJECT" ]; then
    CACHE_ROOT=~/.claude-requirements/projects/$PROJECT
    CACHE_ACTIVE=$CACHE_ROOT/active
    CACHE_COMPLETED=$CACHE_ROOT/completed
fi
```

### 1. 定位源文件

查找 QUICK-XXX 需求文档：

```bash
# 优先本地，其次缓存
if [ -f "$LOCAL_ACTIVE/QUICK-XXX-*.md" ]; then
    SOURCE_FILE=$LOCAL_ACTIVE/QUICK-XXX-*.md
    SOURCE_LOCATION="local"
elif [ -f "$CACHE_ACTIVE/QUICK-XXX-*.md" ]; then
    SOURCE_FILE=$CACHE_ACTIVE/QUICK-XXX-*.md
    SOURCE_LOCATION="cache"
else
    echo "❌ 未找到 QUICK-XXX 需求文档"
    exit 1
fi
```

**状态检查**：
- 已完成的 QUICK 不允许升级（已归档）
- 仅允许升级 active/ 目录中的需求

### 2. 读取源文件内容

解析 QUICK 需求的关键信息：

```bash
./scripts/parse-requirement.sh "$SOURCE_FILE"
```

提取：
- 编号、标题
- 改动类型、端类型
- 当前状态
- 问题描述（现象、期望）
- 实现方案（涉及文件）
- 验证方式

### 3. 生成新编号

格式：`REQ-XXX`（三位数字）

```bash
# 从本地和缓存获取最大 REQ 编号
LOCAL_MAX=$(ls $LOCAL_ACTIVE/ $LOCAL_COMPLETED/ 2>/dev/null | grep -oE 'REQ-[0-9]+' | sort -t'-' -k2 -n | tail -1)
CACHE_MAX=$(ls $CACHE_ACTIVE/ $CACHE_COMPLETED/ 2>/dev/null | grep -oE 'REQ-[0-9]+' | sort -t'-' -k2 -n | tail -1)

# 取两者中较大的编号 + 1
NEW_REQ_ID=REQ-$(printf "%03d" $((MAX_NUM + 1)))
```

### 4. 内容转换

#### 4.1 元信息转换

| QUICK 字段 | REQ 字段 | 转换规则 |
|-----------|---------|---------|
| 编号 QUICK-XXX | 编号 REQ-XXX | 新生成的编号 |
| 改动类型 | 类型 | bug修复→后端, 小功能→后端 |
| 端类型 | 类型 | 后端/前端/全栈 直接映射 |
| 状态 | 状态 | 见状态映射表 |
| 模块 | 模块 | 直接复制 |
| 关联需求 | 关联需求 | 直接复制，新增「升级自 QUICK-XXX」 |

**状态映射**：

| QUICK 状态 | REQ 状态 |
|-----------|---------|
| 草稿 | 草稿 |
| 方案确认 | 评审通过 |
| 开发中 | 开发中 |
| 已完成 | ❌ 不允许升级 |

#### 4.2 生命周期转换

从 4 阶段扩展为 6 阶段：

```markdown
## 生命周期

- [x] 📝 草稿（编写中）      ← 根据状态勾选
- [ ] 👀 待评审
- [ ] ✅ 评审通过
- [ ] 🔨 开发中
- [ ] 🧪 测试中
- [ ] 🎉 已完成
```

#### 4.3 内容章节转换

| QUICK 章节 | REQ 章节 | 转换方式 |
|-----------|---------|---------|
| 问题描述.现象 | 需求描述.背景 | 直接复制 |
| 问题描述.期望 | 需求描述.目标 | 直接复制 |
| - | 需求描述.价值 | **待补充** |
| 实现方案.涉及文件 | 文件改动清单 | 按分层重组 |
| 验证方式 | 测试要点 | 直接复制 |
| - | 功能清单 | **待补充** |
| - | 业务规则 | **待补充** |
| - | API 设计 | **待补充**（如涉及） |
| - | 数据模型 | **待补充**（如涉及） |
| - | 实现步骤 | **待补充** |

### 5. 显示转换预览

```
🔄 升级预览：QUICK-001 → REQ-007

📋 原快速修复：
  编号：QUICK-001
  标题：修复用户登录失败问题
  状态：开发中
  改动：3 个文件

📋 新正式需求：
  编号：REQ-007
  标题：修复用户登录失败问题
  类型：后端
  状态：开发中（保持）

📝 需补充的章节：
  - 需求描述.价值
  - 功能清单
  - 业务规则
  - 实现步骤

原文件处理：
  [ ] 归档到 completed/（保留历史）
  [ ] 直接删除（减少冗余）

```

### 6. 用户确认后执行

#### 6.1 创建新 REQ 文件

使用 requirement-template.md 模板，填充转换后的内容：

```bash
# 写入本地
TARGET_FILE=$LOCAL_ACTIVE/$NEW_REQ_ID-$TITLE.md
```

#### 6.2 处理原 QUICK 文件

根据用户选择：

**归档**：
```bash
# 在原文件末尾添加升级标记
echo -e "\n---\n\n> ⬆️ 已升级为 $NEW_REQ_ID（$(date +%Y-%m-%d)）" >> $SOURCE_FILE

# 移动到 completed/
mv $SOURCE_FILE $LOCAL_COMPLETED/
```

**删除**：
```bash
rm $SOURCE_FILE
```

#### 6.3 同步缓存

```bash
if [ -n "$PROJECT" ]; then
    # 同步新 REQ 文件
    cp $TARGET_FILE $CACHE_ACTIVE/

    # 根据用户选择处理缓存中的 QUICK 文件
    if [ 归档 ]; then
        mv $CACHE_ACTIVE/QUICK-XXX-*.md $CACHE_COMPLETED/
    else
        rm $CACHE_ACTIVE/QUICK-XXX-*.md
    fi
fi
```

### 7. 触发需求完善

升级完成后，触发 requirement-analyzer 技能补充待填章节：

```
✅ 升级成功！

📋 新需求：REQ-007 修复用户登录失败问题
📁 文件：docs/requirements/active/REQ-007-修复用户登录失败问题.md
📊 状态：开发中

📝 需要补充以下章节：
1. 需求描述.价值
2. 功能清单
3. 业务规则
4. 实现步骤

```

调用 requirement-analyzer 技能引导完善各章节。

---

## 限制条件

1. **仅限 active/ 目录**：已完成（completed/）的 QUICK 不能升级
2. **状态限制**：「已完成」状态的 QUICK 不允许升级
3. **编号唯一性**：生成的 REQ 编号必须唯一

---

## 用户输入

$ARGUMENTS
