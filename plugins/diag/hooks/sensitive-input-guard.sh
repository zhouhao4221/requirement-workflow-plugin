#!/bin/bash
# sensitive-input-guard.sh — UserPromptSubmit Hook
# 拦截用户聊天中的敏感输入（密码 / token / 私钥）
#
# 检测策略：
# - 常见凭证关键词 + 后续非空白内容
# - 已知 API key 前缀（OpenAI sk- / AWS AKIA / GitHub gh[pousr]_）
# - SSH/RSA 私钥头

INPUT=$(cat)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // .user_prompt // empty')

[ -z "$PROMPT" ] && exit 0

# -E ERE，支持大多数常见场景
PATTERNS=(
    # 中英文密码 + 赋值分隔
    '(密码|口令|password|passwd|pwd)[[:space:]]*(是|为|:|=)[[:space:]]*[^[:space:]]{4,}'
    # API token / key
    '(token|api[_-]?key|bearer|secret|access[_-]?key|私钥|密钥)[[:space:]]*[:=][[:space:]]*[A-Za-z0-9._~+/=-]{16,}'
    # OpenAI / Anthropic 风格
    'sk-[A-Za-z0-9_-]{32,}'
    # AWS access key
    'AKIA[0-9A-Z]{16}'
    # GitHub PAT
    'gh[pousr]_[A-Za-z0-9]{36,}'
    # 私钥 PEM 头
    '-----BEGIN [A-Z ]*PRIVATE KEY-----'
)

MATCHED=""
for pat in "${PATTERNS[@]}"; do
    # 使用 -e -- 防止以 - 开头的 pattern 被当成选项（如 -----BEGIN...）
    if printf '%s' "$PROMPT" | grep -qE -e "$pat"; then
        MATCHED="$pat"
        break
    fi
done

if [ -n "$MATCHED" ]; then
    echo "🛑 消息中疑似包含敏感信息（密码/token/私钥），已拦截不提交给 AI。" >&2
    echo "" >&2
    echo "安全替代方式：" >&2
    echo "  1. SSH 密钥 → 使用 SSH Agent 或 ~/.ssh/config" >&2
    echo "  2. DB 凭证 → 写入 ~/.claude-diag/config/（600 权限），插件只读引用" >&2
    echo "  3. API token → 环境变量 / 受保护配置文件" >&2
    exit 2
fi

exit 0
