#!/bin/bash
# sync-cache.sh
# 需求文档写入后自动同步到全局缓存
# 由 PostToolUse Hook 触发

FILE_PATH="$1"

# 非需求文档直接跳过
if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
    exit 0
fi
if [[ ! "$FILE_PATH" =~ docs/requirements/.+\.md$ ]]; then
    exit 0
fi

# 检查是否是 REQ 或 QUICK 需求文档
FILENAME=$(basename "$FILE_PATH")
if [[ ! "$FILENAME" =~ ^(REQ|QUICK)-[0-9]+ ]]; then
    # 非需求文档（可能是 INDEX.md、template.md 或模块文档）
    # 也需要同步模块文档
    if [[ "$FILE_PATH" =~ docs/requirements/modules/ ]]; then
        IS_MODULE=true
    else
        exit 0
    fi
fi

# 查找项目根目录（向上查找 .claude 目录）
find_project_root() {
    local dir="$1"
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/.claude" ]; then
            echo "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    return 1
}

PROJECT_ROOT=$(find_project_root "$(dirname "$FILE_PATH")")
if [ -z "$PROJECT_ROOT" ]; then
    exit 0
fi

# 读取绑定的项目名称
SETTINGS_FILE="$PROJECT_ROOT/.claude/settings.local.json"
if [ ! -f "$SETTINGS_FILE" ]; then
    exit 0
fi

PROJECT_NAME=$(grep -o '"requirementProject"[[:space:]]*:[[:space:]]*"[^"]*"' "$SETTINGS_FILE" | sed 's/.*"requirementProject"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
if [ -z "$PROJECT_NAME" ]; then
    exit 0
fi

# 全局缓存目录
CACHE_ROOT="$HOME/.claude-requirements/projects/$PROJECT_NAME"
if [ ! -d "$CACHE_ROOT" ]; then
    # 缓存目录不存在，可能项目尚未初始化，跳过
    exit 0
fi

# 计算相对路径并确定目标路径
# FILE_PATH: /path/to/project/docs/requirements/active/REQ-001-xxx.md
# 需要转换为: ~/.claude-requirements/projects/xxx/active/REQ-001-xxx.md
REL_PATH="${FILE_PATH#$PROJECT_ROOT/docs/requirements/}"

# 检查是活跃需求还是已完成需求
if [[ "$REL_PATH" =~ ^active/ ]]; then
    TARGET_DIR="$CACHE_ROOT/active"
elif [[ "$REL_PATH" =~ ^completed/ ]]; then
    TARGET_DIR="$CACHE_ROOT/completed"
elif [[ "$REL_PATH" =~ ^modules/ ]]; then
    TARGET_DIR="$CACHE_ROOT/modules"
else
    # 可能是根目录下的文件（如 INDEX.md），同步到缓存根目录
    TARGET_DIR="$CACHE_ROOT"
fi

# 确保目标目录存在
mkdir -p "$TARGET_DIR"

# 同步文件
TARGET_FILE="$TARGET_DIR/$FILENAME"
cp "$FILE_PATH" "$TARGET_FILE"

if [ $? -eq 0 ]; then
    echo "已同步到缓存: $PROJECT_NAME"
else
    echo "缓存同步失败: $TARGET_FILE" >&2
    exit 1
fi
