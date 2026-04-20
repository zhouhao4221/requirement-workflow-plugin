#!/bin/bash
# services-config.sh — 读取/校验 ~/.claude-diag/config/services.yaml
#
# 用法：
#   source services-config.sh        # 以函数库方式使用
#   services-config.sh list          # 输出服务名（每行一个）
#   services-config.sh hosts         # 输出主机白名单（去重）
#   services-config.sh show <name>   # 输出服务详情 JSON
#   services-config.sh validate      # 校验配置完整性

DIAG_HOME="${DIAG_HOME:-$HOME/.claude-diag}"
SERVICES_FILE="${DIAG_SERVICES_FILE:-$DIAG_HOME/config/services.yaml}"

_diag_yaml_to_json() {
    local file="$1"
    if command -v yq >/dev/null 2>&1; then
        yq -o=json "$file"
    elif command -v python3 >/dev/null 2>&1; then
        python3 - "$file" <<'PYEOF'
import sys, json
try:
    import yaml
except ImportError:
    sys.stderr.write("ERROR: 缺少 pyyaml，请执行 pip3 install pyyaml 或安装 yq\n")
    sys.exit(2)
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f) or {}
print(json.dumps(data, ensure_ascii=False))
PYEOF
    else
        echo "ERROR: 需要 yq 或 python3+pyyaml" >&2
        return 2
    fi
}

diag_config_exists() {
    [ -f "$SERVICES_FILE" ]
}

diag_list_services() {
    diag_config_exists || return 1
    _diag_yaml_to_json "$SERVICES_FILE" | jq -r '.services[]?.name // empty'
}

diag_list_hosts() {
    diag_config_exists || return 1
    _diag_yaml_to_json "$SERVICES_FILE" | jq -r '.services[]?.host // empty' | sort -u
}

diag_show_service() {
    local name="$1"
    diag_config_exists || return 1
    _diag_yaml_to_json "$SERVICES_FILE" | jq --arg n "$name" '.services[] | select(.name == $n)'
}

diag_host_in_whitelist() {
    local host="$1"
    diag_config_exists || return 1
    diag_list_hosts | grep -Fxq "$host"
}

diag_validate_config() {
    if ! diag_config_exists; then
        echo "❌ 配置文件不存在：$SERVICES_FILE" >&2
        echo "💡 执行 /diag:init 初始化" >&2
        return 1
    fi

    local json
    json=$(_diag_yaml_to_json "$SERVICES_FILE") || return 2

    local errors=0

    # 必填字段校验
    local invalid
    invalid=$(echo "$json" | jq -r '
        (.services // []) |
        to_entries |
        map(select(
            (.value.name // "") == "" or
            (.value.host // "") == "" or
            ((.value.log_paths // []) | length) == 0
        )) |
        .[] | "第 \(.key + 1) 项缺字段：name=\(.value.name // "-")，host=\(.value.host // "-")，log_paths=\(.value.log_paths // [] | length) 条"
    ')
    if [ -n "$invalid" ]; then
        echo "❌ 服务配置有缺失：" >&2
        echo "$invalid" >&2
        errors=$((errors + 1))
    fi

    # name 唯一
    local dup
    dup=$(echo "$json" | jq -r '
        (.services // []) |
        map(.name // empty) |
        group_by(.) |
        map(select(length > 1)) |
        .[] | .[0]
    ')
    if [ -n "$dup" ]; then
        echo "❌ service name 重复：$dup" >&2
        errors=$((errors + 1))
    fi

    # language_hint 枚举
    local bad_lang
    bad_lang=$(echo "$json" | jq -r '
        (.services // []) |
        map(
            . as $svc |
            select(
                ($svc.language_hint // "") != "" and
                ((["java","node","python","go","ruby","php"]) | index($svc.language_hint // "") | not)
            )
        ) |
        .[] | "service \(.name): language_hint=\(.language_hint) 非法（应为 java/node/python/go/ruby/php 之一）"
    ')
    if [ -n "$bad_lang" ]; then
        echo "❌ $bad_lang" >&2
        errors=$((errors + 1))
    fi

    if [ "$errors" -eq 0 ]; then
        local count
        count=$(echo "$json" | jq '.services | length')
        echo "✅ 配置校验通过（$count 个服务）"
    else
        return 1
    fi
}

# CLI 入口（仅在被直接执行时运行，source 时不触发）
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    case "${1:-}" in
        list) diag_list_services ;;
        hosts) diag_list_hosts ;;
        show) diag_show_service "${2:-}" ;;
        validate) diag_validate_config ;;
        *) echo "用法：$0 [list|hosts|show <name>|validate]" >&2; exit 1 ;;
    esac
fi
