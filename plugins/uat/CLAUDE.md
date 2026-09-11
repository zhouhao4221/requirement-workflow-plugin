# uat 插件 — 目录级说明

> 本文件只在处理 `plugins/uat/` 下文件时加载；全局规则（命令/技能结构、模型分级、布局守卫）见仓库根 `CLAUDE.md`。

UI 验收测试。存储：`docs/uat/flows/`（流程文档，入 git）· `docs/uat/reports/` + `screenshots/`（`.gitignore`）。`/uat:run` 激活 `uat-executor`，意图驱动、不依赖预写选择器（testid 为可选加速）。结果四态 PASS/⚠️PASS/FAIL/SKIP。命令：`/uat`（入口）· `init`（首次必跑，装 skill 到项目）· `new` · `run` · `report` · `bug`（FAIL→issue，6 条）。
