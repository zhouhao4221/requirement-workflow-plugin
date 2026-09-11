# api 插件 — 目录级说明

> 本文件只在处理 `plugins/api/` 下文件时加载；全局规则（命令/技能结构、模型分级、布局守卫）见仓库根 `CLAUDE.md`。

前端 API 对接。配置 `.api-config.json`（项目根，入 git）；Swagger **不缓存**，每次实时解析（`scripts/swagger-parser.py`，无第三方依赖）。产物：TS 类型→`{typeDir}`、请求函数→`{outputDir}`；gen 做字段 diff + 引用文件影响分析后才写入。
