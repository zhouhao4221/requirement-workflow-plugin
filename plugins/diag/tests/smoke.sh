#!/bin/bash
# smoke.sh — Diag 插件 T1-T9 冒烟测试
#
# 用法：从仓库根目录执行
#   bash plugins/diag/tests/smoke.sh
#
# 覆盖范围：
#   T1 主机白名单：登记主机放行 / 未登记拒绝 / 非 ssh 忽略
#   T2 命令白名单：白名单 verb 放行 / 未知 verb 拒绝 / 登录 shell 拒绝 / rm 拒绝
#   T3 写操作阻断：重定向 / tee / systemctl / docker rm / kubectl delete /
#                  mysql INSERT / sudo / find -delete / apt install
#   T4 敏感输入拦截：password / bearer / AWS / sk-key / 普通消息
#   T5 Hook 完整性：全部存在放行 / 缺失时拒绝
#   T9 审计完整性：JSONL 字段齐全
#
# 不覆盖（依赖 AI 行为或真实环境，需人工验证）：
#   T6 多栈堆栈识别（SKILL.md 策略）
#   T7 本地代码关联（真实代码仓库）
#   T8 零改动验证（插件 allowed-tools 约束 + 命令文档）
#   T10 审计查询（/diag:audit 命令）

set -e

PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR=$(mktemp -d)
export DIAG_HOME="$TMPDIR/.claude-diag"
export CLAUDE_PLUGIN_ROOT="$PLUGIN"
export CLAUDE_SESSION_ID="smoke-$$"

mkdir -p "$DIAG_HOME/config"
cat > "$DIAG_HOME/config/services.yaml" << 'EOF'
services:
  - name: order-api
    host: prod-web-01
    log_paths:
      - /var/log/app/order.log
    language_hint: java
EOF

PASS=0
FAIL=0
RESULTS=()

assert_deny() {
    local name="$1"; local cmd="$2"; local hook="$3"
    local out
    out=$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}' | bash "$PLUGIN/hooks/$hook.sh")
    if echo "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
        RESULTS+=("✅ $name")
        PASS=$((PASS+1))
    else
        RESULTS+=("❌ $name (not denied)")
        FAIL=$((FAIL+1))
    fi
}

assert_allow() {
    local name="$1"; local cmd="$2"; local hook="$3"
    local out
    out=$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}' | bash "$PLUGIN/hooks/$hook.sh")
    if [ -z "$out" ]; then
        RESULTS+=("✅ $name")
        PASS=$((PASS+1))
    else
        local reason
        reason=$(echo "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // "no reason"')
        RESULTS+=("❌ $name (unexpectedly denied: ${reason})")
        FAIL=$((FAIL+1))
    fi
}

assert_prompt_deny() {
    local name="$1"; local prompt="$2"
    local ec
    echo "{\"prompt\": \"${prompt}\"}" | bash "$PLUGIN/hooks/sensitive-input-guard.sh" >/dev/null 2>&1 && ec=0 || ec=$?
    if [ "$ec" -eq 2 ]; then
        RESULTS+=("✅ $name")
        PASS=$((PASS+1))
    else
        RESULTS+=("❌ $name (exit=${ec}, expected 2)")
        FAIL=$((FAIL+1))
    fi
}

assert_prompt_allow() {
    local name="$1"; local prompt="$2"
    local ec
    echo "{\"prompt\": \"${prompt}\"}" | bash "$PLUGIN/hooks/sensitive-input-guard.sh" >/dev/null 2>&1 && ec=0 || ec=$?
    if [ "$ec" -eq 0 ]; then
        RESULTS+=("✅ $name")
        PASS=$((PASS+1))
    else
        RESULTS+=("❌ $name (exit=${ec}, expected 0)")
        FAIL=$((FAIL+1))
    fi
}

# ===== T1: 主机白名单 =====
assert_allow "T1a host-whitelist: registered host allowed" \
    "ssh prod-web-01 tail -n 100 /var/log/app/order.log" "host-whitelist"
