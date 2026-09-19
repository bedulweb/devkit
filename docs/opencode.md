# OpenCode — custom models + MCP (Doppler-backed)

Template: `config/opencode/opencode.jsonc`
Installer: `scripts/install-opencode.sh`

## Install

```bash
# secrets come from Doppler, never from this repo
export DOPPLER_TOKEN=dp.st.xxx
bash ~/linux-devkit/scripts/install-opencode.sh
# or via install.sh profile default/full (calls it automatically)
```

Result: `~/.config/opencode/opencode.jsonc` (`chmod 600`).

## Secrets

| Var | Used by | Doppler default |
|-----|---------|-----------------|
| `PINKGREEN_API_KEY` | providers `cx`, `hv` (`https://ai.sabergaming.my.id/v1`) | `developer-workstation` / `dev` |
| `ROUTEID_API_KEY` | provider `routeid` | `developer-workstation` / `dev` |
| `EXA_API_KEY` | MCP `exa` | `developer-workstation` / `dev` |
| `FIRECRAWL_API_KEY` | MCP `firecrawl` | `developer-workstation` / `dev` |

Override vault: `DEVKIT_OPENCODE_DOPPLER_PROJECT` / `DEVKIT_OPENCODE_DOPPLER_CONFIG`
(falls back to `DEVKIT_CODEX_DOPPLER_*`).

Legacy alias: `SABER_API_KEY` is accepted as fallback for `PINKGREEN_API_KEY`
(same endpoint, old name). Prefer `PINKGREEN_API_KEY`.

## Models

- `cx`: `cx/gpt-5.6-sol`, `cx/gpt-5.6-terra`, `cx/gpt-5.6-luna`, `cx/gpt-6-astra`
- `hv`: `hv/deepseek-ai/deepseek-v4.1-flash`
- `routeid`: `kimi-k3`, `glm-5.2`, `deepseek-v4-pro-0813`,
  `deepseek-v4-flash-0731`, `qwen3.8-max`, `qwen3.8-flash`

## MCP servers

| Server | Type | Auth |
|--------|------|------|
| `mobbin` | remote `https://api.mobbin.com/mcp` | none |
| `firecrawl` | local `bunx -y firecrawl-mcp` | `{env:FIRECRAWL_API_KEY}` |
| `exa` | remote `https://mcp.exa.ai/mcp` | header `{env:EXA_API_KEY}` |
| `linear` | remote `https://mcp.linear.app/mcp` | OAuth (`/mcp reauth linear`) |
| `agentation` | local `npx -y agentation-mcp server` | none |

## Runtime

```bash
source ~/linux-devkit/scripts/export-env.sh   # loads keys into shell
opencode                                      # keys resolve via {env:}
# or without exporting:
doppler run --project developer-workstation --config dev -- opencode
```

## Serve (`opencode serve`)

`opencode serve` inherits its environment from the parent process. Starting it
bare (systemd unit, login shell without Doppler env, …) serves the custom
models with empty keys and every inference fails with HTTP 401. Always start
it wrapped:

```bash
bash ~/linux-devkit/scripts/serve-opencode.sh --port 4096
# preflight only — exits non-zero naming the missing keys (values never printed):
bash ~/linux-devkit/scripts/serve-opencode.sh --check
```

Stop it with `bash ~/linux-devkit/scripts/stop-dev.sh opencode`.

## Conventions

- Never commit raw keys — config uses `{env:VAR}` placeholders only.
  Enforced by `tests/check-opencode-config.sh` (runs in CI).
- Edit the template, not `~/.config/...` directly, then re-run the installer.
