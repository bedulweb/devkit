# devkit

Installer + multi-project workspace for disposable Linux VPs.

- **Tools:** Bun, TypeScript 7, Wrangler, Go, PM2, Doppler, gh, modern CLI
- **Projects:** `~/projects/apps/<org>/<repo>` via `projects.yaml`
- **Agents:** global skills pack (`npx skills`) + skill `devkit`
- **Secrets:** Doppler (not in this repo)

## New VM (one shot)

```bash
# optional for private app repos:
export GH_TOKEN=github_pat_xxx
export DOPPLER_TOKEN=dp.st.xxx

curl -fsSL https://raw.githubusercontent.com/bedulweb/devkit/main/bootstrap-vps.sh | bash
```

Or:

```bash
git clone https://github.com/bedulweb/devkit.git ~/linux-devkit
bash ~/linux-devkit/install.sh --profile default -y
source ~/.bashrc
devkit restore
bash ~/linux-devkit/scripts/install-skills.sh
```

## Layout

```text
~/projects/apps/
  wabase/core
  wazapin/platform
  wazapin/web
  usebetterpay/betterpay
~/linux-devkit/          # this repo (or ~/devkit)
```

## Commands

```bash
devkit doctor
devkit list
devkit path wabase-core
devkit restore
devkit add org-repo https://github.com/org/repo.git --path apps/org/repo --stack bun
```

## Profiles

| Profile | Contents |
|---------|----------|
| minimal | core CLI + bun/go basics |
| default | + Bun, TypeScript 7, Wrangler, Herdr, Doppler, agent tools, and skills pack |
| full | + docker/flutter/ccgram hooks |

## Skills

```bash
bash scripts/install-skills.sh
# or see skills-manifest.txt
```

## Cloudflare / Neon

- DB: Neon `DATABASE_URL` via Doppler
- Workers: `CLOUDFLARE_API_TOKEN` via Doppler (not OAuth on VPS)