assert_deny "T1b host-whitelist: unknown host denied" \
    "ssh unknown-host tail /etc/passwd" "host-whitelist"
assert_allow "T1c host-whitelist: non-ssh ignored" \
    "cat /etc/hosts" "host-whitelist"

# ===== T2: 命令白名单 =====
assert_allow "T2a command-whitelist: tail allowed" \
    "ssh prod-web-01 tail -n 100 /var/log/app/order.log" "command-whitelist"
assert_allow "T2b command-whitelist: grep | head allowed" \
    "ssh prod-web-01 'grep ERROR /var/log/app/order.log | head -n 20'" "command-whitelist"
assert_deny "T2c command-whitelist: unknown verb (curl) denied" \
    "ssh prod-web-01 curl http://example.com" "command-whitelist"
assert_deny "T2d command-whitelist: interactive login denied" \
    "ssh prod-web-01" "command-whitelist"
assert_deny "T2e command-whitelist: rm denied" \
    "ssh prod-web-01 rm -rf /tmp/test" "command-whitelist"

# ===== 追加：本地包装器 SSH 绕过检测 =====
assert_deny "T2f-wrap-nohup: nohup ssh host rm denied" \
    "nohup ssh prod-web-01 rm -rf /tmp/test" "command-whitelist"
assert_deny "T2g-wrap-env: env VAR ssh host rm denied" \
    "env FOO=bar ssh prod-web-01 rm -rf /tmp/test" "command-whitelist"
assert_deny "T2h-wrap-timeout: timeout 60 ssh host rm denied" \
    "timeout 60 ssh prod-web-01 rm -rf /tmp/test" "command-whitelist"
assert_deny "T2i-wrap-nested: nohup env timeout ssh host rm denied" \
    "nohup env FOO=bar timeout 60 ssh prod-web-01 rm -rf /tmp/test" "command-whitelist"
assert_allow "T2j-fp-grep: grep ssh /etc/hosts not treated as ssh" \
    "grep ssh /etc/hosts" "command-whitelist"
assert_allow "T2k-fp-man: man ssh not treated as ssh" \
    "man ssh" "command-whitelist"

# ===== 追加：本地提权工具阻断 =====
assert_deny "T3-priv-sudo: sudo ssh denied locally" \
    "sudo ssh prod-web-01 tail /var/log/app.log" "write-guard"
assert_deny "T3-priv-doas: doas ssh denied locally" \
    "doas ssh prod-web-01 tail /var/log/app.log" "write-guard"
assert_deny "T3-priv-chroot: chroot ssh denied locally" \
    "chroot /tmp ssh prod-web-01 tail /var/log/app.log" "write-guard"

# ===== T3: 写操作阻断 =====
assert_allow "T3a write-guard: pure tail allowed" \
    "ssh prod-web-01 tail -n 100 /var/log/app/order.log" "write-guard"
assert_deny "T3b write-guard: redirect denied" \
    "ssh prod-web-01 'tail /var/log/app/order.log > /tmp/out'" "write-guard"
assert_deny "T3c write-guard: tee denied" \
    "ssh prod-web-01 'cat /etc/passwd | tee /tmp/copy'" "write-guard"
assert_deny "T3d write-guard: systemctl restart denied" \
    "ssh prod-web-01 systemctl restart nginx" "write-guard"
assert_deny "T3e write-guard: docker rm denied" \
    "ssh prod-web-01 docker rm -f container-abc" "write-guard"
assert_deny "T3f write-guard: kubectl delete denied" \
    "ssh prod-web-01 kubectl delete pod abc" "write-guard"
assert_deny "T3g write-guard: mysql INSERT denied" \
    "ssh prod-web-01 mysql -e 'INSERT INTO users VALUES (1)'" "write-guard"
assert_deny "T3h write-guard: sudo denied" \
    "ssh prod-web-01 sudo tail /var/log/syslog" "write-guard"
