---
name: test-guide
description: |
  测试引导助手。在执行 /req:test、/req:test_regression 或 /req:test_new 命令时触发。
  支持运行已有自动化测试和创建新测试用例。
---

# 测试引导助手

测试分为两大类型，通过不同命令触发：

| 命令 | 用途 | 说明 |
|-----|------|------|
| `/req:test_regression` | 运行已有测试 | 执行现有自动化测试用例，回归验证 |
| `/req:test_new` | 创建新测试 | 为新功能编写 UT/API/E2E 测试用例 |
| `/req:test` | 综合测试 | 先运行回归，再补充新测试 |

---

## 测试目录结构

```
your-project/
├── internal/
│   ├── biz/
│   │   ├── user.go
│   │   └── user_test.go          # UT：与源文件同目录
│   ├── store/
│   │   └── user_test.go          # UT：与源文件同目录
│   └── controller/
│       └── user_test.go          # UT：与源文件同目录
│
├── tests/
│   ├── api/                       # API 集成测试
│   │   ├── setup_test.go         # 测试初始化
│   │   ├── user_api_test.go
│   │   └── dept_api_test.go
│   ├── e2e/                       # E2E 测试 (Playwright)
│   │   ├── playwright.config.ts
│   │   ├── user-flow.spec.ts
│   │   └── order-flow.spec.ts
│   └── fixtures/                  # 测试数据
│       └── test_data.sql
│
├── docker-compose.test.yml        # 测试环境 Docker 配置
└── scripts/
    └── test-env.sh               # 测试环境启动脚本
```

---

## 测试环境搭建

API 测试和 E2E 测试需要先启动测试环境：

### 环境依赖

```yaml
# docker-compose.test.yml
services:
  mysql-test:
    image: your-mysql-test:latest  # 预先创建的测试镜像
    ports:
      - "3307:3306"
    environment:
      MYSQL_DATABASE: test_db
      MYSQL_ROOT_PASSWORD: test123

  redis-test:
    image: your-redis-test:latest  # 预先创建的测试镜像
    ports:
      - "6380:6379"
```

### 启动流程

```
1. 启动 Docker 容器（MySQL + Redis）
2. 等待服务就绪
3. 初始化测试数据
4. 启动后端服务（本地）
5. 启动前端服务（本地，E2E 需要）
6. 执行测试
7. 清理环境
```

### 环境启动命令

```bash
# 启动测试环境
docker-compose -f docker-compose.test.yml up -d

# 等待服务就绪
./scripts/wait-for-it.sh localhost:3307 -- echo "MySQL ready"
./scripts/wait-for-it.sh localhost:6380 -- echo "Redis ready"

# 启动后端（测试模式）
APP_ENV=test go run main.go &

# 启动前端（E2E 需要）
cd frontend && npm run dev &
```

---

## 一、回归测试 (`/req:test_regression`)

运行项目中已存在的自动化测试用例。

### 测试类型识别

根据项目技术栈自动识别测试框架：

| 类型 | 目录 | 命令 | 需要环境 |
|-----|------|------|---------|
| UT | `internal/**/*_test.go` | `go test ./...` | 否 |
| API | `tests/api/` | `go test -tags=api ./tests/api/...` | Docker + 后端 |
| E2E | `tests/e2e/` | `npx playwright test` | Docker + 前后端 |

### 执行流程

```
1. 检测项目类型和测试框架
2. 识别测试范围（全量/增量/指定模块）
3. 执行测试命令
4. 收集测试结果
5. 生成测试报告
```

### 测试范围选项

```bash
/req:test_regression              # 全量回归
/req:test_regression --changed    # 仅测试变更相关
/req:test_regression --module=user # 指定模块
/req:test_regression --failed     # 仅运行上次失败的
```

### 结果输出格式

```
🔄 执行回归测试...

📦 单元测试 (go test)
├── internal/biz/user_test.go      ✅ 12/12 通过
├── internal/biz/order_test.go     ✅ 8/8 通过
└── internal/store/dept_test.go    ❌ 2/5 通过

📡 API 测试 (integration)
├── POST /api/v1/user              ✅ 通过
├── GET /api/v1/user/:id           ✅ 通过
└── DELETE /api/v1/user/:id        ❌ 失败 - 权限检查错误

📊 回归测试结果：22/27 通过 (81.5%)

❌ 失败用例：
1. TestDeptChannelValidation - 预期 error，实际 nil
2. DELETE /api/v1/user/:id - 权限检查未生效

💡 下一步：
- 修复问题后重新测试：/req:test_regression --failed
- 查看失败详情：/req:test_regression --verbose
```

