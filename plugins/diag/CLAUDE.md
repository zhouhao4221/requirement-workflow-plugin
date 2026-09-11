# diag 插件 — 目录级说明

> 本文件只在处理 `plugins/diag/` 下文件时加载；全局规则（命令/技能结构、模型分级、布局守卫）见仓库根 `CLAUDE.md`。

生产诊断，**全程只读**，与 [claude-safe-ops](https://github.com/zhouhao4221/claude-safe-ops) 互补。边界：SSH 只读命令 ✅ · DB SELECT ✅ · 远端 `/tmp/claude-diag-*` append ⚠️ · 写操作/Edit/Write ❌。**6 个风控 Hook 全 deny**：敏感输入拦截 · Hook 完整性自检（防风控链被禁用）· SSH 主机白名单 · 命令动词白名单 · 写操作+本地提权阻断 · JSONL 审计（30 天）。**改动 hooks/ 须同步 hooks.json 注册，否则被 validate-hooks 拦截。** 存储 `~/.claude-diag/`。依赖：`python3` · `jq` · `yq`/`pyyaml` · `ssh`。
