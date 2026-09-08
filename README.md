# glm-review

**Use GLM (Z.ai) as a cross-provider second-opinion code reviewer inside Claude Code** — like [codex-plugin-cc](https://github.com/openai/codex-plugin-cc), but powered by GLM-5.3.

AI models tend to validate code that resembles their own output. A reviewer from a *different* provider doesn't share the same blind spots: Claude writes, GLM reviews. This plugin wires that loop into Claude Code as slash commands.

## How it works

The plugin launches a **headless Claude Code instance pointed at the Anthropic-compatible endpoint of the GLM Coding Plan** (`https://api.z.ai/api/anthropic`). The GLM reviewer runs in your repository with **read-only tools** (Read, Grep, Glob, `git diff/log/show/blame`), investigates the change agentically, and returns a structured review — severity-ranked findings with `file:line` references and a final SHIP / SHIP WITH FIXES / DO NOT SHIP verdict.

No extra CLI to install: if you have Claude Code and a Z.ai API key, you have everything.

## Requirements

- [Claude Code](https://claude.com/claude-code) (the `claude` binary on your PATH)
- A [Z.ai API key](https://z.ai/manage-apikey/apikey-list) — a [GLM Coding Plan](https://z.ai/subscribe) subscription or pay-as-you-go API access
- `git`

## Installation

```
/plugin marketplace add deduzzo/glm-review
/plugin install glm-review@glm-review
```

Then configure your API key:

```
/glm-review:setup
```

## Commands

| Command | What it does |
|---|---|
| `/glm-review:review` | Standard second-opinion review of uncommitted changes or the current branch |
| `/glm-review:adversarial-review [focus...]` | Steerable review that tries to *break confidence* in the change; extra words become reviewer focus instructions |
| `/glm-review:setup` | Configure the API key / endpoint / model and verify the connection |

### Examples

```
/glm-review:review
/glm-review:review --base origin/develop
/glm-review:review --flash --wait
/glm-review:review --scope working-tree --model "glm-5.3[1m]"
/glm-review:adversarial-review focus on concurrency and error handling
```

**Flags** (both review commands):

- `--flash` — use the Flash model (faster/cheaper); `--model <id>` — use any specific model id
- `--base <ref>` — base ref for branch review (default: auto-detected default branch)
- `--scope auto|working-tree|branch` — what to review (default `auto`: working tree if dirty, otherwise branch vs base)
- `--wait` / `--background` — skip the foreground/background question

With no model flag, the command asks whether to review with **GLM-5.3** (deeper) or **GLM-5.3-Flash** (faster/cheaper).

## Configuration

Environment variables, or `KEY=VALUE` lines in `~/.glm-review/config` (chmod 600):

| Variable | Default | Notes |
|---|---|---|
| `GLM_REVIEW_API_KEY` | — | Z.ai API key (`ZAI_API_KEY` also honored) |
| `GLM_REVIEW_BASE_URL` | `https://api.z.ai/api/anthropic` | Mainland China: `https://open.bigmodel.cn/api/anthropic` |
| `GLM_REVIEW_MODEL` | `glm-5.3` | Any model your plan exposes (e.g. `glm-5.3[1m]`) |
| `GLM_REVIEW_FLASH_MODEL` | `glm-5.3-flash` | Model used by the `--flash` flag |
| `GLM_REVIEW_MAX_TURNS` | `40` | Upper bound on the reviewer's agentic turns |
| `GLM_REVIEW_CONFIG` | `~/.glm-review/config` | Alternate config file location |

If no key is configured, glm-review also falls back to the key saved by the
[claude-glm wrapper kit](https://github.com/deduzzo) at `~/.config/claude-glm/api_key`, if present.

## Safety

- The GLM reviewer is **read-only**: it runs with an explicit tool allowlist (no Write/Edit, no network tools, no subagents) and is instructed never to modify state.
- The review commands themselves are review-only: they report findings verbatim and never apply fixes.
- Your API key is never printed; diagnostics mask it.

## Relationship to codex-plugin-cc

The command UX (review / adversarial-review, `--wait`/`--background`, verbatim output) is modeled on OpenAI's [codex-plugin-cc](https://github.com/openai/codex-plugin-cc). The backend is different: instead of wrapping a separate CLI's app server, glm-review reuses Claude Code itself in headless mode against Z.ai's Anthropic-compatible API.

## License

[MIT](LICENSE)
