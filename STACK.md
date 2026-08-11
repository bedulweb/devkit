# Stack (ujang)

- Agents: Grok + OpenCode
- JS: Bun (primary), Node via nvm (fallback)
- TypeScript: 7.x
- Go: official toolchain → ~/.local/go
- Secrets: Doppler → env (never commit keys)
- Multi-project: projects.yaml + devkit restore
- Research: Exa MCP (+ Firecrawl) via env

## Run agents with secrets

```bash
# sekali: isi ~/.devkit.env (DOPPLER_TOKEN, DOPPLER_PROJECT, DOPPLER_CONFIG)
source ~/linux-devkit/scripts/export-doppler.sh

doppler run --project="${DOPPLER_PROJECT:-wazapin-platform}" --config=dev -- grok
doppler run --project="${DOPPLER_PROJECT:-wazapin-platform}" --config=dev -- opencode
```

## Required Doppler keys (suggested)

```
EXA_API_KEY
FIRECRAWL_API_KEY
GH_TOKEN                 # private app clone (optional)
# plus any CONTEXT7 / FIGMA keys you use
```
