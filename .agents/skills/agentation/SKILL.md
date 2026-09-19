---
name: agentation
description: >
  Visual annotation feedback loop (Agentation): fetch human page annotations
  (comment, element, x/y, severity, intent) from the Agentation worker via MCP,
  acknowledge or resolve them, and reply in thread. Use when the user mentions
  annotations, visual feedback, page comments, toolbar sessions, pending
  feedback, or runs /agentation. Project source: ~/projects/apps/agentation.
---

# Agentation — annotation feedback skill (global agent)

Agentation connects a browser toolbar (human clicks/annotates on a page) to
agents via MCP. Annotations land as `pending`; the agent reads them, acts on
the code, then acknowledges/resolves. Backend = Cloudflare Worker + D1
(`~/projects/apps/agentation`, `agentation-http`), compatible 1:1 with
`agentation-mcp` in `--http-url` mode.

## MCP tools (server `agentation`, local stdio)

| Tool | Use |
|------|-----|
| `agentation_get_all_pending` | All pending annotations across sessions — start here |
| `agentation_list_sessions` | Active annotation sessions |
| `agentation_get_session` | One session with all its annotations (`sessionId`) |
| `agentation_acknowledge` | Mark annotation seen (`annotationId`) — always ack what you will handle |

## Core loop

1. `agentation_get_all_pending` → pick items for this task.
2. `agentation_get_session` per session for full context (element, elementPath,
   x/y, selectedText, nearbyText, severity, intent, thread).
3. `agentation_acknowledge` each item you accept.
4. Fix code, reply/resolve in thread, keep status moving
   (`pending` → `acknowledged` → `resolved`/`dismissed`).

## Namespace scoping

Worker URL may carry `/p/<namespace>` (e.g. `--http-url https://<worker>/p/tokoku`).
All queries scope to that namespace; no prefix = `default`. Current OpenCode
wiring (`~/.config/opencode/opencode.jsonc` → `mcp.servers.agentation`):

```json
"agentation": {
  "type": "local",
  "command": ["npx", "-y", "agentation-mcp", "server",
              "--mcp-only", "--http-url", "https://agentation.wzpn.net"],
  "enabled": true
}
```

No `npm install` needed for MCP use — `npx -y` fetches/caches
`agentation-mcp` on demand. Verify with `opencode mcp list` (expect
`agentation connected`).

## Worker REST (direct, no MCP)

`GET /health`, `GET /status`, `GET /pending`, `GET /sessions`,
`POST /sessions` (`{url, projectId?}`), `GET /sessions/:id`,
`GET /sessions/:id/pending`, `GET /sessions/:id/events` (SSE snapshot),
`POST /sessions/:id/annotations`, `PATCH|DELETE /annotations/:id`,
`POST /annotations/:id/thread` (`{role, content}`),
`POST /sessions/:id/action` (`{output}`). Auth: none unless worker sets
`API_KEY` (then `x-api-key` or `Bearer`). Prefix any path with `/p/:ns`
for namespaced mode.

## Project ops (source of truth: `~/projects/apps/agentation`)

```bash
cd ~/projects/apps/agentation
bun run dev        # wrangler dev
bun run deploy     # wrangler deploy
# D1: db:create / db:migrate (see package.json), schema.sql
```
