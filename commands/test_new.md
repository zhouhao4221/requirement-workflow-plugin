---
description: 创建测试 - 为新功能编写自动化测试用例
---

# 创建测试

为新开发的功能创建自动化测试用例，包括单元测试、API 测试和 E2E 测试。

> 存储路径和缓存同步规则见 [_common.md](./_common.md)

## 命令格式

```
/req:test_new [REQ-XXX] [--type=ut|api|e2e|all]
```

### 参数

| 参数 | 说明 | 示例 |
|-----|------|------|
| `REQ-XXX` | 需求编号（可选） | `/req:test_new REQ-001` |
| `--type=ut` | 仅创建单元测试 | `/req:test_new --type=ut` |
| `--type=api` | 仅创建 API 测试 | `/req:test_new --type=api` |
| `--type=e2e` | 仅创建 E2E 测试 | `/req:test_new --type=e2e` |
| `--type=all` | 创建所有类型测试 | `/req:test_new --type=all` |
| `--dry-run` | 预览不实际创建 | `/req:test_new --dry-run` |

---

## 执行流程

### 1. 选择需求

- 指定编号 → 使用该需求
- 未指定 → 查找「开发中」或「测试中」的需求
- 多个候选 → 让用户选择

### 2. 分析需求文档

```
📋 分析需求文档...

需求：REQ-001 部门渠道关联
状态：🔨 开发中

📖 功能清单：
1. 部门创建时关联渠道
2. 渠道范围校验（上下级约束）
3. 获取可选渠道列表

📁 涉及文件：
├── internal/model/dept.go
├── internal/store/dept.go
├── internal/biz/dept.go
├── internal/biz/dept_channel.go
└── internal/controller/dept.go

🔍 识别测试点：

┌──────────┬─────────────────────────────┬──────────┐
│ 类型     │ 测试点                       │ 数量     │
├──────────┼─────────────────────────────┼──────────┤
│ UT       │ Biz 层业务方法               │ 5        │
│ API      │ REST 接口                   │ 3        │
│ E2E      │ 用户流程                     │ 1        │
└──────────┴─────────────────────────────┴──────────┘
```

### 3. 选择测试类型

```
请选择要创建的测试类型：

[1] 单元测试 (UT)
    - 测试 Biz 层业务逻辑
    - 使用 Mock 隔离依赖
    - 预计生成 5 个测试用例

[2] API 测试
    - 测试 REST 接口
    - 验证请求/响应/错误码
    - 预计生成 3 个测试文件

[3] E2E 测试
    - 测试完整用户流程
    - 端到端场景验证
    - 预计生成 1 个测试文件

[4] 全部

请输入选择 (1/2/3/4)：
```

### 4. 生成单元测试 (UT)

#### 4.1 分析被测方法

```
📦 分析 Biz 层方法...

internal/biz/dept_channel.go:
├── func (b *DeptBiz) CreateWithChannel(ctx, req) error
├── func (b *DeptBiz) ValidateChannelScope(ctx, deptID, channels) error
├── func (b *DeptBiz) GetAvailableChannels(ctx, parentID) ([]Channel, error)
├── func (b *DeptBiz) UpdateChannels(ctx, deptID, channels) error
└── func (b *DeptBiz) InheritParentChannels(ctx, deptID) error
```

#### 4.2 生成测试用例

```go
// 生成文件：internal/biz/dept_channel_test.go

package biz

import (
    "context"
    "testing"

    "github.com/golang/mock/gomock"
    "github.com/stretchr/testify/assert"
)

func TestDeptBiz_CreateWithChannel_Success(t *testing.T) {
    // Arrange
    ctrl := gomock.NewController(t)
    defer ctrl.Finish()

    mockStore := mock.NewMockDeptStore(ctrl)
    mockStore.EXPECT().Create(gomock.Any(), gomock.Any()).Return(nil)

    biz := NewDeptBiz(mockStore)

    // Act
    err := biz.CreateWithChannel(context.Background(), &CreateDeptReq{
        Name:     "测试部门",
        ParentID: 1,
        Channels: []int64{1, 2, 3},
    })

    // Assert
    assert.NoError(t, err)
}

func TestDeptBiz_CreateWithChannel_ChannelOutOfScope(t *testing.T) {
    // 测试渠道超出范围的场景
    ctrl := gomock.NewController(t)
    defer ctrl.Finish()

    mockStore := mock.NewMockDeptStore(ctrl)
    mockStore.EXPECT().GetParentChannels(gomock.Any(), int64(1)).Return([]int64{1, 2}, nil)

    biz := NewDeptBiz(mockStore)

    err := biz.CreateWithChannel(context.Background(), &CreateDeptReq{
        Name:     "测试部门",
        ParentID: 1,
        Channels: []int64{1, 2, 3}, // 3 不在父级范围内
    })

    assert.Error(t, err)
    assert.Equal(t, errno.ErrChannelOutOfScope, err)
}

func TestDeptBiz_ValidateChannelScope_ParentNoChannel(t *testing.T) {
    // 上级部门未设置渠道，下级可任意选择
}

func TestDeptBiz_ValidateChannelScope_MustBeSubset(t *testing.T) {
    // 下级渠道必须是上级的子集
}

func TestDeptBiz_GetAvailableChannels_RootDept(t *testing.T) {
    // 根部门返回所有渠道
}

func TestDeptBiz_GetAvailableChannels_SubDept(t *testing.T) {
    // 子部门返回父级渠道的子集
}
```

