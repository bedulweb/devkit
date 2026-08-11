---
name: devkit
description: >
  Manage multi-project workspace via linux-devkit: list/add/restore projects,
  resolve paths under ~/projects/apps/<org>/<repo>, edit projects.yaml, and
  guide VPS bootstrap. Use when the user mentions devkit, projects.yaml,
  multi-project layout, add a GitHub repo to the workspace, clone/restore
  wabase/wazapin/betterpay, path conventions, or runs /devkit.
---

# Devkit — multi-project skill (global agent)

Works with any agent that loads Agent Skills (`SKILL.md`): OpenCode, Claude-compatible paths, etc.
Manage **product repos** via `devkit` CLI + `projects.yaml`. Do not invent folders under `$HOME`.

## Canonical layout

```text
~/projects/apps/<org>/<repo>     # product code only
~/linux-devkit/                  # installer + projects.yaml (NOT an app)
~/linux-devkit/projects.yaml     # registry (source of truth)
~/.linux-devkit/projects.yaml    # synced copy
```

| Key | Path | Repo |
|-----|------|------|
| wabase-core | `~/projects/apps/wabase/core` | `wabase/core` |
| wazapin-platform | `~/projects/apps/wazapin/platform` | `wazapin/platform` |
| wazapin-web | `~/projects/apps/wazapin/web` | `wazapin/web` |
| betterpay | `~/projects/apps/usebetterpay/betterpay` | `usebetterpay/betterpay` |

**Rule:** GitHub `org/repo` → disk `apps/<org>/<repo>`. Key = `org-repo` (`/` → `-`).

## CLI

```bash
export PATH="$HOME/.local/bin:$PATH"
devkit doctor
devkit list
devkit path <key>
devkit restore              # all
devkit restore <key>        # one
devkit add <key> <git-url> --path apps/<org>/<repo> --stack bun|go|flutter|python|node
devkit sync-registry
```

Registry file: `$HOME/linux-devkit/projects.yaml` (fallback `$HOME/.linux-devkit/projects.yaml`).

## Add a project

1. Parse URL → `org`, `repo`.
2. Key: `{org}-{repo}` (e.g. `wazapin-api`).
3. Path: `apps/{org}/{repo}`.
4. Stack default: `bun` (TS/JS), `go` for Go.
5. Run:
   ```bash
   devkit add <key> <url> --path apps/<org>/<repo> --stack <stack>
   devkit restore <key>    # needs GH_TOKEN/SSH if private
   devkit list && devkit path <key>
   ```
6. Or edit `projects.yaml` then `devkit sync-registry`.

### YAML template

```yaml
  <key>:
    path: apps/<org>/<repo>
    repo: https://github.com/<org>/<repo>.git
    branch: main
    stack: bun
    description: "..."
    org: <org>
    pm2: <key>
    port: <unique>      # avoid 3001, 3101, 3102, 3201, ...
    doppler: <slug>
    tags: [<org>, product]
```

## Restore / new VPS

1. `bash ~/linux-devkit/install.sh --profile default -y`
2. Private Git: `GH_TOKEN` or SSH (not interactive login as default)
3. Secrets: Doppler — never in projects.yaml
4. `devkit restore` && `devkit doctor`

## Path lookup

```bash
devkit path <key>
devkit list
```

## Cloudflare Wrangler

- Doppler: `CLOUDFLARE_API_TOKEN` (+ optional `CLOUDFLARE_ACCOUNT_ID`)
- Prefer API token env over `wrangler login` OAuth on VPS
- `doppler run --project=<slug> --config=dev -- bunx wrangler deploy` from project dir

## PM2 + Neon

- PM2 process name = yaml `pm2` field
- DB: Neon `DATABASE_URL` from Doppler (no local Postgres by default)

## Do NOT

- Put apps in `~/0new`, `~/my_app`, or random `$HOME/<name>`
- Commit tokens/secrets into yaml or kit
- Use flat `apps/wabase-core` when org has multiple repos — use `apps/wabase/core`

## After changes

1. `devkit list` shows project  
2. `devkit path <key>` under `.../projects/apps/...`  
3. `devkit sync-registry` if yaml hand-edited  
4. Tell user absolute path + next command  