assert_deny "T3i write-guard: find -delete denied" \
    "ssh prod-web-01 'find /tmp -name *.log -delete'" "write-guard"
assert_deny "T3j write-guard: apt install denied" \
    "ssh prod-web-01 apt install nginx" "write-guard"

# ===== T4: 敏感输入拦截 =====
assert_prompt_deny "T4a sensitive: password" "登录密码是 abc12345"
assert_prompt_deny "T4b sensitive: bearer token" "bearer:abcdef1234567890ABCDEFGHIJKLMNOP"
assert_prompt_deny "T4c sensitive: AWS key" "AKIAIOSFODNN7EXAMPLE"
assert_prompt_deny "T4d sensitive: sk- api key" "sk-abcdefghijklmnopqrstuvwxyz0123456789ABCD"
assert_prompt_allow "T4e sensitive: normal msg" "订单接口报 500，帮忙看一下"

# ===== T5: Hook 完整性校验 =====
rm -f "/tmp/diag-validated-${CLAUDE_SESSION_ID}-"* 2>/dev/null
assert_allow "T5a validate-hooks: all present passes" \
    "ssh prod-web-01 tail /var/log/app/order.log" "validate-hooks"

CHAOS_DIR=$(mktemp -d)
cp -r "$PLUGIN"/* "$CHAOS_DIR/"
rm "$CHAOS_DIR/hooks/audit-log.sh"
rm -f "/tmp/diag-validated-${CLAUDE_SESSION_ID}-"* 2>/dev/null
out=$(jq -n --arg c "ssh prod-web-01 tail /x" '{tool_input:{command:$c}}' | \
    CLAUDE_PLUGIN_ROOT="$CHAOS_DIR" bash "$CHAOS_DIR/hooks/validate-hooks.sh")
if echo "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    RESULTS+=("✅ T5b validate-hooks: missing hook detected and denied")
    PASS=$((PASS+1))
else
    RESULTS+=("❌ T5b validate-hooks: missing hook NOT detected")
    FAIL=$((FAIL+1))
fi
rm -rf "$CHAOS_DIR"

# ===== T9: 审计完整性 =====
jq -n --arg c "ssh prod-web-01 tail -n 100 /var/log/app/order.log" '{
    tool_input: {command: $c},
    tool_response: {stdout: "2026-04-20 ERROR NPE at line 42", exit_code: 0}
}' | bash "$PLUGIN/hooks/audit-log.sh"

AUDIT_FILE=$(ls "$DIAG_HOME/audit/"*.jsonl 2>/dev/null | head -1)
if [ -n "$AUDIT_FILE" ] && [ -s "$AUDIT_FILE" ]; then
    ENTRY=$(tail -n 1 "$AUDIT_FILE")
    FIELDS=(timestamp session_id operator host service command exit_code log_snippet_hash hooks_passed)
    MISS=""
    for f in "${FIELDS[@]}"; do
        if ! echo "$ENTRY" | jq -e ".\"$f\"" >/dev/null 2>&1; then
            MISS="${MISS} $f"
        fi
    done
    if [ -z "$MISS" ]; then
        RESULTS+=("✅ T9 audit: JSONL record complete ($(echo "$ENTRY" | jq -r '.service // "(no service)"') @ $(echo "$ENTRY" | jq -r '.host'))")
        PASS=$((PASS+1))
    else
        RESULTS+=("❌ T9 audit: missing fields:${MISS}")
        FAIL=$((FAIL+1))
    fi
else
    RESULTS+=("❌ T9 audit: no audit file written")
    FAIL=$((FAIL+1))
fi

# 清理
rm -rf "$TMPDIR"
rm -f "/tmp/diag-validated-${CLAUDE_SESSION_ID}-"* 2>/dev/null

echo "==================================================="
echo "Diag 插件冒烟测试结果"
echo "==================================================="
for r in "${RESULTS[@]}"; do
    echo "  $r"
done
echo "==================================================="
echo "总计: $((PASS + FAIL))   通过: $PASS   失败: $FAIL"
echo "==================================================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
