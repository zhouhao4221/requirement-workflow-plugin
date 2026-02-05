---
description: 完成需求 - 标记完成并归档
---

# 完成需求

标记需求为已完成，归档文档。

> 存储路径和缓存同步规则见 [_common.md](./_common.md)

## 命令格式

```
/req:done [REQ-XXX]
```

- 省略编号时自动选择「测试中」的需求
- 多个候选时让用户选择

---

## 执行流程

### 1. 选择需求

- 指定编号 → 使用该需求
- 未指定 → 查找可完成需求（状态为测试中）

### 2. 前置检查

- 状态必须为「测试中」
- 检查测试完成情况，有未通过时警告并确认

### 3. 生成完成摘要

```
📋 需求完成确认：REQ-001 部门渠道关联

📊 完成统计：
- 功能点：6/6 ✅
- 测试点：8/8 ✅
- 涉及文件：12 个
- 开发周期：2 天（2026-01-07 ~ 2026-01-08）

📁 代码变更：
新增文件（4）：
- internal/sys/model/sys_dept_channel_model.go
- internal/sys/store/sys_dept_channel_store.go
- internal/sys/biz/dept_channel.go
- docs/migrations/1.2/1.2.3.sql

修改文件（8）：
- internal/sys/biz/sys_dept.go
- internal/sys/controller/v1/sys_dept.go
- internal/sys/router.go
- pkg/api/core/v1/sys_dept.go
- internal/oms/store/sales_order_store.go
- internal/oms/biz/sales_order_biz.go
- internal/dashboard/store/sales_dashboard_store.go
- internal/dashboard/biz/sales_dashboard_biz.go

是否确认完成？(y/n)
```

### 4. 更新需求文档

- 修改元信息状态为「已完成」
- 勾选生命周期「已完成」
- 记录完成时间

### 5. 更新 PRD 索引

在 `docs/requirements/PRD.md` 的「需求追踪」章节中，更新对应需求的状态和完成日期：

```markdown
| REQ-XXX | 需求标题 | 模块名 | 已完成 | 创建日期 | YYYY-MM-DD |
```

若 PRD.md 不存在或无「需求追踪」章节，跳过此步骤。

### 6. 归档文档并同步缓存

- 移动到 completed/ 目录
- **必须执行缓存同步**：
  1. 读取 `.claude/settings.local.json` 获取 `requirementProject`
  2. 若项目已绑定，执行缓存归档：
     ```bash
     CACHE_ROOT=~/.claude-requirements/projects/<project>
     mv $CACHE_ROOT/active/REQ-XXX-*.md $CACHE_ROOT/completed/
     ```
  3. 缓存目录不存在时跳过（项目未初始化）

### 7. 生成完成报告

```
🎉 需求已完成！

═══════════════════════════════════════════════
📋 需求完成报告
═══════════════════════════════════════════════

📌 基本信息
- 编号：REQ-001
- 标题：部门渠道关联
- 优先级：P1
- 负责人：-

📅 时间线
- 创建：2026-01-07
- 评审通过：2026-01-07
- 开发完成：2026-01-08
- 测试通过：2026-01-08
- 完成：2026-01-08
- 总周期：2 天

📊 工作量
- 功能点：6 个
- 测试点：8 个
- 新增文件：4 个
- 修改文件：8 个

📁 归档位置
$REQ_COMPLETED/REQ-001-部门渠道关联.md

═══════════════════════════════════════════════

💡 后续操作：
- 查看历史需求：ls docs/requirements/completed/
- 创建新需求：/req:new
- 查看活跃需求：/req
```

### 8. 可选：Git 提交关联

如果有关联的 Git 提交，显示提交记录：

```
📝 关联的 Git 提交：
- d7929c9 feat(sys): 实现部门渠道关联 (REQ-001)
- 36c055f feat(sys): 添加部门渠道缓存机制 (REQ-001)
```

---

## 回滚操作

如果需要将已完成的需求重新激活：

```bash
# 手动操作
mv $REQ_COMPLETED/REQ-001-*.md $REQ_ACTIVE/
# 然后修改文档状态
```

---

## 统计数据

完成需求时自动统计：
- 需求总数
- 平均完成周期
- 功能点完成率
- 测试通过率

数据可用于团队效能分析。

## 用户输入

$ARGUMENTS
