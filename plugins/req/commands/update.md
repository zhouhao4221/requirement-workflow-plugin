---
description: 热更新插件 - 从源目录拉取最新命令文件和技能
argument-hint: "[--check]"
allowed-tools: Read, Bash(git:*, jq:*, cat:*)
model: claude-haiku-4-5-20251001
---

# 热更新 req 插件

从插件源目录拉取最新版本，所有使用该插件的项目立即生效（无需重装）。

`--check`：只检查是否有更新，不执行拉取。

## 执行流程

### 1. 定位插件源目录

依次查找：

```bash
# 1. 当前项目设置
SOURCE_PATH=$(jq -r '
  .extraKnownMarketplaces | to_entries[] |
  select(.value.source.source == "directory") |
  .value.source.path
' .claude/settings.local.json 2>/dev/null | head -1)

# 2. 全局用户设置
if [ -z "$SOURCE_PATH" ]; then
  SOURCE_PATH=$(jq -r '
    .extraKnownMarketplaces | to_entries[] |
    select(.value.source.source == "directory") |
    .value.source.path
  ' ~/.claude/settings.json 2>/dev/null | head -1)
fi
```

若找不到或 source 类型非 `directory`：

```
⚠️  未找到本地目录源。

当前插件以非目录方式安装，无法热更新。
如需更新，请在原安装来源重新安装。
```

退出。

### 2. 验证是 git 仓库

```bash
if ! git -C "$SOURCE_PATH" rev-parse --is-inside-work-tree &>/dev/null; then
    echo "❌ 插件源目录不是 git 仓库：$SOURCE_PATH"
    exit 1
fi
```

### 3. 检查远程更新

```bash
git -C "$SOURCE_PATH" fetch origin --quiet

LOCAL=$(git -C "$SOURCE_PATH" rev-parse HEAD)
REMOTE=$(git -C "$SOURCE_PATH" rev-parse "@{u}" 2>/dev/null)

if [ "$LOCAL" = "$REMOTE" ]; then
    CURRENT_VER=$(cat "$SOURCE_PATH/plugins/req/.claude-plugin/plugin.json" 2>/dev/null | jq -r '.version // "unknown"')
    echo "✅ 已是最新版本（$CURRENT_VER）"
    exit 0
fi

# 展示待拉取的提交
echo "📦 发现更新："
git -C "$SOURCE_PATH" log HEAD..@{u} --oneline --no-merges
```

**`--check` 模式**：到此退出，不执行 pull。

### 4. 执行更新

```bash
BEFORE=$(git -C "$SOURCE_PATH" rev-parse HEAD)

git -C "$SOURCE_PATH" pull --ff-only origin

AFTER=$(git -C "$SOURCE_PATH" rev-parse HEAD)
NEW_VER=$(cat "$SOURCE_PATH/plugins/req/.claude-plugin/plugin.json" 2>/dev/null | jq -r '.version // "unknown"')
```

### 5. 输出结果

```
✅ 插件已更新至 v<NEW_VER>

更新内容：
  <git log BEFORE..AFTER --oneline --no-merges 的输出>

源目录：<SOURCE_PATH>
所有使用此插件的项目立即生效，无需重启。
```

若 `pull --ff-only` 失败（本地有分歧提交）：

```
❌ 拉取失败：源目录存在本地修改或分歧提交。
   请手动处理：cd <SOURCE_PATH> && git status
```

## 用户输入

$ARGUMENTS
