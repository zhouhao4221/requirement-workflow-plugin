# 公共逻辑参考 - 索引

> v3 起按主题拆为多个专题文档。本文档仅为索引，命令应直接链接到具体主题文件以减少 Read 体积（详见 [`docs/design/token-optimization.md`](../../../docs/design/token-optimization.md)）。

## 主题索引

| 主题文件 | 内容 |
|---------|------|
| [`_storage.md`](./_storage.md) | settings 写入规范 / 存储路径解析 / 写入规则（无缓存）/ 需求编号生成 / 元信息字段 |
| [`_template.md`](./_template.md) | 状态更新确认机制 / 确认操作规范 / 状态流转 / Memory 隔离规则 / 模板格式约束 |
| [`_branch.md`](./_branch.md) | 分支策略配置（`branchStrategy` 结构、三种预设、各命令消费） |
| [`_issue.md`](./_issue.md) | Issue 拉取规范 / OWNER/REPO 解析 / Issue 与分支提交关联 / Issue 编号读取优先级 / 关闭策略 |
| [`_granularity.md`](./_granularity.md) | 需求粒度规则 / 粒度参考 / 拆分建议 / 已有需求扩展 / 前后端拆分 / REQ vs QUICK 选择 |
| [`_claude-md.md`](./_claude-md.md) | CLAUDE.md 架构检查（检查时机、规则、缺失提醒、片段模板） |
| [`_delegate.md`](./_delegate.md) | 子任务委派规范（何时派 subagent、可用 agent、prompt 自包含/只回结论/并行/只读） |
| [`_verify.md`](./_verify.md) | 执行后验证（方案验收行 / 编译→回归→覆盖判断 / 失败上限与红线 / 验证结果段） |

## 旧链接兼容

旧版本将所有规则集中在本文件，链接形如 `[_common.md](./_common.md)` 或 `[_common.md](./_common.md#anchor)`。所有锚点已迁到对应主题文件并保持名称一致：

| 旧锚点 | 新位置 |
|-------|-------|
| `#settingslocaljson-写入规范` | `_storage.md#settingslocaljson-写入规范` |
| `#存储路径解析` | `_storage.md#存储路径解析` |
| `#issue-拉取规范` | `_issue.md#issue-拉取规范` |
| `#issue-与分支提交的关联` | `_issue.md#issue-与分支提交的关联` |
| `#issue-编号的读取优先级` | `_issue.md#issue-编号的读取优先级` |
| `#ownerrepo-解析` | `_issue.md#ownerrepo-解析` |
| `#分支策略配置` | `_branch.md#分支策略配置` |
| `#需求粒度规则` | `_granularity.md#需求粒度规则` |
| `#已有需求的功能扩展` | `_granularity.md#已有需求的功能扩展` |
| `#claudemd-架构检查` | `_claude-md.md#claudemd-架构检查` |
| `#模板格式约束强制` | `_template.md#模板格式约束强制` |

新增/修改命令时，请直接链接到具体主题文件，不要再链回 `_common.md`。
