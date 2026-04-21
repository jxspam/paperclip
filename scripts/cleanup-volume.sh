#!/bin/sh
# cleanup-volume.sh — prune stale workspaces, caches, and logs from /paperclip
# Runs on every container start before the main process.
# All paths are relative to PAPERCLIP_HOME (default: /paperclip).

set -e

PH="${PAPERCLIP_HOME:-/paperclip}"
INSTANCE="${PH}/instances/${PAPERCLIP_INSTANCE_ID:-default}"
MAX_AGE_DAYS="${CLEANUP_MAX_AGE_DAYS:-3}"

bytes_before=$(du -sb "$PH" 2>/dev/null | cut -f1 || echo 0)

echo "[cleanup] Starting volume cleanup (max age: ${MAX_AGE_DAYS}d)..."

# 1. Run logs (NDJSON) — safe to delete, purely diagnostic
if [ -d "${INSTANCE}/data/run-logs" ]; then
  count=$(find "${INSTANCE}/data/run-logs" -type f -name "*.ndjson" -mtime +${MAX_AGE_DAYS} | wc -l)
  if [ "$count" -gt 0 ]; then
    find "${INSTANCE}/data/run-logs" -type f -name "*.ndjson" -mtime +${MAX_AGE_DAYS} -delete
    echo "[cleanup] Deleted $count run-log files"
  fi
fi

# 2. Claude Code session logs — conversation JSONL files
for dir in "${PH}/.claude/projects" "${PH}/.claude"; do
  if [ -d "$dir" ]; then
    count=$(find "$dir" -maxdepth 2 -type f -name "*.jsonl" -mtime +${MAX_AGE_DAYS} | wc -l)
    if [ "$count" -gt 0 ]; then
      find "$dir" -maxdepth 2 -type f -name "*.jsonl" -mtime +${MAX_AGE_DAYS} -delete
      echo "[cleanup] Deleted $count Claude session logs from $dir"
    fi
  fi
done

# 3. Codex session logs
for sessions_dir in "${INSTANCE}/codex-home/sessions" "${INSTANCE}"/companies/*/codex-home/sessions; do
  if [ -d "$sessions_dir" ]; then
    count=$(find "$sessions_dir" -type f -mtime +${MAX_AGE_DAYS} | wc -l)
    if [ "$count" -gt 0 ]; then
      find "$sessions_dir" -type f -mtime +${MAX_AGE_DAYS} -delete
      echo "[cleanup] Deleted $count Codex session files from $sessions_dir"
    fi
  fi
done

# 4. npm / pnpm / yarn caches
for cache_dir in "${PH}/.npm/_cacache" "${PH}/.cache" "${PH}/.pnpm-store" "${PH}/.yarn/cache"; do
  if [ -d "$cache_dir" ]; then
    size=$(du -sm "$cache_dir" 2>/dev/null | cut -f1 || echo 0)
    if [ "$size" -gt 50 ]; then
      rm -rf "$cache_dir"
      echo "[cleanup] Cleared cache $cache_dir (${size}MB)"
    fi
  fi
done

# 5. Git garbage collection in project workspaces
if [ -d "${INSTANCE}/projects" ]; then
  find "${INSTANCE}/projects" -maxdepth 4 -type d -name ".git" | while read gitdir; do
    repo=$(dirname "$gitdir")
    git -C "$repo" gc --auto --quiet 2>/dev/null || true
  done
  echo "[cleanup] Ran git gc on project workspaces"
fi

# 6. Stale git worktrees (leftover from crashed executions)
if [ -d "${INSTANCE}/projects" ]; then
  find "${INSTANCE}/projects" -maxdepth 4 -type d -name ".git" | while read gitdir; do
    repo=$(dirname "$gitdir")
    git -C "$repo" worktree prune 2>/dev/null || true
  done
fi

# 7. Backups older than max age
if [ -d "${INSTANCE}/data/backups" ]; then
  count=$(find "${INSTANCE}/data/backups" -type f -mtime +${MAX_AGE_DAYS} | wc -l)
  if [ "$count" -gt 0 ]; then
    find "${INSTANCE}/data/backups" -type f -mtime +${MAX_AGE_DAYS} -delete
    echo "[cleanup] Deleted $count old backup files"
  fi
fi

bytes_after=$(du -sb "$PH" 2>/dev/null | cut -f1 || echo 0)
freed_mb=$(( (bytes_before - bytes_after) / 1048576 ))
echo "[cleanup] Done. Freed ~${freed_mb}MB"
