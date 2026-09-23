// NOTE: type-only import on purpose. The compiled opencode binary cannot
// resolve the `@opencode/plugin` package from this directory at runtime
// (Bun ResolveMessage), so the plugin must have zero runtime dependencies
// beyond node builtins. `Plugin.define` is an identity helper anyway.
import type { Plugin, Skill } from "@opencode/plugin";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const current_dir = dirname(fileURLToPath(import.meta.url));
const skillDir = join(current_dir, "skills", "firecrawl-cli");
const skillPath = join(skillDir, "SKILL.md");
const installPath = join(skillDir, "rules", "install.md");

function loadText(path: string): string {
  try {
    return readFileSync(path, "utf8");
  } catch {
    return "";
  }
}

// Resolve the Firecrawl key the same way devkit does: env first, then Doppler
// (developer-workstation/dev by default, same project/config resolution as
// ~/linux-devkit/scripts/install-opencode.sh). Needed because the opencode
// server is often spawned from a shell without Doppler env, so process.env
// alone is empty. The value is never logged or written to disk.
function resolveFirecrawlKey(): string | undefined {
  const fromEnv = process.env.FIRECRAWL_API_KEY?.trim();
  if (fromEnv) return fromEnv;
  try {
    const project =
      process.env.DEVKIT_OPENCODE_DOPPLER_PROJECT ??
      process.env.DEVKIT_CODEX_DOPPLER_PROJECT ??
      process.env.DOPPLER_PROJECT ??
      "developer-workstation";
    const config =
      process.env.DEVKIT_OPENCODE_DOPPLER_CONFIG ??
      process.env.DEVKIT_CODEX_DOPPLER_CONFIG ??
      process.env.DOPPLER_CONFIG ??
      "dev";
    const out = execFileSync(
      "doppler",
      [
        "secrets",
        "get",
        "FIRECRAWL_API_KEY",
        `--project=${project}`,
        `--config=${config}`,
        "--plain",
      ],
      { encoding: "utf8", timeout: 15_000, stdio: ["ignore", "pipe", "ignore"] },
    ).trim();
    return out || undefined;
  } catch {
    return undefined;
  }
}

const plugin: Parameters<typeof Plugin.define>[0] = {
  id: "opencode-firecrawl",
  async setup(ctx) {
    // Load external data BEFORE registering transforms (transforms must be sync + replayable).
    const skillContent = loadText(skillPath);
    const installContent = loadText(installPath);

    // V1 `config.skills.paths` -> V2 skill transform.
    if (skillContent) {
      await ctx.skill.transform((editor) => {
        editor.add({
          id: "firecrawl" as Skill.Info["id"],
          name: "firecrawl" as Skill.Info["name"],
          description:
            "Firecrawl CLI for web search, scraping, mapping, and crawling. Use instead of WebFetch/WebSearch. See skill content for syntax, rules/install.md for auth.",
          path: skillPath as Skill.Info["path"],
          content: skillContent,
        });
      });
    }

    // V1 `config.instructions` (install.md) -> append to every agent's system prompt.
    // Replayed onto a fresh registry on every reload, so no duplication risk.
    if (installContent) {
      const instruction = `# Firecrawl CLI setup (from opencode-firecrawl plugin)\n\n${installContent}`;
      await ctx.agent.transform((editor) => {
        for (const agent of editor.list()) {
          editor.update(agent.id as unknown as string, (draft) => {
            draft.system = draft.system ? `${draft.system}\n\n${instruction}` : instruction;
          });
        }
      });
    }

    // V1 `shell.env` -> V2 shell hook. Key resolves via env first, then
    // Doppler (devkit), so `firecrawl` CLI calls work even when the server
    // was started from a shell without Doppler env.
    const firecrawlKey = resolveFirecrawlKey();
    await ctx.shell.hook("create.before", (event) => {
      if (firecrawlKey) {
        event.env.FIRECRAWL_API_KEY = firecrawlKey;
      }
    });
  },
};

export default plugin;
