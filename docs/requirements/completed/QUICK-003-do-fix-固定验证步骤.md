# QUICK-003 do/fix 增加固定验证步骤并抽成 shared/_verify.md

## 元信息

| 字段 | 值 |
|-----|-----|
| 编号 | QUICK-003 |
| 改动类型 | 优化 |
| 端类型 | 后端 |
| 状态 | 已完成 |
| 模块 | 快速修复 |
| 优先级 | P2 |
| 创建时间 | 2026-09-11 |
| 负责人 | haiqing |
| 关联需求 | - |
| branch | fix/QUICK-003-verify-step |
| issue | - |

## 生命周期

- [x] 草稿
- [x] 方案确认
- [x] 开发中
- [x] 已完成

---

## 问题描述

### 现象
`/req:do` 与 `/req:fix` 改完代码后的质量保障只有一句「有相关测试就派 test-runner 回归，无则跳过」：

- 方案模板没有「验收」字段，`_delegate.md` 委派实施准入第四条「有验收手段」无处落地
- 没有编译 / lint 闸门
- 改动文件无测试时静默跳过，完成提示不报任何验证结果
- 测试失败后的修复没有轮次上限，也没有「不得改测试断言迎合通过」的红线
- `do` 的规模判断在定位代码之前做，code-scout 返回后不复核；无 issue 时直接在当前分支开发，哪怕当前在 main 上
- `test_new.md` 依赖需求文档，`do`/`fix` 没有文档时无法复用它补 UT；其头部仍写「从 CLAUDE.md 测试规范章节读取」（过期）

### 期望
验证顺序固定、结果必报、无覆盖显式说出、失败修复有上限；do/fix 共用一份规则，不各写一份。

---

## 实现方案

### 问题分析
验证逻辑在 do 与 fix 之间完全相同（编译/lint → 相关测试回归 → 覆盖判断 → 结果段），按仓库规则应抽到 `shared/_verify.md`，命令用链接引用；两个命令只保留方案里的「验收」行和完成提示里的「验证结果」段。

### 解决方案
1. 新建 `shared/_verify.md`：方案验收行的要求；验证三级（编译/lint → 相关测试回归 → 覆盖判断按意图类型分流）；失败处理（最多 2 轮、不得改断言迎合、ERROR 不绕过）；「验证结果」段格式。
2. `do.md`：步骤 1 规模判断在 code-scout 返回后复核；步骤 2 方案模板加「验收」行和「行为变化」行；步骤 3 无 issue 且当前在 mainBranch/developBranch 时按类型前缀建分支；新增步骤 3.5 验证（链接 `_verify.md`）；步骤 4 完成提示加「验证结果」段。
3. `fix.md`：修复建议模板加「验收」行；步骤 3 末段改为链接 `_verify.md`；步骤 4 完成提示加「验证结果」段。
4. `test_new.md`：新增 `--files=<逗号分隔文件>` 无文档模式（仅 `--type=ut`，跳过选需求/读文档/回填文档）；头部测试规范来源改为 `docs/prompt/testing.md`，缺失回退 `architecture.md` 测试规范章节。
5. `shared/_common.md` 索引加 `_verify.md`；根 `CLAUDE.md` 心智模型第 3 条的专题文件列表加 `_verify`。

### 涉及文件

| 文件 | 改动类型 | 说明 |
|-----|---------|------|
| plugins/req/shared/_verify.md | 新增 | 执行后验证的共享规则 |
| plugins/req/commands/do.md | 修改 | 规模复核、验收行、分支保护、步骤 3.5、验证结果段 |
| plugins/req/commands/fix.md | 修改 | 验收行、链接 _verify.md、验证结果段 |
| plugins/req/commands/test_new.md | 修改 | `--files=` 无文档模式；测试规范来源改 testing.md |
| plugins/req/shared/_common.md | 修改 | 索引加 _verify.md |
| CLAUDE.md | 修改 | 专题文件列表加 _verify |

### 改动量
- 预估：中
- 涉及文件：6 个
- 代码行数：约 150 行

---

## 验证方式

- [x] `python3 scripts/check-layout.py --check` 通过（92 个链接可达，78 个菜单项无重复）
- [x] `do.md`、`fix.md` 各只出现一处对 `_verify.md` 的链接，验证规则正文不在命令里重复
- [x] `_verify.md` 不含 Python/curl 实现，只写规则与输出格式
- [x] 确认无副作用：`dev.md` 未改（其实施步骤后续可复用 `_verify.md`，本次不动）

---

## 开发记录

### 2026-09-11
- 创建快速需求；方案在会话中已由用户确认（「按方案改」），直接进入开发
- 完成 6 个文件改动，`_verify.md` 3.4 KB，`do.md` 7.6 → 8.9 KB；验证方式 4 项全部通过，待 PR 合并后 `/req:done`
- 用户确认归档（`/req:done QUICK-003`），状态→已完成，移至 completed/；PR 尚未合并，分支 fix/QUICK-003-verify-step 待合
