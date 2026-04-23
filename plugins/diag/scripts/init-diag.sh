#!/bin/bash
# init-diag.sh — 初始化 ~/.claude-diag/ 目录与配置模板

set -e

DIAG_HOME="${DIAG_HOME:-$HOME/.claude-diag}"
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$PLUGIN_ROOT/templates/services.yaml.template"

echo "🔧 初始化 Diag 插件..."
echo ""

# 依赖检查
echo "📋 依赖检查："
missing=0

for tool in python3 jq ssh; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "  ✅ $tool"
    else
        echo "  ❌ $tool（必须）"
        missing=$((missing + 1))
    fi
done

# YAML 解析器二选一
if command -v yq >/dev/null 2>&1; then
    echo "  ✅ yq"
elif python3 -c "import yaml" 2>/dev/null; then
    echo "  ✅ python3 pyyaml"
else
    echo "  ❌ yq 或 python3+pyyaml（必须，二选一）"
    echo "     安装：brew install yq  或  pip3 install pyyaml"
    missing=$((missing + 1))
fi

if [ "$missing" -gt 0 ]; then
    echo ""
    echo "⚠️  缺少必要依赖，请先安装后重试"
    exit 1
fi

echo ""

# 创建目录
mkdir -p "$DIAG_HOME/config" "$DIAG_HOME/audit" "$DIAG_HOME/tmp" "$DIAG_HOME/runtime"
chmod 700 "$DIAG_HOME"
chmod 700 "$DIAG_HOME/config"
chmod 700 "$DIAG_HOME/audit"
chmod 700 "$DIAG_HOME/tmp"
chmod 700 "$DIAG_HOME/runtime"

# 配置模板
SERVICES_FILE="$DIAG_HOME/config/services.yaml"
if [ ! -f "$SERVICES_FILE" ]; then
    cp "$TEMPLATE" "$SERVICES_FILE"
    chmod 600 "$SERVICES_FILE"
    echo "✅ 已创建配置模板：$SERVICES_FILE"
else
    echo "ℹ️  配置已存在（未覆盖）：$SERVICES_FILE"
fi

echo ""
echo "📂 目录结构："
echo "  $DIAG_HOME/"
echo "  ├── config/services.yaml     （服务清单，请编辑为真实主机）"
echo "  ├── audit/                   （审计日志，按日切分）"
echo "  ├── tmp/                     （临时 session 文件，2h TTL 自动清理）"
echo "  └── runtime/                 （Hook 短效 marker，自动清理）"
echo ""
echo "💡 下一步："
echo "  1. 编辑 ${SERVICES_FILE}，登记服务"
echo "  2. 执行 /diag:diagnose <报错描述> 开始诊断"
