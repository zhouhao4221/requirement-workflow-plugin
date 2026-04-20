# Diag — 生产诊断插件

**只读拉日志 · AI 解析堆栈 · 关联代码 · 给修复建议**

与 [claude-safe-ops](https://github.com/zhouhao4221/claude-safe-ops) 互补：它管"执行类"运维动作，本插件管**只读诊断**。

---

## 核心边界

- ✅ **读**：`tail / head / cat / grep / awk / sed / less / wc / find -name / ls / ps / df / free / uptime` 等只读命令
- ❌ **写**：禁止 `rm / mv / cp / chmod / chown / 重定向（>、>>、tee）/ 服务控制 / 包管理 / 一切修改类操作`
- ❌ **代码**：建议以文字形式给出，插件不触发 Edit/Write 改动仓库

---

## 快速开始

```bash
# 在 Claude Code 中执行
/diag:init

# 编辑 ~/.claude-diag/config/services.yaml，登记服务

# 开始诊断
/diag:diagnose 订单接口刚才报 500
```

---

## 命令

| 命令 | 用途 |
|---|---|
| `/diag` | 入口，列出子命令 |
| `/diag:init` | 初始化 `~/.claude-diag/` + 注册 Hook + 空跑测试 |
| `/diag:diagnose <描述>` | 报错定位（SSH 拉日志 → 堆栈解析 → 代码关联 → 建议） |
| `/diag:audit [--host] [--from] [--to]` | 审计查询（默认近 7 天） |

---

## 风控 Hook

| Hook | 时机 | 职责 |
|---|---|---|
| `sensitive-input-guard` | UserPromptSubmit | 拦截消息中的 token / password / key |
| `validate-hooks` | PreToolUse Bash（首次） | 校验 Hook 注册完整性 |
| `host-whitelist` | PreToolUse Bash | SSH 目标主机白名单 |
| `command-whitelist` | PreToolUse Bash | SSH 远程命令白名单 |
| `write-guard` | PreToolUse Bash | 阻断写类命令与重定向 |
| `audit-log` | PostToolUse Bash | JSONL 审计 |

---

## 目录

```
~/.claude-diag/
├── config/services.yaml          # 服务清单（唯一权限源）
└── audit/command_audit-YYYY-MM-DD.jsonl   # 审计日志（日切分，保留 30 天）
```

---

## 依赖

- `python3`（3.6+，用于 SSH 命令解析和 YAML 读取）
- `jq`（用于 Hook 输出 JSON 决策）
- `yq` *或* `python3 + pyyaml`（YAML 解析，二选一）
- 系统 `ssh` + `~/.ssh/config` + SSH Agent

`/diag:init` 会检查并提示缺失依赖。
