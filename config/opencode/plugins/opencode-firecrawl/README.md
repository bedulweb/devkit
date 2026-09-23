# opencode-firecrawl

OpenCode plugin for [Firecrawl](https://firecrawl.dev) — gives your AI agent reliable web scraping, crawling, and search via the [Firecrawl CLI](https://github.com/firecrawl/cli).

## Installation (OpenCode V2)

This copy is ported to the OpenCode V2 plugin API (`Plugin.define` + `setup`,
see https://opencode.ai/v2/docs/build/plugins/ and the V1 migration guide).
It lives at `~/.config/opencode/plugins/opencode-firecrawl/` and is
auto-discovered — no `opencode.jsonc` change needed. Alternatively pin it
explicitly with the V2 `plugins` key:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "plugins": ["./plugins/opencode-firecrawl"]
}
```

Then install the Firecrawl CLI globally:

```bash
npm install -g firecrawl-cli
```

## Authentication

On first use, the agent will prompt you to authenticate. You can also set up in advance:

```bash
# Browser login (recommended)
firecrawl login --browser

# Or set an API key
export FIRECRAWL_API_KEY=fc-your-api-key
```

Get an API key at [firecrawl.dev](https://firecrawl.dev).

If `FIRECRAWL_API_KEY` is set in your environment, the plugin automatically passes it to shell commands.
If not, it falls back to devkit's Doppler (`developer-workstation/dev`, same
project/config resolution as `~/linux-devkit/scripts/install-opencode.sh`),
so no `firecrawl login` is needed on devkit machines. The key is never logged
or written to disk.

## What it does

This plugin registers the Firecrawl CLI skill with OpenCode. Once installed, the agent can:

- **Search** the web with optional scraping of results
- **Scrape** any webpage to clean markdown, HTML, or structured data
- **Map** all URLs on a website
- **Crawl** entire websites recursively
- **Agent** — AI-powered autonomous web data extraction

All output is written to a `.firecrawl/` directory to avoid flooding context.

## Links

- [Firecrawl CLI Documentation](https://docs.firecrawl.dev/cli)
- [Firecrawl CLI GitHub](https://github.com/firecrawl/cli)
- [OpenCode Plugin Docs (V2)](https://opencode.ai/v2/docs/build/plugins/)

## License

ISC
