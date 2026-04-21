#!/bin/sh
# sync-references.sh — clone or pull public reference repos for agent use
# Repos live at /paperclip/references/<name>/ on the persistent volume.

set -e

PH="${PAPERCLIP_HOME:-/paperclip}"
REF_DIR="${PH}/references"
POLL_INTERVAL="${SYNC_POLL_INTERVAL:-1800}"  # default: 30 minutes

mkdir -p "$REF_DIR"

sync_repo() {
  url="$1"
  name="$2"
  dest="${REF_DIR}/${name}"

  if [ -d "${dest}/.git" ]; then
    echo "[sync] Pulling ${name}..."
    cd "$dest"
    prev=$(git rev-parse HEAD 2>/dev/null || echo "none")
    git fetch --depth 1 origin 2>/dev/null
    git reset --hard origin/HEAD 2>/dev/null
    curr=$(git rev-parse HEAD 2>/dev/null || echo "none")
    if [ "$prev" != "$curr" ]; then
      echo "[sync] ${name} updated: ${prev:0:8} -> ${curr:0:8}"
    else
      echo "[sync] ${name} already up to date"
    fi
  else
    echo "[sync] Cloning ${name}..."
    rm -rf "$dest"
    git clone --depth 1 "$url" "$dest" 2>/dev/null
    echo "[sync] ${name} cloned"
  fi
}

run_sync() {
  sync_repo "https://github.com/openclaw/openclaw.git" "openclaw"
  sync_repo "https://github.com/NousResearch/hermes-agent.git" "hermes-agent"
  echo "[sync] Done at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

# If called with --daemon, run once then loop in background
if [ "$1" = "--daemon" ]; then
  run_sync
  while true; do
    sleep "$POLL_INTERVAL"
    run_sync
  done
else
  run_sync
fi
