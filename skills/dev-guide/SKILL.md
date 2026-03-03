---
name: dev-guide
description: |
  开发引导助手。仅在执行 /req:dev 命令时触发。按项目分层架构引导开发。
---

# 开发引导助手

仅在 `/req:dev` 命令执行时激活，引导按分层架构实现代码。

## 前置条件检查

**在开始开发前必须检查需求状态**：

1. 读取需求文档的「状态」字段
2. 只有以下状态允许开发：
   - ✅ 评审通过 → 可以开始开发
   - 🔨 开发中 → 可以继续开发
   - 🧪 测试中 → 可以修复问题

3. 以下状态**禁止开发**（仅 REQ-XXX，QUICK-XXX 跳过评审）：
   - 📝 草稿 → 提示：`⚠️ 需求尚未评审，请先执行 /req:review 提交评审`
   - 👀 待评审 → 提示：`⚠️ 需求正在评审中，请等待评审通过后再开发`
   - ❌ 评审驳回 → 提示：`⚠️ 需求评审未通过，请先修改后重新提审：/req:edit → /req:review`
   - 🎉 已完成 → 提示：`⚠️ 需求已完成，如需修改请创建新需求`

4. 如果状态不允许开发，**立即终止并提示用户**，不执行后续开发流程

## 分层架构

```
Model → Store → Biz → Controller → Router
```

## 开发顺序

1. **Model** - 数据模型定义
   - 包含 TenantID（多租户）
   - 定义 TableName()

2. **Store** - 数据访问层
   - 定义接口 + 实现
   - CRUD 操作

3. **Biz** - 业务逻辑层
   - 业务校验
   - 使用 errno 返回错误
   - 使用结构化日志

4. **Controller** - 接口层
   - Swagger 注解
   - 参数绑定校验
   - response 包封装响应

5. **Router** - 路由注册
   - 权限标识：`module:resource:action`

## 代码规范

- 文件名：kebab-case
- 日志：`log.Info/Error(msg, ctx, k, v...)`
- 错误：`errno.ErrXxx`
- 事务：`store.DB().Transaction()`

## 检查清单

- [ ] 分层架构正确
- [ ] 多租户支持
- [ ] 日志规范
- [ ] 错误处理
- [ ] Swagger 注解
