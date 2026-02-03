#!/bin/bash
# update-status.sh
# 更新需求文档状态

FILE_PATH="$1"
NEW_STATUS="$2"

if [ -z "$FILE_PATH" ] || [ -z "$NEW_STATUS" ]; then
    echo "用法: update-status.sh <需求文档路径> <新状态>"
    echo "状态: 草稿|待评审|评审通过|开发中|测试中|已完成"
    exit 1
fi

if [ ! -f "$FILE_PATH" ]; then
    echo "文件不存在: $FILE_PATH"
    exit 1
fi

# 状态映射
declare -A STATUS_MAP
STATUS_MAP["草稿"]="📝 草稿"
STATUS_MAP["待评审"]="👀 待评审"
STATUS_MAP["评审通过"]="✅ 评审通过"
STATUS_MAP["开发中"]="🔨 开发中"
STATUS_MAP["测试中"]="🧪 测试中"
STATUS_MAP["已完成"]="🎉 已完成"

# 更新元信息中的状态
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s/| 状态 | .* |/| 状态 | $NEW_STATUS |/" "$FILE_PATH"
else
    # Linux
    sed -i "s/| 状态 | .* |/| 状态 | $NEW_STATUS |/" "$FILE_PATH"
fi

echo "状态已更新为: $NEW_STATUS"

# 同步到全局缓存
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/sync-cache.sh" "$FILE_PATH"
