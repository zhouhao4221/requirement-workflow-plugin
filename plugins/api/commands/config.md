---
description: API 配置管理 - 初始化和管理 Swagger 数据源配置
argument-hint: "[init|list|set] [参数]"
allowed-tools: Read, Write, Edit, Bash(python3:*)
model: claude-sonnet-4-6
---

# API 配置管理

管理 `.api-config.json` 配置文件，包括初始化、添加/删除数据源、查看配置。

## 命令格式

```
/api:config [子命令] [参数]
```

## 子命令

| 子命令 | 说明 | 示例 |
|-------|------|------|
| `init` | 初始化配置文件 | `/api:config init` |
| (空) | 查看当前配置 | `/api:config` |
| `add` | 添加 Swagger 数据源 | `/api:config add` |
| `remove` | 删除数据源 | `/api:config remove 主服务` |

## 执行流程

### /api:config init

1. 检查项目根目录是否已存在 `.api-config.json`
   - **已存在** → 显示当前配置，询问是否重新初始化
   - **不存在** → 继续初始化

2. 交互式引导收集信息：
   - **Swagger 地址**：询问用户后端 Swagger 文档的 URL 或本地文件路径
   - **服务名称**：给数据源命名（如「主服务」「支付服务」）
   - **API 前缀**：可选，如 `/api/v1`

3. 自动检测项目结构确定 codegen 配置：
   - 检查 `src/api/` 或 `src/services/` 是否存在 → 设为 `outputDir`
   - 检查 `src/types/` 是否存在 → 设为 `typeDir`
   - 都不存在 → 使用默认值

4. 生成 `.api-config.json` 写入项目根目录

5. 提示用户将 `.api-config.json` 加入版本控制

### /api:config（查看配置）

读取并展示 `.api-config.json` 内容：

```
📋 API 配置

数据源：
  1. 主服务 — http://localhost:8080/swagger/doc.json [/api/v1]
  2. 支付服务 — ./docs/payment-swagger.json [/pay/v1]

代码生成：
  请求函数目录：src/api
  类型定义目录：src/types/api
  字段命名风格：camelCase

请求库检测：axios (来自 package.json)
封装文件：src/utils/request.ts
```

### /api:config add

交互式添加新的 Swagger 数据源：

1. 询问数据源类型（URL / 本地文件）
2. 收集地址/路径和服务名称
3. 可选：API 前缀
4. 验证连通性（URL 类型尝试请求，文件类型检查是否存在）
5. 追加到 `.api-config.json` 的 `swagger.sources` 数组

### /api:config remove <服务名>

1. 在 `swagger.sources` 中查找匹配的 `name`
2. 找到 → 展示即将删除的数据源信息，确认后删除
3. 未找到 → 列出所有可用数据源名称

## 配置文件模板

```json
{
  "swagger": {
    "sources": [
      {
        "name": "主服务",
        "url": "http://localhost:8080/swagger/doc.json",
        "prefix": "/api/v1"
      }
    ]
  },
  "codegen": {
    "outputDir": "src/api",
    "typeDir": "src/types/api",
    "fieldCase": "camelCase"
  }
}
```
