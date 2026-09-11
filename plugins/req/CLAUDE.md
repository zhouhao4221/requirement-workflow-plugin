# req 插件 — 目录级说明

> 本文件只在处理 `plugins/req/` 下文件时加载；全局规则见仓库根 `CLAUDE.md`。

## 项目架构适配（init / dev / test / release / update 如何读下游项目）

插件不内置项目架构细节，从下游项目的 `docs/prompt/` 和 `.claude/skills/` 读取。

| 位置 | 内容 | 加载方式 |
|------|------|---------|
| `CLAUDE.md` | AI 行为指令（通用规则、引用指针） | 每次会话自动加载 |
| `docs/prompt/architecture.md` | 项目架构知识（分层、规范、技术栈） | `/req:dev`、`/req:test` 显式 Read |
| `docs/prompt/release.md` | 项目发版规则 | `/req:release` 步骤 0 Read |
| `docs/prompt/` Prompt 库（`code-generation`/`refactoring`/`test-generation`/`testing`/`error-diagnosis`/`pr-review`/`requirement-structuring`） | 各方面项目特有规范，统一 5 节骨架 | 对应命令按需 Read（`/req:dev`/`do`/`test*`/`fix`/`review-pr`/`new`·`edit`），缺失降级，非阻塞 |
| `docs/requirements/specs/` | 公共知识层（枚举、规则、契约摘要） | 命令按仓库角色注入 |
| `.devflow/settings.json(.local)` | 结构化配置 | 命令读取字段（local 覆盖同名） |
| `.claude/skills/<concern>.md` | 窄知识具体约定（如路径变量） | 命令扫描全量注入 |

- `/req:init` 扫描项目结构生成 `docs/prompt/architecture.md`；CLAUDE.md 只留引用指针，不内嵌架构内容。Prompt 库其余 7 文件从 `templates/prompt-snippets/` 复制空骨架（仅当不存在），供下游按项目填充；骨架格式见 `prompt-craft.md`。
- 项目级 skill 文件名反映关注点（`migration.md` ✅，`config.md` ❌）；`docs/prompt/` 文件按需 Read，缺失时打印创建提示（非阻塞）。
- 现有示例：`.claude/skills/migration.md` 声明 `MIGRATIONS_DIR`，供 `/req:dev` 写入、`/req:release` 扫描合并。Changelog 目录固定 `docs/changelogs/`，不参与配置。
- **Prompt 结构验证**：`plugins/req/schemas/prompt-schema.md` 定义各命令期望的 prompt 文件结构；`/req:update` 拉新版本后对照检查，缺必需章节报错、缺推荐章节警告。

