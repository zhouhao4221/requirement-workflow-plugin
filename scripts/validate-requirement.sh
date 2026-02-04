#!/bin/bash
# validate-requirement.sh
# 验证需求文档格式和完整性
# 由 PostToolUse Hook 触发（Write/Edit 工具操作后）
#
# 仅对 docs/requirements/ 目录下的需求文档（REQ-XXX、QUICK-XXX）进行验证

FILE_PATH="$1"

# 空路径或文件不存在，静默跳过
if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# 仅处理 docs/requirements/ 目录下的文件
if [[ ! "$FILE_PATH" =~ docs/requirements/ ]]; then
    exit 0
fi

FILENAME=$(basename "$FILE_PATH")

# 仅对 REQ/QUICK 需求文档验证章节
if [[ "$FILENAME" =~ ^(REQ|QUICK)-[0-9]+ ]]; then
    echo "验证需求文档: $FILENAME"

    MISSING=""
    if ! grep -q "## 元信息" "$FILE_PATH"; then
        MISSING="$MISSING\n  - 元信息"
    fi
    if ! grep -q "## 一、需求描述" "$FILE_PATH"; then
        MISSING="$MISSING\n  - 需求描述"
    fi
    if ! grep -q "## 二、功能清单" "$FILE_PATH"; then
        MISSING="$MISSING\n  - 功能清单"
    fi

    if [ -n "$MISSING" ]; then
        echo -e "缺少章节:$MISSING"
    fi
fi