---

## 二、创建新测试 (`/req:test_new`)

为新开发的功能创建自动化测试用例。

### 测试金字塔

```
        ┌─────────┐
        │   E2E   │  少量关键路径
        ├─────────┤
        │   API   │  中等数量，覆盖接口
        ├─────────┤
        │   UT    │  大量，覆盖业务逻辑
        └─────────┘
```

### 2.1 单元测试 (UT)

**目标**：测试业务逻辑层，不依赖外部服务

**Go 项目规范**：

```go
// 文件命名：xxx_test.go，与被测文件同目录
// 函数命名：TestXxx 或 Test_Xxx_场景

func TestUserBiz_Create_Success(t *testing.T) {
    // Arrange - 准备测试数据和 mock
    ctrl := gomock.NewController(t)
    mockStore := mock.NewMockUserStore(ctrl)
    biz := NewUserBiz(mockStore)

    // Act - 执行被测方法
    result, err := biz.Create(ctx, &CreateUserReq{...})

    // Assert - 验证结果
    assert.NoError(t, err)
    assert.NotNil(t, result)
}

func TestUserBiz_Create_DuplicateEmail(t *testing.T) {
    // 测试异常场景
}
```

**测试场景覆盖**：

- 正常流程（Happy Path）
- 边界条件（空值、最大/最小值）
- 异常场景（重复、不存在、无权限）
- 业务规则验证

**UT 生成流程**：

```
1. 分析需求文档中的业务规则
2. 识别 Biz 层需要测试的方法
3. 为每个方法生成测试用例
4. 包含正常和异常场景
5. 生成 mock 依赖
```

### 2.2 API 测试

**目标**：验证接口契约、参数校验、错误码

**Go 项目规范**：

```go
// 文件位置：tests/api/ 或 internal/controller/xxx_test.go
// 使用 httptest 或真实服务

func TestCreateUser_API(t *testing.T) {
    // 启动测试服务器
    router := setupTestRouter()

    tests := []struct {
        name       string
        body       string
        wantCode   int
        wantErrno  string
    }{
        {
            name:     "正常创建",
            body:     `{"name":"test","email":"test@example.com"}`,
            wantCode: 200,
        },
        {
            name:     "缺少必填字段",
            body:     `{"name":"test"}`,
            wantCode: 400,
            wantErrno: "INVALID_PARAMS",
        },
        {
            name:     "邮箱格式错误",
            body:     `{"name":"test","email":"invalid"}`,
            wantCode: 400,
            wantErrno: "INVALID_EMAIL",
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            req := httptest.NewRequest("POST", "/api/v1/user", strings.NewReader(tt.body))
            // ... 执行和验证
        })
    }
}
```

**API 测试要点**：

| 测试类型 | 验证内容 |
|---------|---------|
| 参数校验 | 必填、格式、范围、类型 |
| 权限控制 | 认证、授权、租户隔离 |
| 错误码 | 统一错误码格式和语义 |
| 响应格式 | JSON 结构、字段完整性 |
| 边界场景 | 空列表、分页边界、并发 |

**API 测试生成流程**：

```
1. 从需求文档提取 API 设计
2. 为每个接口生成测试表格
3. 覆盖正常、异常、边界场景
4. 生成测试数据准备代码
5. 集成到 CI 流程
```

### 2.3 E2E 测试

**目标**：验证完整用户流程，端到端场景

**适用场景**：

- 核心业务流程（下单、支付）
- 跨模块交互
- 关键用户旅程

**前置条件**：需要启动完整测试环境（Docker + 前后端服务）

**E2E 规范（Playwright）**：

```typescript
// 文件位置：tests/e2e/user-register.spec.ts

import { test, expect } from '@playwright/test';

test.describe('用户注册流程', () => {
  test.beforeEach(async ({ request }) => {
    // 重置测试数据
    await request.post('/api/test/reset-db');
  });

  test('完整注册流程', async ({ page }) => {
    // 访问注册页
    await page.goto('/register');

    // 填写表单
    await page.getByTestId('email').fill('test@example.com');
    await page.getByTestId('password').fill('Password123');
    await page.getByTestId('confirm').fill('Password123');

    // 提交
    await page.getByTestId('submit').click();

    // 验证结果
    await expect(page).toHaveURL(/.*dashboard/);
    await expect(page.getByText('欢迎')).toBeVisible();
  });

  test('邮箱已存在时提示错误', async ({ page, request }) => {
    // 创建已存在的用户
    await request.post('/api/test/create-user', {
      data: { email: 'exist@example.com' }
    });

    await page.goto('/register');
    await page.getByTestId('email').fill('exist@example.com');
    await page.getByTestId('password').fill('Password123');
    await page.getByTestId('confirm').fill('Password123');
    await page.getByTestId('submit').click();

    await expect(page.getByText('邮箱已被注册')).toBeVisible();
  });
});
```

