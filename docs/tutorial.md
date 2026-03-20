# 使用教程

本教程以一个完整示例，演示从安装插件到完成需求的全流程。

> 示例场景：为一个 Go 后端项目开发「用户积分规则管理」功能。

---

## 一、安装与初始化

### 1.1 安装插件

```bash
# 1. 添加插件仓库为 marketplace
claude plugins marketplace add https://github.com/zhouhao4221/requirement-workflow-plugin

# 2. 从 marketplace 安装插件
claude plugins install req@dev-workflow

# 验证安装
claude plugins list
```

### 1.2 初始化需求项目

在项目根目录启动 Claude Code，执行：

```
/req:init my-saas
```

这会：
- 创建本地目录 `docs/requirements/`（active/、completed/、modules/、templates/）
- 创建全局缓存 `~/.claude-requirements/projects/my-saas/`
- 生成 PRD 文档模板 `docs/requirements/PRD.md`
- 在 `.claude/settings.local.json` 中记录项目名和角色

### 1.3 同步模板（可选）

如果插件更新了模板，可以同步最新版：

```
/req:update-template
```

---

## 二、创建需求

### 2.1 正式需求（REQ）

```
/req:new 用户积分规则管理 --type=后端
```

AI 会引导你逐章完善需求文档：

| 章节 | 内容 | 你需要做什么 |
|------|------|------------|
| 一、需求描述 | 背景、目标、客户场景、价值 | 描述业务背景，AI 帮你结构化 |
| 二、功能清单 | 可勾选的功能点列表 | 确认功能范围 |
| 三、业务规则 | 校验规则、状态转换、权限 | 补充业务细节 |
| 四、使用场景 | 角色、流程、异常处理 | 描述典型操作流程 |
| 五、API 设计 | 接口路径、方法、说明 | 确认接口设计 |
| 六、测试要点 | 需要验证的场景 | 补充测试关注点 |

完成后生成 `docs/requirements/active/REQ-001-用户积分规则管理.md`。

### 2.2 快速修复（QUICK）

适合小 bug 或小功能，流程更轻量：

```
/req:new-quick 修复积分计算精度丢失
```

QUICK 模板更简洁：问题描述 → 实现方案 → 验证方式。

### 2.3 需求拆分建议

不确定粒度是否合适？用拆分分析：

```
/req:split 用户积分系统
```

AI 会分析粒度并建议拆分方案（只读，不创建文档）。

---

## 三、评审流程

> QUICK 跳过评审，可直接进入开发。

### 3.1 提交评审

```
/req:review
```

状态从「草稿」变为「待评审」。

### 3.2 评审决议

```
/req:review pass     # 通过，进入「评审通过」
/req:review reject   # 驳回，回到「草稿」
```

驳回后需要 `/req:edit` 修改再重新提审。

---

## 四、开发阶段

### 4.1 启动开发

```
/req:dev
```

执行流程：

```
前置检查（REQ 必须通过评审）
    ↓
分支管理（自动创建 feat/REQ-001-user-points-rule）
    ↓
加载需求上下文（章节一~六）
    ↓
生成实现方案（Plan Mode）
    ├── 10.1 数据模型
    ├── 10.2 文件改动清单
    └── 10.3 实现步骤
    ↓
确认方案 → 状态改为「开发中」
    ↓
按分层架构逐步实现
    Model → Store → Biz → Controller → Router
```

### 4.2 分支管理

首次执行 `/req:dev` 时，AI 自动：

1. 检查工作区是否干净（有未提交改动会终止）
2. 从需求标题生成英文分支名，供你确认：
   ```
   将创建开发分支：feat/REQ-001-user-points-rule
   基于分支：main
   ```
3. 确认后创建分支并写入需求文档的 `branch` 字段

再次执行 `/req:dev` 时，直接切换到已记录的分支。

分支命名规则：
- REQ → `feat/REQ-XXX-<english-slug>`
- QUICK → `fix/QUICK-XXX-<english-slug>`

### 4.3 继续开发

中断后再次进入，会恢复进度：

```
/req:dev REQ-001
```

加 `--reset` 可以重新生成实现方案：

```
/req:dev REQ-001 --reset
```

### 4.4 规范提交

开发过程中使用规范提交，自动关联需求编号：

```
/req:commit
```

AI 分析改动内容，生成 Conventional Commits 格式的提交信息：

```
新功能: 实现积分规则 CRUD 接口 (REQ-001)
```

---

## 五、测试阶段

### 5.1 综合测试

