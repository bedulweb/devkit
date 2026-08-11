# MCP layout (Grok) — recommended

## Layers

| Layer | MCP | Role |
|-------|-----|------|
| Search | **exa** | web + advanced + deep research |
| Scrape | **firecrawl-mcp** | full page extract |
| Docs lib | **context7** | library docs |
| Files | **filesystem** | manage `~/projects` only |
| Design | framelink / hugeicons / drawio | as needed |

## Folder roots (filesystem MCP)

Only:
- `~/projects` — app + research work
- `~/linux-devkit` — installer/docs

Never expose whole `$HOME` (secrets, `.ssh`, tokens).

## Research tree

See `~/projects/research/README.md`.

## Secrets

Prefer env vars / Doppler over pasting keys in `config.toml`.
Keys in `~/.grok/config.toml` are world-readable to your user — `chmod 600`.

```bash
chmod 600 ~/.grok/config.toml
```

## Runtime

```bash
grok mcp list
grok mcp doctor
# in TUI: /mcps
```
