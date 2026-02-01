#!/bin/bash
# validate-requirement.sh
# 验证需求文档格式和完整性

FILE_PATH="$1"

# 非需求文档直接跳过
if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
    exit 0
fi
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