#### 4.3 生成 Mock 文件

```
📝 生成 Mock 文件...

go generate ./internal/store/...

✅ 生成：internal/store/mock/dept_store_mock.go
```

### 5. 生成 API 测试

#### 5.1 提取 API 定义

```
📡 提取 API 定义...

从需求文档提取：
├── POST /api/v1/dept           创建部门（带渠道）
├── PUT /api/v1/dept/:id        更新部门渠道
└── GET /api/v1/dept/channels   获取可选渠道
```

#### 5.2 生成测试代码

```go
// 生成文件：tests/api/dept_channel_api_test.go

//go:build integration

package api

import (
    "net/http"
    "net/http/httptest"
    "strings"
    "testing"

    "github.com/stretchr/testify/assert"
)

func TestCreateDept_WithChannel(t *testing.T) {
    router := setupTestRouter()

    tests := []struct {
        name     string
        body     string
        wantCode int
        wantBody string
    }{
        {
            name:     "正常创建-带渠道",
            body:     `{"name":"测试部门","parent_id":1,"channels":[1,2]}`,
            wantCode: http.StatusOK,
        },
        {
            name:     "正常创建-不带渠道",
            body:     `{"name":"测试部门","parent_id":1}`,
            wantCode: http.StatusOK,
        },
        {
            name:     "渠道超出范围",
            body:     `{"name":"测试部门","parent_id":1,"channels":[1,2,99]}`,
            wantCode: http.StatusBadRequest,
            wantBody: `"code":"CHANNEL_OUT_OF_SCOPE"`,
        },
        {
            name:     "缺少必填字段",
            body:     `{"parent_id":1}`,
            wantCode: http.StatusBadRequest,
            wantBody: `"code":"INVALID_PARAMS"`,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            req := httptest.NewRequest("POST", "/api/v1/dept",
                strings.NewReader(tt.body))
            req.Header.Set("Content-Type", "application/json")
            req.Header.Set("Authorization", "Bearer "+testToken)

            w := httptest.NewRecorder()
            router.ServeHTTP(w, req)

            assert.Equal(t, tt.wantCode, w.Code)
            if tt.wantBody != "" {
                assert.Contains(t, w.Body.String(), tt.wantBody)
            }
        })
    }
}

func TestGetAvailableChannels(t *testing.T) {
    router := setupTestRouter()

    tests := []struct {
        name     string
        parentID string
        wantCode int
        wantLen  int
    }{
        {
            name:     "根部门-返回所有渠道",
            parentID: "0",
            wantCode: http.StatusOK,
            wantLen:  10, // 假设系统有10个渠道
        },
        {
            name:     "子部门-返回父级子集",
            parentID: "1",
            wantCode: http.StatusOK,
            wantLen:  3, // 父级有3个渠道
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            req := httptest.NewRequest("GET",
                "/api/v1/dept/channels?parent_id="+tt.parentID, nil)
            req.Header.Set("Authorization", "Bearer "+testToken)

            w := httptest.NewRecorder()
            router.ServeHTTP(w, req)

            assert.Equal(t, tt.wantCode, w.Code)
            // 验证返回数量
        })
    }
}

func TestUpdateDeptChannels(t *testing.T) {
    // 测试更新渠道
}
```

### 6. 生成 E2E 测试

**前提条件**：E2E 测试需要完整的测试环境

```
⚠️ E2E 测试需要启动测试环境：
- Docker 容器（MySQL + Redis）
- 后端服务（本地）
- 前端服务（本地）

是否检查并启动测试环境？(y/n): y
```

#### 6.1 识别用户流程

```
🎯 识别用户流程...

核心流程：部门渠道管理
1. 管理员登录
2. 进入部门管理页面
3. 创建部门并选择渠道
4. 验证渠道限制生效
5. 修改渠道设置
```

#### 6.2 生成测试代码 (Playwright)

