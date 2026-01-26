---
description: 回归测试 - 运行已有自动化测试用例
---

# 回归测试

运行项目中已存在的自动化测试用例，验证功能正确性。

> 存储路径和缓存同步规则见 [_common.md](./_common.md)

## 命令格式

```
/req:test_regression [选项]
```

### 选项

| 选项 | 说明 | 示例 |
|-----|------|------|
| `--all` | 全量回归（默认） | `/req:test_regression --all` |
| `--changed` | 仅测试变更相关 | `/req:test_regression --changed` |
| `--module=<name>` | 指定模块 | `/req:test_regression --module=user` |
| `--failed` | 仅运行上次失败的 | `/req:test_regression --failed` |
| `--type=<ut\|api\|e2e>` | 指定测试类型 | `/req:test_regression --type=ut` |
| `--verbose` | 显示详细输出 | `/req:test_regression --verbose` |
| `--coverage` | 生成覆盖率报告 | `/req:test_regression --coverage` |
| `--skip-env` | 跳过环境检查（仅 UT） | `/req:test_regression --type=ut --skip-env` |

---

## 测试环境要求

不同类型的测试需要不同的环境：

| 测试类型 | Docker (MySQL+Redis) | 后端服务 | 前端服务 |
|---------|---------------------|---------|---------|
| UT | 否 | 否 | 否 |
| API | 是 | 是 | 否 |
| E2E | 是 | 是 | 是 |

---

## 执行流程

### 0. 环境准备（API/E2E 需要）

如果测试类型包含 API 或 E2E，先检查并启动测试环境：

```
🔍 检查测试环境...

Docker 容器状态：
├── mysql-test    ❌ 未启动
└── redis-test    ❌ 未启动

是否启动测试环境？(y/n): y

🚀 启动 Docker 容器...
docker-compose -f docker-compose.test.yml up -d

⏳ 等待服务就绪...
├── MySQL (localhost:3307)  ✅ 就绪
└── Redis (localhost:6380)  ✅ 就绪

🚀 启动后端服务...
APP_ENV=test go run main.go &

⏳ 等待后端服务...
└── Backend (localhost:8080)  ✅ 就绪

🚀 启动前端服务（E2E 需要）...
cd frontend && npm run dev &

⏳ 等待前端服务...
└── Frontend (localhost:3000)  ✅ 就绪

✅ 测试环境准备完成
```

### 1. 检测项目类型

自动识别项目技术栈和测试框架：

```
🔍 检测项目类型...

项目类型：Go
测试框架：
├── 单元测试：go test
├── API 测试：go test -tags=integration
└── E2E 测试：未配置

测试目录：
├── internal/biz/*_test.go (42 个文件)
├── internal/store/*_test.go (18 个文件)
└── tests/api/*_test.go (12 个文件)
```

### 2. 确定测试范围

根据选项确定要执行的测试：

#### 全量模式 (--all)
执行所有测试文件

#### 变更模式 (--changed)
```
📋 检测变更文件...

变更文件：
├── internal/biz/dept.go
├── internal/biz/dept_channel.go
└── internal/controller/dept.go

关联测试：
├── internal/biz/dept_test.go
├── internal/biz/dept_channel_test.go
└── tests/api/dept_api_test.go
```

#### 失败重试模式 (--failed)
从上次测试结果中读取失败用例

### 3. 执行测试

按类型依次执行：

```
🔄 执行回归测试...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📦 单元测试 (go test ./...)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

internal/biz/user_test.go
├── TestUserBiz_Create_Success           ✅ PASS (0.02s)
├── TestUserBiz_Create_DuplicateEmail    ✅ PASS (0.01s)
├── TestUserBiz_Update_Success           ✅ PASS (0.01s)
└── TestUserBiz_Delete_NotFound          ✅ PASS (0.01s)

internal/biz/dept_test.go
├── TestDeptBiz_Create_Success           ✅ PASS (0.02s)
├── TestDeptBiz_ValidateChannel          ❌ FAIL (0.01s)
│   Expected: error
│   Actual:   nil
└── TestDeptBiz_GetChildren              ✅ PASS (0.01s)

internal/store/order_test.go
├── TestOrderStore_Create                ✅ PASS (0.03s)
├── TestOrderStore_List_Pagination       ✅ PASS (0.02s)
└── TestOrderStore_List_Filter           ✅ PASS (0.02s)

📊 单元测试结果：9/10 通过

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📡 API 测试 (go test -tags=integration)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

tests/api/user_api_test.go
├── POST /api/v1/user                    ✅ PASS
├── GET /api/v1/user/:id                 ✅ PASS
├── PUT /api/v1/user/:id                 ✅ PASS
└── DELETE /api/v1/user/:id              ✅ PASS

tests/api/dept_api_test.go
├── POST /api/v1/dept                    ✅ PASS
├── GET /api/v1/dept/tree                ✅ PASS
└── GET /api/v1/dept/channels            ❌ FAIL
    Expected: 200
    Actual:   500 (Internal Server Error)

📊 API 测试结果：6/7 通过
```

