#!/bin/bash
# write-guard.sh — PreToolUse Bash Hook
# 阻断 SSH 远程命令中的写操作（重定向、写类动词、服务控制、包管理、DB 写等）

INPUT=$(cat)
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

CMD=$(diag_read_command "$INPUT")
[ -z "$CMD" ] && exit 0

# 独立于 SSH 的本地提权阻断：防止 `sudo ssh ...` / `su -c ssh ...` 等
# 以本地提升权限执行，无论后续 ssh 是否被识别
if echo "$CMD" | grep -qE '^[[:space:]]*(sudo|su|doas|chroot|unshare|nsenter)([[:space:]]|$)'; then
    diag_deny "本地命令以提权工具开头（sudo / su / doas / chroot / unshare / nsenter），已阻断。Diag 插件禁止提权执行。"
fi

PARSED=$(diag_parse_ssh "$CMD")
diag_is_ssh "$PARSED" || exit 0

REMOTE=$(diag_ssh_remote "$PARSED")
[ -z "$REMOTE" ] && exit 0

RESULT=$(printf '%s' "$REMOTE" | python3 "$DIAG_PLUGIN_ROOT/scripts/check-remote.py")
WRITE_ALLOWED=$(echo "$RESULT" | jq -r '.write.allowed // false')

if [ "$WRITE_ALLOWED" = "true" ]; then
    exit 0
fi

DETAILS=$(echo "$RESULT" | jq -r '.write.violations | map("\(.kind):[\(.token)]") | join("; ")')
diag_deny "SSH 远程命令含写操作：${DETAILS}。Diag 插件只允许只读命令，禁止修改远程文件/进程/服务/数据库。"
