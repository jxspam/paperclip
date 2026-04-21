#!/bin/sh
set -e

# Capture runtime UID/GID from environment variables, defaulting to 1000
PUID=${USER_UID:-1000}
PGID=${USER_GID:-1000}

# Adjust the node user's UID/GID if they differ from the runtime request
# and fix volume ownership only when a remap is needed
changed=0

if [ "$(id -u node)" -ne "$PUID" ]; then
    echo "Updating node UID to $PUID"
    usermod -o -u "$PUID" node
    changed=1
fi

if [ "$(id -g node)" -ne "$PGID" ]; then
    echo "Updating node GID to $PGID"
    groupmod -o -g "$PGID" node
    usermod -g "$PGID" node
    changed=1
fi

# Always fix /paperclip ownership on startup. Files may be root-owned
# from volume mounts, SSH sessions, or companies.sh imports.
chown -R node:node /paperclip

# Prune stale workspaces, caches, and logs before starting
cleanup-volume.sh || echo "Warning: cleanup-volume.sh failed, continuing anyway"

# Install Claude Code MCP plugins if not already present (persistent on /paperclip volume)
PLUGIN_FILE="/paperclip/.claude/plugins/installed_plugins.json"
if ! grep -q "asana@claude-plugins-official" "$PLUGIN_FILE" 2>/dev/null; then
  echo "Installing Claude plugin: asana@claude-plugins-official"
  gosu node claude plugin install asana@claude-plugins-official || true
fi
if ! grep -q "slack@claude-plugins-official" "$PLUGIN_FILE" 2>/dev/null; then
  echo "Installing Claude plugin: slack@claude-plugins-official"
  gosu node claude plugin install slack@claude-plugins-official || true
fi

exec gosu node "$@"