### 4. 生成测试报告

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 回归测试报告
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

测试时间：2024-01-15 14:30:22
测试范围：全量回归
总耗时：12.5s

┌──────────┬────────┬────────┬────────┬─────────┐
│ 类型     │ 总数   │ 通过   │ 失败   │ 通过率  │
├──────────┼────────┼────────┼────────┼─────────┤
│ 单元测试 │ 10     │ 9      │ 1      │ 90.0%   │
│ API 测试 │ 7      │ 6      │ 1      │ 85.7%   │
│ E2E 测试 │ -      │ -      │ -      │ -       │
├──────────┼────────┼────────┼────────┼─────────┤
│ 合计     │ 17     │ 15     │ 2      │ 88.2%   │
└──────────┴────────┴────────┴────────┴─────────┘

❌ 失败用例（2 个）：

1. TestDeptBiz_ValidateChannel
   文件：internal/biz/dept_test.go:45
   原因：预期返回 error，实际返回 nil

2. GET /api/v1/dept/channels
   文件：tests/api/dept_api_test.go:78
   原因：500 Internal Server Error

💡 下一步操作：
- 修复后重新测试：/req:test_regression --failed
- 查看失败详情：/req:test_regression --verbose
- 忽略失败继续：/req:test --force
```

### 5. 覆盖率报告（--coverage）

```
📊 代码覆盖率报告

┌─────────────────────────────┬──────────┬──────────┐
│ 包                          │ 覆盖率   │ 状态     │
├─────────────────────────────┼──────────┼──────────┤
│ internal/biz                │ 82.5%    │ ✅ 达标   │
│ internal/store              │ 75.3%    │ ⚠️ 接近   │
│ internal/controller         │ 68.2%    │ ❌ 不足   │
│ pkg/utils                   │ 91.0%    │ ✅ 达标   │
├─────────────────────────────┼──────────┼──────────┤
│ 总计                        │ 78.5%    │ ⚠️ 接近   │
└─────────────────────────────┴──────────┴──────────┘

目标覆盖率：80%
建议补充测试：internal/controller
```

---

## 测试框架配置

### 单元测试 (UT)

```bash
# 运行所有单元测试
go test ./internal/...

# 带覆盖率
go test -cover -coverprofile=coverage.out ./internal/...

# 指定模块
go test ./internal/biz/...

# 仅失败重试
go test -run "TestDeptBiz_ValidateChannel|TestUserBiz_Create" ./internal/...
```

### API 测试

```bash
# 前提：确保测试环境已启动
docker-compose -f docker-compose.test.yml up -d
APP_ENV=test go run main.go &

# 运行 API 测试
go test -tags=api ./tests/api/...

# 带详细输出
go test -tags=api -v ./tests/api/...

# 指定接口
go test -tags=api -run "TestCreateUser|TestGetUser" ./tests/api/...
```

### E2E 测试 (Playwright)

```bash
# 前提：确保测试环境已启动（包括前端）
docker-compose -f docker-compose.test.yml up -d
APP_ENV=test go run main.go &
cd frontend && npm run dev &

# 运行所有 E2E 测试
npx playwright test

# 带 UI 调试
npx playwright test --ui

# 仅失败重试
npx playwright test --last-failed

# 指定测试文件
npx playwright test tests/e2e/user-flow.spec.ts

# 生成报告
npx playwright show-report
```

---

## 与 CI/CD 集成

回归测试结果可输出为 CI 友好格式：

```bash
/req:test_regression --ci --output=junit.xml
```

生成的报告可用于：
- GitHub Actions
- GitLab CI
- Jenkins

---

## 用户输入

$ARGUMENTS
