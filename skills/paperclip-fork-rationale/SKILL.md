---
name: paperclip-fork-rationale
description: >
  Documents every change made in jxspam/paperclip (our private fork) compared to
  upstream paperclipai/paperclip. Use this skill before modifying the fork to
  understand what has already been changed and why, to avoid regressions or
  conflicting with existing patches. Also consult before syncing upstream.
---

# Paperclip Fork Rationale

This is a **private fork** of [paperclipai/paperclip](https://github.com/paperclipai/paperclip) deployed on Railway as `paperclip-prod`. Every change below is a deliberate divergence from upstream. When syncing upstream, preserve these patches.

## Changed Files (8 total)

### 1. `Dockerfile`

**What changed:**
- Added `fontconfig fonts-dejavu-core` to the `apt-get install` line
- Removed `VOLUME ["/paperclip"]` directive

**Why:**
- **fonts-dejavu-core**: Sharp/librsvg renders org chart SVGs to PNG server-side. Without a real font on disk, all text renders as tofu rectangles (U+FFFD). DejaVu Sans is the font librsvg resolves.
- **VOLUME removed**: Railway bans the `VOLUME` directive — it conflicts with Railway's own volume mount system and causes build failures.

---

### 2. `scripts/docker-entrypoint.sh`

**What changed:**
- `chown -R node:node /paperclip` now runs **unconditionally** on every startup, not only when UID/GID changes.

**Why:**
- On Railway the default UID/GID is already 1000:1000, so the conditional `if [ "$changed" = "1" ]` never triggered. But files created by root (SSH sessions, `companies.sh` imports, volume mounts) stayed root-owned, causing `EACCES` errors when agents tried to write run logs or session data.

---

### 3. `packages/adapters/claude-local/src/server/execute.ts`

**What changed:**
- `dangerouslySkipPermissions` now defaults to **`true`** (was `false`)
- Added `wrapCommandForNonRoot()` — when running as root (uid 0), wraps Claude CLI invocations with `runuser -u node --`
- Skills directory gets `chmod 0o755` after creation

**Why:**
- **Default true**: Paperclip heartbeat runs are always non-interactive. Permission prompts would block indefinitely with no human to approve them. Agents can still explicitly set `false` for development.
- **runuser wrapper**: Claude Code rejects `--dangerously-skip-permissions` when the process runs as root. Railway containers start as root, so the adapter must drop to the `node` user before invoking Claude.
- **chmod 755**: When Claude runs as `node` (via runuser) but the skills tmpdir was created by root, Claude can't read the skill files without world-readable permissions.

---

### 4. `packages/adapters/claude-local/src/server/test.ts`

**What changed:**
- Added the same `wrapCommandForNonRoot()` helper for environment probe commands.

**Why:**
- The environment test (`testEnvironment`) also invokes Claude CLI. Without the wrapper, the health check fails on Railway containers running as root, making the agent appear unhealthy even when Claude is installed and working.

---

### 5. `packages/adapters/codex-local/src/server/execute.ts`

**What changed:**
- `dangerouslyBypassApprovalsAndSandbox` now defaults to **`true`** (was `false`)

**Why:**
- Same rationale as Claude: Codex runs in non-interactive heartbeats. Approval prompts block forever. The default must be `true` for autonomous operation.

---

### 6. `server/src/routes/org-chart-svg.ts`

**What changed:**
- All theme `font` properties changed from `'Inter'` to `'DejaVu Sans', sans-serif`
- Overlay text (company name, stats) also changed to DejaVu Sans

**Why:**
- The SVG-to-PNG pipeline uses Sharp (backed by librsvg). librsvg is a C library with no JavaScript engine — it cannot fetch web fonts, execute CSS `@import`, or resolve `system-ui`. It needs an actual font file registered with fontconfig. `Inter` is a web font not present on any server. `DejaVu Sans` is installed via `fonts-dejavu-core` in the Dockerfile.

---

### 7. `railway.toml` (new file)

**What changed:**
- Added Railway deployment configuration: Dockerfile builder, restart policy (ON_FAILURE, max 10 retries).

**Why:**
- Railway needs this file to know how to build and deploy the service. Without it, Railway defaults to Nixpacks which doesn't work for this project's multi-stage Dockerfile.

---

### 8. `.railwayignore` (new file)

**What changed:**
- Excludes `.git`, `node_modules`, `coverage`, `data`, `tmp`, `*.log` from the Railway build context.

**Why:**
- Reduces Docker build context size and prevents accidental inclusion of local development artifacts, PGlite data directories, or large log files in the deployed image.

---

## Summary Table

| File | Category | Upstream-safe? |
|------|----------|----------------|
| `Dockerfile` | Infrastructure | Yes — additive (font package + remove VOLUME) |
| `docker-entrypoint.sh` | Infrastructure | Yes — strictly more correct |
| `claude-local/execute.ts` | Adapter | **Behavioral** — changes default from false to true |
| `claude-local/test.ts` | Adapter | Yes — additive (root wrapper) |
| `codex-local/execute.ts` | Adapter | **Behavioral** — changes default from false to true |
| `org-chart-svg.ts` | Rendering | **Visual** — different font in exports |
| `railway.toml` | Infrastructure | Yes — new file, no conflict |
| `.railwayignore` | Infrastructure | Yes — new file, no conflict |

## Upstream Sync Procedure

```bash
git fetch upstream
git merge upstream/master
# Resolve conflicts in the 3 behavioral files above
# Test: docker build, deploy to Railway, verify org chart renders, verify heartbeat runs
```

The most likely merge conflicts are in the adapter `execute.ts` files (the default value changes) and `org-chart-svg.ts` (font references). Infrastructure files (Dockerfile, railway.toml, .railwayignore) are additive and won't conflict.