```
/req:test
```

包含回归测试 + 新功能测试，状态改为「测试中」。

### 5.2 分步测试

```
/req:test_regression    # 运行已有自动化测试，生成回归报告
/req:test_new           # 为新功能创建测试用例（UT/API/E2E）
```

---

## 六、完成归档

```
/req:done
```

流程：
1. 检查测试完成情况
2. 展示完成摘要（功能点、测试点、文件统计、时间线）
3. 确认后归档：`active/REQ-001-*.md` → `completed/`
4. 更新 PRD 索引
5. 提醒合并开发分支

---

## 七、查看与管理

### 7.1 需求列表

```
/req                          # 列出所有需求
/req --type=后端              # 按类型筛选
/req --module=用户            # 按模块筛选
/req --type=前端 --module=用户 # 组合筛选
```

### 7.2 查看详情

```
/req:show REQ-001     # 查看需求完整内容（只读）
/req:status REQ-001   # 查看状态和进度
```

### 7.3 编辑需求

```
/req:edit REQ-001     # 修改已有需求
```

---

## 八、模块管理

模块是按功能域划分的业务文档，帮助 AI 理解上下文。

```
/req:modules                  # 列出所有模块
/req:modules new 用户         # 创建用户模块文档
/req:modules show 用户        # 查看模块详情
```

模块文档描述：职责边界、核心功能、数据模型、API 概览、关键文件路径。

---

## 九、PRD 管理

PRD 是项目级的产品需求文档，一个项目一份。

```
/req:prd                      # 查看 PRD 状态概览，分析各章节填充情况
/req:prd-edit                 # 编辑 PRD，AI 辅助补充内容
/req:prd-edit 产品概述         # 编辑指定章节
```

PRD 的「需求追踪」章节会自动维护：
- `/req:new` 时追加记录
- `/req:done` 时更新状态和完成日期

---

## 十、版本管理

### 10.1 生成版本说明

```
/req:changelog v1.2.0                          # 自动检测范围
/req:changelog v1.2.0 --from=v1.1.0 --to=HEAD # 指定范围
```

AI 根据 Git 提交记录分类生成结构化 Changelog。

### 10.2 快速修复升级

QUICK 做到一半发现范围变大，可以升级为正式需求：

```
/req:upgrade QUICK-003
```

---

## 十一、跨仓库协作

适用于前后端分仓的项目。

### 主仓库（后端）

```
# 初始化项目
/req:init my-saas

# 正常创建和管理需求
/req:new 用户积分-后端 --type=后端
```

### 关联仓库（前端）

```
# 绑定到同一项目
/req:use my-saas

# 可以查看需求（只读）
/req
/req:show REQ-001

# 可以基于需求开发（从缓存读取）
/req:dev REQ-002
```

关联仓库的角色为 `readonly`：
- 可以查看和读取需求
- 可以基于已完成需求开发
- 不能创建、编辑、变更需求状态

---

## 十二、完整流程图

```
                    创建需求
                /req:new 标题
                      │
                      ▼
               ┌─────────────┐
               │   📝 草稿    │ ← /req:edit 修改
               └──────┬──────┘
                      │ /req:review
                      ▼
               ┌─────────────┐
               │  👀 待评审   │
               └──────┬──────┘
                      │ /req:review pass
                      ▼
               ┌─────────────┐
               │ ✅ 评审通过  │
               └──────┬──────┘
                      │ /req:dev（自动创建分支）
                      ▼
               ┌─────────────┐
               │  🔨 开发中   │ ← /req:commit 提交代码
               └──────┬──────┘
                      │ /req:test
                      ▼
               ┌─────────────┐
               │  🧪 测试中   │
               └──────┬──────┘
                      │ /req:done（提醒合并分支）
                      ▼
               ┌─────────────┐
               │  🎉 已完成   │ → archived to completed/
               └─────────────┘
```

---

## 常用命令速查

| 场景 | 命令 |
|------|------|
| 看看有哪些需求 | `/req` |
| 创建正式需求 | `/req:new 标题 --type=后端` |
| 创建小修复 | `/req:new-quick 标题` |
| 编辑需求 | `/req:edit` |
| 提交评审 | `/req:review` |
| 通过评审 | `/req:review pass` |
| 启动开发 | `/req:dev` |
| 提交代码 | `/req:commit` |
| 运行测试 | `/req:test` |
| 完成归档 | `/req:done` |
| 查看 PRD | `/req:prd` |
| 生成 Changelog | `/req:changelog v1.0.0` |
