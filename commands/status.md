---
description: 查看需求状态 - 详细状态和进度
---

# 查看需求状态

查看需求的详细状态和进度信息。

## 命令格式

```
/req:status [REQ-XXX]
```

**说明**：编号可选，省略时自动选择最近活跃的需求。

---

## 执行流程

### 0. 自动识别需求

如果未提供 REQ-XXX 编号：

```python
# 根据角色决定搜索路径（步骤 1 中已解析 ROLE 和路径）
# readonly：直接搜索缓存 active/
# primary：搜索本地 active/，本地为空时搜索缓存 active/
# 未绑定：仅搜索本地 active/
candidates = find_requirements(dir=ACTIVE, sort_by="mtime")

if len(candidates) == 0 and ROLE == "primary" and CACHE_ACTIVE:
    candidates = find_requirements(dir=CACHE_ACTIVE, sort_by="mtime")

if len(candidates) == 0:
    print("没有活跃的需求")
    if ROLE != "readonly":
        print("创建新需求：/req:new")
    print("查看已完成：/req:status --all")
    exit()
elif len(candidates) == 1:
    REQ_ID = candidates[0]
    print(f"自动选择：{REQ_ID}")
else:
    print("发现多个活跃需求，请选择：")
    for i, req in enumerate(candidates):
        print(f"  {i+1}. {req}")
    choice = input()  # 用户输入编号
    REQ_ID = candidates[int(choice) - 1]
```

### 1. 解析存储路径（按角色）

```bash
# 读取项目配置
PROJECT=$(cat .claude/settings.local.json 2>/dev/null | jq -r '.requirementProject // empty')
ROLE=$(cat .claude/settings.local.json 2>/dev/null | jq -r '.requirementRole // empty')

if [ "$ROLE" = "readonly" ]; then
    # 只读仓库：直接使用缓存路径
    ROOT=~/.claude-requirements/projects/$PROJECT
    ACTIVE=$ROOT/active
    COMPLETED=$ROOT/completed
    SOURCE="cache"
elif [ "$ROLE" = "primary" ]; then
    # 主仓库：优先本地，缓存为备用
    LOCAL_ROOT=docs/requirements
    ACTIVE=$LOCAL_ROOT/active
    COMPLETED=$LOCAL_ROOT/completed
    CACHE_ROOT=~/.claude-requirements/projects/$PROJECT
    CACHE_ACTIVE=$CACHE_ROOT/active
    CACHE_COMPLETED=$CACHE_ROOT/completed
    SOURCE="local"
else
    # 未绑定项目：仅使用本地
    LOCAL_ROOT=docs/requirements
    ACTIVE=$LOCAL_ROOT/active
    COMPLETED=$LOCAL_ROOT/completed
    SOURCE="local"
fi
```

### 2. 查找需求文档（按角色）

**`primary` 角色**搜索位置（按优先级）：
1. `$ACTIVE/REQ-XXX-*.md`（本地）
2. `$COMPLETED/REQ-XXX-*.md`（本地）
3. `$CACHE_ACTIVE/REQ-XXX-*.md`（本地不存在时）
4. `$CACHE_COMPLETED/REQ-XXX-*.md`（本地不存在时）

**`readonly` 角色**搜索位置：
1. `$ACTIVE/REQ-XXX-*.md`（缓存）
2. `$COMPLETED/REQ-XXX-*.md`（缓存）

如果未找到：
```
❌ 未找到需求：REQ-XXX

💡 可用操作：
- 查看所有需求：/req
- 创建新需求：/req:new
```

### 3. 解析需求文档

提取关键信息：
- 元信息
- 生命周期状态
- 功能清单进度
- 测试要点进度
- 文件改动清单
- 变更记录

### 4. 输出详细状态

```
═══════════════════════════════════════════════
📋 需求状态：REQ-001 部门渠道关联
═══════════════════════════════════════════════

📌 元信息
├── 编号：REQ-001
├── 状态：🔨 开发中
├── 优先级：P1
├── 创建日期：2026-01-07
├── 负责人：-
├── 数据来源：本地 (primary)
└── 项目：my-saas-product

📊 生命周期
├── [x] 📝 草稿         2026-01-07
├── [x] 👀 待评审       2026-01-07
├── [x] ✅ 评审通过      2026-01-07
├── [>] 🔨 开发中       2026-01-08 ← 当前
├── [ ] 🧪 测试中
└── [ ] 🎉 已完成

📝 功能清单（4/6 完成）
├── [x] 部门渠道关联
├── [x] 渠道范围校验
├── [x] 获取可选渠道接口
├── [x] 订单数据过滤
├── [ ] Dashboard数据过滤      ← 进行中
└── [ ] 缓存机制

🧪 测试要点（0/8 完成）
├── [ ] 部门创建时关联渠道
├── [ ] 部门更新时修改渠道关联
├── [ ] 上级部门未设置渠道，下级可任意选择
├── [ ] 上级部门已设置渠道，下级必须设置且为子集
├── [ ] 选择超出范围的渠道报错
├── [ ] 订单列表按渠道正确过滤
├── [ ] Dashboard 数据按渠道正确过滤
└── [ ] 缓存正确失效

📁 文件改动（8/12 完成）
已完成：
├── internal/sys/model/sys_dept_channel_model.go ✅
├── internal/sys/store/sys_dept_channel_store.go ✅
├── internal/sys/biz/dept_channel.go ✅
├── internal/sys/biz/sys_dept.go ✅
├── internal/sys/controller/v1/sys_dept.go ✅
├── pkg/api/core/v1/sys_dept.go ✅
├── internal/sys/router.go ✅
└── internal/oms/store/sales_order_store.go ✅

待处理：
├── internal/oms/biz/sales_order_biz.go
├── internal/dashboard/store/sales_dashboard_store.go
├── internal/dashboard/biz/sales_dashboard_biz.go
└── docs/swagger/docs.go

📜 变更记录
└── 2026-01-07 初始版本

📋 评审记录
└── 2026-01-07 张三 通过 - 方案合理，可以开发

═══════════════════════════════════════════════

💡 可用操作：
# primary 角色显示完整操作
- 继续开发：/req:dev REQ-001
- 编辑需求：/req:edit REQ-001
- 进入测试：/req:test REQ-001

# readonly 角色仅显示只读操作
# - 查看需求列表：/req
# - 查看模块：/req:modules
```

---

## 简洁模式

使用 `--brief` 参数输出简洁信息：

```
/req:status REQ-001 --brief
```

输出：
```
REQ-001 部门渠道关联
状态：🔨 开发中 | 功能：4/6 | 测试：0/8
```

---

## 批量查看

查看所有活跃需求状态：

```
/req:status --all
```

输出：
```
📋 活跃需求状态一览

| 编号 | 标题 | 状态 | 功能进度 | 测试进度 |
|------|------|------|---------|---------|
| REQ-001 | 部门渠道关联 | 🔨 开发中 | 4/6 | 0/8 |
| REQ-002 | 用户积分系统 | 👀 待评审 | - | - |
| REQ-003 | 订单导出优化 | 📝 草稿 | - | - |
```

## 用户输入

$ARGUMENTS