```typescript
// 生成文件：tests/e2e/dept-channel.spec.ts

import { test, expect } from '@playwright/test';

test.describe('部门渠道管理', () => {
  test.beforeEach(async ({ page, request }) => {
    // 重置测试数据
    await request.post('/api/test/reset-db');

    // 登录
    await page.goto('/login');
    await page.getByTestId('username').fill('admin');
    await page.getByTestId('password').fill('password');
    await page.getByTestId('submit').click();
    await expect(page).toHaveURL(/.*dashboard/);
  });

  test('创建部门时选择渠道', async ({ page }) => {
    // 进入部门管理
    await page.goto('/system/dept');

    // 点击新建
    await page.getByTestId('btn-create').click();

    // 填写表单
    await page.getByTestId('input-name').fill('销售一部');
    await page.getByTestId('select-parent').click();
    await page.getByText('总公司').click();

    // 选择渠道
    await page.getByTestId('select-channels').click();
    await page.getByText('天猫').click();
    await page.getByText('京东').click();
    await page.keyboard.press('Escape'); // 关闭下拉框

    // 提交
    await page.getByTestId('btn-submit').click();

    // 验证成功
    await expect(page.getByText('创建成功')).toBeVisible();
    await expect(page.getByText('销售一部')).toBeVisible();
  });

  test('子部门渠道不能超出父级范围', async ({ page, request }) => {
    // 创建有渠道限制的父部门
    await request.post('/api/test/create-dept', {
      data: { name: '父部门', channels: ['天猫', '京东'] }
    });

    await page.goto('/system/dept');
    await page.getByTestId('btn-create').click();

    await page.getByTestId('input-name').fill('子部门');
    await page.getByTestId('select-parent').click();
    await page.getByText('父部门').click();

    // 渠道选择应该只显示父级的渠道
    await page.getByTestId('select-channels').click();
    await expect(page.getByText('天猫')).toBeVisible();
    await expect(page.getByText('京东')).toBeVisible();
    await expect(page.getByText('拼多多')).not.toBeVisible(); // 父级没有，不应显示
  });

  test('修改部门渠道', async ({ page }) => {
    // 测试修改渠道
  });
});
```

### 7. 测试文件汇总

```
📊 测试文件生成完成

┌──────────┬────────────────────────────────────┬──────────┐
│ 类型     │ 文件                                │ 用例数   │
├──────────┼────────────────────────────────────┼──────────┤
│ UT       │ internal/biz/dept_channel_test.go  │ 6        │
│ API      │ tests/api/dept_channel_api_test.go │ 4        │
│ E2E      │ cypress/e2e/dept-channel.cy.ts     │ 3        │
├──────────┼────────────────────────────────────┼──────────┤
│ 合计     │ 3 个文件                            │ 13       │
└──────────┴────────────────────────────────────┴──────────┘

✅ 已生成 Mock 文件
✅ 已添加测试数据 fixtures
```

### 8. 运行验证

```
🔄 运行新创建的测试...

go test -v ./internal/biz/dept_channel_test.go
=== RUN   TestDeptBiz_CreateWithChannel_Success
--- PASS: (0.02s)
=== RUN   TestDeptBiz_CreateWithChannel_ChannelOutOfScope
--- PASS: (0.01s)
...

go test -tags=integration -v ./tests/api/dept_channel_api_test.go
=== RUN   TestCreateDept_WithChannel
--- PASS: (0.15s)
...

📊 验证结果：13/13 通过

💡 下一步：
- 运行全量回归：/req:test_regression
- 继续开发：/req:dev
- 完成需求：/req:done
```

### 9. 更新需求文档

自动更新需求文档的测试覆盖章节：

```markdown
## 测试覆盖

| 类型 | 文件 | 用例数 | 覆盖率 |
|-----|------|-------|-------|
| UT | internal/biz/dept_channel_test.go | 6 | 85% |
| API | tests/api/dept_channel_api_test.go | 4 | 100% |
| E2E | cypress/e2e/dept-channel.cy.ts | 3 | - |

创建时间：2024-01-15
最后运行：2024-01-15 ✅ 全部通过
```

---

## 测试模板

### UT 模板（Go）

```go
func Test{Struct}_{Method}_{Scenario}(t *testing.T) {
    // Arrange - 准备数据和 Mock
    ctrl := gomock.NewController(t)
    defer ctrl.Finish()

    // Act - 执行被测方法

    // Assert - 验证结果
}
```

### API 测试模板（Go）

```go
func Test{Endpoint}_{Scenario}(t *testing.T) {
    tests := []struct {
        name     string
        method   string
        path     string
        body     string
        wantCode int
        wantBody string
    }{
        // 测试用例
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            // 执行请求
            // 验证响应
        })
    }
}
```

### E2E 测试模板（Playwright）

```typescript
import { test, expect } from '@playwright/test';

test.describe('功能名称', () => {
  test.beforeEach(async ({ page, request }) => {
    // 重置测试数据
    await request.post('/api/test/reset-db');

    // 登录（如需要）
    await page.goto('/login');
    await page.getByTestId('username').fill('user');
    await page.getByTestId('password').fill('password');
    await page.getByTestId('submit').click();
    await expect(page).toHaveURL(/.*dashboard/);
  });

  test('场景描述', async ({ page }) => {
    // 页面操作
    await page.goto('/target-page');
    await page.getByTestId('button').click();

    // 断言验证
    await expect(page.getByText('成功')).toBeVisible();
  });
});
```

---

## 用户输入

$ARGUMENTS
