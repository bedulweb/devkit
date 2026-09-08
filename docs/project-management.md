# Multi-project + multi-VPS

## Problem
Setiap bulan ganti VPS → males install tools + clone wabase, wazapin, dll satu-satu.

## Solution
1. **install.sh** → semua tools (sekali)
2. **projects.yaml** → daftar semua project (source of truth)
3. **devkit restore** → clone/pull semua project

## New VPS (ideal)

```bash
# 1) auth once
gh auth login

# 2) bootstrap kit + tools + all projects
export DEVKIT_KIT_REPO=git@github.com:bedulweb/devkit.git
curl -fsSL https://raw.githubusercontent.com/bedulweb/devkit/main/bootstrap-vps.sh | bash
```

Atau manual:

```bash
git clone git@github.com:bedulweb/devkit.git ~/linux-devkit
bash ~/linux-devkit/install.sh --profile default --with-docker -y
source ~/.bashrc
devkit restore
```

## Register a project

```bash
devkit add wabase git@github.com:ujangid/wabase.git --path apps/wabase --stack node
devkit add wazapin git@github.com:ujangid/wazapin.git --path apps/wazapin --stack flutter
devkit restore wabase
```

Edit YAML langsung: `~/linux-devkit/projects.yaml` lalu `devkit sync-registry` + git push.

## Layout on every machine

```
~/projects/
  apps/
    wabase/
    wazapin/
  web/ api/ mobile/
  research/
```

## Secrets
Not in projects.yaml. Use:
- `gh auth` for private repos
- Doppler per project (`doppler run --project=<slug> --config=<env> -- ...`)
- never commit API keys

## Exa MCP
Exa is for **research/search**, not for cloning your private apps.
Use Exa when you need docs/competitors; use **devkit restore** for your code.
