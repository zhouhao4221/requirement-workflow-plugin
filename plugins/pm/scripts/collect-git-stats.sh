#!/bin/bash
# collect-git-stats.sh - Git 统计数据采集脚本
# 用法: collect-git-stats.sh [--from=DATE] [--to=DATE] [--mode=summary|commits|authors|types]
#
# 输出 JSON 格式的统计数据，供 pm 插件命令使用

set -euo pipefail

# 参数解析
FROM_DATE=""
TO_DATE=""
MODE="summary"

for arg in "$@"; do
  case $arg in
    --from=*) FROM_DATE="${arg#*=}" ;;
    --to=*) TO_DATE="${arg#*=}" ;;
    --mode=*) MODE="${arg#*=}" ;;
  esac
done

# 构建日期参数
DATE_ARGS=""
if [ -n "$FROM_DATE" ]; then
  DATE_ARGS="$DATE_ARGS --since=$FROM_DATE"
fi
if [ -n "$TO_DATE" ]; then
  DATE_ARGS="$DATE_ARGS --until=${TO_DATE}T23:59:59"
fi

# 检查是否在 git 仓库中
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo '{"error": "not a git repository"}'
  exit 1
fi

case $MODE in
  summary)
    # 提交总数
    TOTAL=$(git log --oneline --no-merges $DATE_ARGS 2>/dev/null | wc -l | tr -d ' ')

    # 代码变更统计
    STAT_LINE=$(git log --shortstat --no-merges $DATE_ARGS 2>/dev/null | \
      awk '/files? changed/{f+=$1; i+=$4; d+=$6} END{printf "%d %d %d", f, i, d}')
    FILES_CHANGED=$(echo "$STAT_LINE" | awk '{print $1}')
    INSERTIONS=$(echo "$STAT_LINE" | awk '{print $2}')
    DELETIONS=$(echo "$STAT_LINE" | awk '{print $3}')

    # 活跃分支数
    BRANCHES=$(git branch -a 2>/dev/null | wc -l | tr -d ' ')

    # Tag 数
    TAGS=$(git tag 2>/dev/null | wc -l | tr -d ' ')

    # 最新 tag
    LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "none")

    # 贡献者数
    CONTRIBUTORS=$(git shortlog -sn --no-merges $DATE_ARGS 2>/dev/null | wc -l | tr -d ' ')

    echo "{\"total_commits\": $TOTAL, \"files_changed\": $FILES_CHANGED, \"insertions\": $INSERTIONS, \"deletions\": $DELETIONS, \"branches\": $BRANCHES, \"tags\": $TAGS, \"latest_tag\": \"$LATEST_TAG\", \"contributors\": $CONTRIBUTORS}"
    ;;

  commits)
    # 按日期统计每天提交数
    echo "["
    FIRST=true
    git log --format='%ad' --date=short --no-merges $DATE_ARGS 2>/dev/null | sort | uniq -c | sort -k2 | while read count date; do
      if [ "$FIRST" = true ]; then
        FIRST=false
      else
        echo ","
      fi
      printf '{"date": "%s", "count": %d}' "$date" "$count"
    done
    echo "]"
    ;;

  authors)
    # 按作者统计
    echo "["
    FIRST=true
    git shortlog -sn --no-merges $DATE_ARGS 2>/dev/null | while read count author; do
      if [ "$FIRST" = true ]; then
        FIRST=false
      else
        echo ","
      fi
      printf '{"author": "%s", "commits": %d}' "$author" "$count"
    done
    echo "]"
    ;;

  types)
    # 按提交类型统计
    echo "["
    FIRST=true
    git log --oneline --no-merges $DATE_ARGS 2>/dev/null | \
      sed 's/^[a-f0-9]* //' | \
      grep -oE '^(feat|fix|refactor|perf|docs|test|chore|style|ci|build|新功能|修复|重构|优化|文档|测试|构建)' | \
      sort | uniq -c | sort -rn | while read count type; do
        if [ "$FIRST" = true ]; then
          FIRST=false
        else
          echo ","
        fi
        printf '{"type": "%s", "count": %d}' "$type" "$count"
      done
    echo "]"
    ;;

  *)
    echo '{"error": "unknown mode: '"$MODE"'"}'
    exit 1
    ;;
esac