**Playwright 配置**：

```typescript
// tests/e2e/playwright.config.ts
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  baseURL: 'http://localhost:3000',  // 前端地址
  use: {
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  webServer: [
    {
      command: 'npm run dev',
      url: 'http://localhost:3000',
      reuseExistingServer: true,
    },
  ],
});
```

**E2E 测试生成流程**：

```
1. 确认测试环境已启动（Docker + 前后端）
2. 识别需求中的用户故事
3. 提取关键用户流程
4. 设计测试场景（正常+异常）
5. 生成 Playwright 测试代码
6. 添加断言验证
```

---

## 三、测试创建工作流

执行 `/req:test_new` 时的完整流程：

### 步骤 1：分析需求

```
📋 分析需求文档...

需求：REQ-001 部门渠道关联
涉及功能：
- 部门创建时关联渠道
- 渠道范围校验（上下级约束）
- 获取可选渠道列表

识别到的测试点：
- Biz 层：3 个方法需要 UT
- API：3 个接口需要测试
- E2E：1 个核心流程
```

### 步骤 2：选择测试类型

```
请选择要创建的测试类型：

[ ] 单元测试 (UT) - 推荐：业务逻辑层
[ ] API 测试 - 推荐：已有接口定义
[ ] E2E 测试 - 可选：关键流程
[ ] 全部

输入选择 (1/2/3/all)：
```

### 步骤 3：生成测试代码

根据选择生成对应测试文件：

```
📝 生成测试文件...

✅ internal/biz/dept_channel_test.go
   - TestDeptBiz_CreateWithChannel
   - TestDeptBiz_ValidateChannelScope
   - TestDeptBiz_GetAvailableChannels

✅ tests/api/dept_channel_api_test.go
   - TestCreateDept_WithChannel
   - TestCreateDept_ChannelOutOfScope
   - TestGetAvailableChannels

📊 共生成 2 个测试文件，6 个测试用例
```

### 步骤 4：运行验证

```
🔄 运行新创建的测试...

go test -v ./internal/biz/dept_channel_test.go
=== RUN   TestDeptBiz_CreateWithChannel
--- PASS: TestDeptBiz_CreateWithChannel (0.02s)
=== RUN   TestDeptBiz_ValidateChannelScope
--- PASS: TestDeptBiz_ValidateChannelScope (0.01s)
...

✅ 6/6 测试通过
```

---

## 四、测试最佳实践

### 命名规范

| 类型 | 格式 | 示例 |
|-----|------|------|
| UT 文件 | `xxx_test.go` | `user_biz_test.go` |
| UT 函数 | `Test{结构体}_{方法}_{场景}` | `TestUserBiz_Create_Success` |
| API 测试 | `Test{接口}_{场景}` | `TestCreateUser_DuplicateEmail` |
| E2E 测试 | 描述性名称 | `用户完整注册流程` |

### 测试数据管理

```go
// 使用 fixtures 管理测试数据
func setupTestData(t *testing.T) *TestFixtures {
    return &TestFixtures{
        User:  createTestUser(t),
        Dept:  createTestDept(t),
        Token: generateTestToken(t),
    }
}

// 测试后清理
func teardown(t *testing.T, fixtures *TestFixtures) {
    // 清理测试数据
}
```

### Mock 使用原则

- UT：Mock 外部依赖（Store、第三方服务）
- API：Mock 外部服务，使用真实数据库
- E2E：尽量使用真实环境

### 覆盖率目标

| 测试类型 | 建议覆盖率 |
|---------|-----------|
| UT (Biz 层) | >= 80% |
| API | 100% 接口覆盖 |
| E2E | 核心流程 100% |

---

## 五、与需求关联

测试完成后更新需求文档：

```markdown
## 测试覆盖

| 类型 | 文件 | 用例数 | 覆盖率 |
|-----|------|-------|-------|
| UT | dept_channel_test.go | 6 | 85% |
| API | dept_channel_api_test.go | 4 | 100% |
| E2E | - | - | - |

最后测试时间：2024-01-15
测试结果：✅ 全部通过
```
