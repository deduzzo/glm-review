# glm-review

> **Use GLM (Z.ai) as a cross-provider second-opinion code reviewer inside Claude Code** — like [codex-plugin-cc](https://github.com/openai/codex-plugin-cc), but powered by GLM-5.3.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-plugin-blueviolet)](https://code.claude.com/docs/en/plugins)
[![Model](https://img.shields.io/badge/model-GLM--5.3%20%7C%20Flash-00b4ab)](https://z.ai)

---

## Table of contents

- [Why](#why)
- [Features](#features)
- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Commands](#commands)
- [Model selection](#model-selection)
- [Review scopes and flags](#review-scopes-and-flags)
- [Configuration](#configuration)
- [Output format](#output-format)
- [Safety and privacy](#safety-and-privacy)
- [Troubleshooting](#troubleshooting)
- [Development and testing](#development-and-testing)
- [Uninstall](#uninstall)
- [Credits and license](#credits-and-license)

## Why

AI models have a well-documented tendency to validate code that resembles their own output. When Claude reviews code Claude wrote, it often agrees with itself. A reviewer from a **different provider** doesn't share the same training history or blind spots:

> **Claude writes. GLM reviews.**

This plugin wires that cross-provider loop into Claude Code as slash commands, exactly like OpenAI's codex plugin does with Codex — but using Z.ai's GLM-5.3, the strongest open-weights coding model at a fraction of the cost.

## Features

- 🔍 **`/glm-review:review`** — independent second-opinion review of your uncommitted changes or branch
- ⚔️ **`/glm-review:adversarial-review`** — steerable review that actively tries to *break confidence* in the change
- ⚡ **Model choice per run** — GLM-5.3 (deeper) or GLM-5.3-Flash (faster/cheaper), interactively or via flags
- 🕵️ **Agentic review, not diff-glancing** — the reviewer explores your repository (reads files, follows call sites, checks `git log`/`blame`) before judging
- 🔒 **Read-only and isolated by construction** — the reviewer runs in a sandboxed headless session: no user/project settings, hooks, plugins, MCP servers or slash commands; a hard-capped toolset (Read/Glob/Grep + read-only git); anything else is denied
- 🧾 **Structured output** — severity-ranked findings (P0–P3) with `file:line` references and a final verdict
- 🪶 **Zero extra dependencies** — no additional CLI to install: if you have Claude Code and a Z.ai key, you have everything
- 🔑 **Zero-config with claude-glm** — automatically reuses the key saved by the `claude-glm` wrapper kit if present

## How it works

```
┌─────────────────────┐  /glm-review:review   ┌──────────────────────────────┐
│  Claude Code        │ ────────────────────► │  glm-companion.sh            │
│  (your session,     │                       │  · resolves scope & model    │
│   Claude models)    │                       │  · builds review prompt      │
└─────────────────────┘                       └──────────────┬───────────────┘
                                                             │ headless
                                                             ▼
                                              ┌──────────────────────────────┐
        https://api.z.ai/api/anthropic  ◄──── │  claude -p  (isolated, r/o)  │
        (Anthropic-compatible endpoint,       │  ANTHROPIC_BASE_URL → Z.ai   │
         GLM-5.3 / GLM-5.3-Flash)             │  tools: Read/Grep/Glob/git   │
                                              └──────────────┬───────────────┘
                                                             │ structured review
                                                             ▼
                                              findings P0–P3 + SHIP verdict,
                                              returned to your session verbatim
```

The trick: the GLM Coding Plan exposes an **Anthropic-compatible API**, so Claude Code itself can act as the harness for the GLM reviewer. The plugin launches a headless `claude -p` instance with the environment pointed at Z.ai, isolated from your Claude Code configuration (settings, hooks, plugins, MCP servers) and restricted to read-only tools, running in your repository. No separate CLI, no app server.

## Requirements

| Requirement | Notes |
|---|---|
| [Claude Code](https://claude.com/claude-code) | the `claude` binary on your `PATH`, recent enough to support the isolation flags the reviewer relies on (`--setting-sources`, `--strict-mcp-config`, `--permission-mode`, `--tools`, ...); tested with 2.1.266. `/glm-review:setup` runs a doctor that checks them and tells you to `claude update` if any is missing |
| Z.ai API key | [GLM Coding Plan](https://z.ai/subscribe) subscription or pay-as-you-go key from [z.ai](https://z.ai/manage-apikey/apikey-list) |
| `git` | reviews are resolved against local git state |
| macOS / Linux | the companion script is POSIX-friendly bash (works on macOS's bash 3.2) |

## Installation

```
/plugin marketplace add deduzzo/glm-review
/plugin install glm-review@glm-review
/reload-plugins
```

Then configure and verify:

```
/glm-review:setup
```

The same commands work from a terminal (`claude plugin marketplace add deduzzo/glm-review`, `claude plugin install glm-review@glm-review`).

<details>
<summary>Install from the Gitea mirror instead of GitHub</summary>

The marketplace source can be any git URL:

```
/plugin marketplace add https://dev.asp.messina.it/asp5_messina/glm-review.git
/plugin install glm-review@glm-review
/reload-plugins
```

</details>

<details>
<summary>Install from a local clone (development)</summary>

```bash
git clone https://github.com/deduzzo/glm-review.git
claude --plugin-dir ./glm-review
```

</details>

### On another machine or another Claude Code version

The plugin ships no binaries: the only moving part is the `claude` CLI itself, and the reviewer relies on a handful of its flags (see [Requirements](#requirements)). After installing on a new machine, or after updating Claude Code, run the doctor with a live ping:

```
/glm-review:setup --ping
```

and check its report:

| Line | Meaning |
|---|---|
| `CLI flags  : OK` | this Claude Code supports every flag the reviewer uses |
| `CLI flags  : MISSING ...` | Claude Code is too old — run `claude update` and try again; reviews refuse to start until this passes |
| `API key    : ... [from ...]` | which key is in use and where it comes from |
| `status     : OK` | GLM answered through the configured endpoint |
| `sandbox    : OK` | the isolated session refused to write a file — safe to use |
| `sandbox    : FAILED` | this Claude Code version let the reviewer write a file: do not use glm-review with it until an update fixes it |

The API key is per machine: set `GLM_REVIEW_API_KEY` in the environment or create `~/.glm-review/config` there (see [Configuration](#configuration)); if the claude-glm wrapper kit is installed on that machine, its key is reused automatically.

### Updating

```
/plugin marketplace update glm-review
/plugin update glm-review@glm-review
```

Restart Claude Code to apply the update, then re-run `/glm-review:setup --ping`.

## Quick start

```
# 1. write some code with Claude, then:
/glm-review:review

# answer two questions (wait/background + model) — or skip them:
/glm-review:review --wait --flash

# 2. want a harsher take?
/glm-review:adversarial-review focus on error handling and race conditions
```

## Commands

| Command | What it does |
|---|---|
| `/glm-review:review` | Standard second-opinion review of uncommitted changes or the current branch |
| `/glm-review:adversarial-review [focus...]` | Adversarial review that hunts for the strongest reasons the change should **not** ship; extra words become reviewer focus instructions |
| `/glm-review:setup` | Configure the API key / endpoint / models and verify the connection end-to-end |

### `/glm-review:review`

Reviews your local git state. With no arguments it auto-detects the scope (dirty working tree → working-tree review; clean tree → branch vs. base) and asks whether to wait or run in background, and which model to use.

```
/glm-review:review
/glm-review:review --base origin/develop
/glm-review:review --scope working-tree --wait
/glm-review:review --flash --background
```

The review is **review-only**: findings are reported verbatim and nothing is ever fixed automatically. Read the review, then decide what to act on.

Foreground runs (`--wait`) are bounded by the host Bash tool timeout (10 minutes). A full GLM-5.3 review of a non-trivial change can take that long, so prefer `--background` (or `--flash` for a quick pass).

### `/glm-review:adversarial-review`

Same mechanics, opposite stance: the reviewer's explicit job is to break confidence in the change — hidden assumptions, failure modes, edge cases, security issues, simpler designs that were ignored. Any free text becomes focus instructions:

```
/glm-review:adversarial-review
/glm-review:adversarial-review focus on concurrency and error handling
/glm-review:adversarial-review --flash would a simpler design work?
```

### `/glm-review:setup`

Runs the doctor (shows CLI version and flag support, key status — masked — and its source, endpoint, models), guides you through storing the key, and verifies the connection with a live ping. The ping doubles as a **sandbox check**: the reviewer is asked to write a temporary file through an allowlisted git command plus a shell redirection, and the doctor reports `sandbox : OK` only if the permission layer denied it and no file appeared — run it after every Claude Code update.

```
/glm-review:setup
/glm-review:setup --ping
```

You can also run the doctor directly from a shell:

```bash
bash ~/.claude/plugins/.../glm-review/scripts/glm-companion.sh doctor --ping
```

## Model selection

Every review can run on either model:

| Model | Default id | When |
|---|---|---|
| **GLM-5.3** | `glm-5.3[1m]` | default — deeper review, 1M context window |
| **GLM-5.3-Flash** | `glm-5.3-flash[1m]` | `--flash` — faster and cheaper, 1M context window |
| any other | via `--model <id>` | e.g. `--model glm-5.2` or plain `--model glm-5.3` (200k) |

With no model flag, the command asks which model to use (same dialog as the wait/background question): the default model or the flash one. Defaults are configurable via `GLM_REVIEW_MODEL` and `GLM_REVIEW_FLASH_MODEL`; the dialog always maps to whatever ids you configured.

## Review scopes and flags

Both review commands accept:

| Flag | Meaning |
|---|---|
| `--scope auto` | *(default)* working tree if dirty, otherwise branch vs. base |
| `--scope working-tree` | staged + unstaged + untracked files |
| `--scope branch` | everything on the current branch relative to the base ref |
| `--base <ref>` | base ref for branch review (default: auto-detected from `origin/HEAD`, falling back to `main`/`master`); ignored, with a note, when the scope resolves to working-tree |
| `--flash` / `--model <id>` | model selection (see above) |
| `--wait` / `--background` | skip the foreground/background question (handled by the slash command; the script accepts and ignores them) |

## Configuration

Set environment variables, or put `KEY=VALUE` lines in `~/.glm-review/config` (recommended, `chmod 600`). Environment variables take precedence over the file. Every non-blank, non-comment line must look like a `[export ]KEY=VALUE` assignment, otherwise the script aborts with `invalid line(s) in ...`; the file is then evaluated once by the shell (so quote values containing spaces, and keep it to plain assignments).

| Variable | Default | Notes |
|---|---|---|
| `GLM_REVIEW_API_KEY` | — | Z.ai API key (`ZAI_API_KEY` also honored) |
| `GLM_REVIEW_BASE_URL` | `https://api.z.ai/api/anthropic` | Mainland China: `https://open.bigmodel.cn/api/anthropic` |
| `GLM_REVIEW_MODEL` | `glm-5.3[1m]` | default review model (1M context) |
| `GLM_REVIEW_FLASH_MODEL` | `glm-5.3-flash[1m]` | model used by `--flash` (1M context) |
| `GLM_REVIEW_MAX_TURNS` | `40` | upper bound on the reviewer's agentic turns (positive integer) |
| `GLM_REVIEW_CONFIG` | `~/.glm-review/config` | alternate config file location |

**API key resolution order:**

1. `GLM_REVIEW_API_KEY` environment variable
2. `ZAI_API_KEY` environment variable
3. `GLM_REVIEW_API_KEY` in `~/.glm-review/config`
4. `ZAI_API_KEY` in `~/.glm-review/config`
5. `~/.config/claude-glm/api_key` — the key saved by the [claude-glm wrapper kit](https://github.com/deduzzo), picked up automatically as a fallback (zero-config if you already use `claude-glm`)

The doctor's `API key` line reports which of these sources is in use.

## Output format

Every review returns:

1. **Summary** — one paragraph on what the change does
2. **Findings**, ranked by severity, each with `file:line`, the issue, why it matters, a concrete failure scenario, and a suggested direction (no patches):
   - `P0` blocker · `P1` major · `P2` minor · `P3` nit
3. **Verdict** — `SHIP` / `SHIP WITH FIXES` / `DO NOT SHIP`, with one sentence why

Reviewers are explicitly instructed to say *"no significant issues"* rather than invent nits, and to only report findings they verified in the code.

## Safety and privacy

- The GLM reviewer runs in an **isolated headless session**: `--setting-sources ""` (no user or project settings, hence no hooks, plugins, permission rules or CLAUDE.md-driven surprises from the repository under review), `--strict-mcp-config` (no MCP servers), `--disable-slash-commands`, and `--no-session-persistence` (the reviewer transcript is not saved to disk and cannot be resumed).
- It is **read-only by construction**: `--tools Read,Glob,Grep,Bash` hard-caps the built-in toolset, the allowlist pre-approves only `git diff/log/show/status/ls-files/blame`, `--permission-mode dontAsk` denies anything else that would need approval, and `Write`/`Edit`/`NotebookEdit`/`WebFetch`/`WebSearch`/`Task`/`Agent` are disallowed on top — as are the write-capable or tool-spawning forms of the allowed git commands (`--output=<file>`, `--ext-diff`, `git difftool`), since deny rules beat allow rules. The prompt-level "never modify state" instruction is the last line of defense, not the first.
- Shell redirections to files (`>`, `>>`, `2>`) on the allowed git commands are denied by Claude Code's permission layer under `dontAsk` (verified; `/dev/null` is the only exception), and `doctor --ping` re-checks this on your installation.
- Residual risk, by design: `git diff` honors diff drivers/textconv from *your own* git config (`diff.external`, `diff.<driver>.command`); a repository cannot set those through committed content.
- The review prompt travels on stdin, not argv, so file names and focus text never show up in the process list.
- The review commands are review-only: they never apply fixes.
- Slash-command arguments are untrusted text: the command instructions require quoting every argument as its own token and refusing input that looks like shell code before invoking the script.
- Your **code is sent to Z.ai** for review (that's the point) — don't use this plugin on repositories whose policy forbids third-party AI processing.
- Your API key is never printed; diagnostics mask it (`sk-x…y4z (35 chars)`).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `no API key found` | run `/glm-review:setup`, or export `GLM_REVIEW_API_KEY` |
| ping fails with auth error | wrong/expired key — regenerate at [z.ai](https://z.ai/manage-apikey/apikey-list) |
| ping fails with model error | your plan may use different ids — try `GLM_REVIEW_MODEL='glm-5.3'` (without the `[1m]` suffix) |
| slow / truncated from mainland China | set `GLM_REVIEW_BASE_URL=https://open.bigmodel.cn/api/anthropic` |
| `could not detect a base branch` | pass `--base origin/<branch>` explicitly |
| `working tree is clean — nothing to review` | commit state is clean; use `--scope branch` or make changes |
| `git diff <base>...HEAD failed: ... no merge base` | the base has no common ancestor with `HEAD` — pass the right `--base` |
| `invalid line(s) in ~/.glm-review/config` / `could not load it` | the file may only contain `KEY=VALUE` lines; quote values containing spaces |
| `GLM_REVIEW_MAX_TURNS must be a positive integer` | fix the value in your environment or config file |
| `CLI flags  : MISSING ...` in the doctor / `this Claude Code version does not support: ...` | your Claude Code is too old for the reviewer's isolation flags — run `claude update` |
| `sandbox    : FAILED` in `doctor --ping` | this Claude Code version let the reviewer write a file: do not use glm-review with it; update Claude Code and re-run the ping |
| `config file ... is not readable` | fix the file's permissions/ownership (it should be `chmod 600`, owned by you) |
| review stops early | raise `GLM_REVIEW_MAX_TURNS` (large diffs need more agentic turns) |
| `isn't described by this version's model catalog` warning | harmless — Claude Code doesn't know GLM ids; the `[1m]` suffix in the default ids already unlocks the 1M context window |
| foreground review times out | use `--background` (foreground runs already use the maximum 10-minute Bash tool timeout) |

## Development and testing

```bash
git clone https://github.com/deduzzo/glm-review.git && cd glm-review

# validate the plugin manifest
claude plugin validate .

# syntax-check the companion script
bash -n scripts/glm-companion.sh

# regression tests (stub `claude`, no API calls, bash 3.2 compatible)
bash tests/companion-test.sh

# dry-run the flow without calling the API: put a stub `claude` first in PATH
# that echoes its args, then:
GLM_REVIEW_API_KEY=fake bash scripts/glm-companion.sh review --scope working-tree

# live end-to-end check (uses your real key, one tiny request): connectivity + sandbox
bash scripts/glm-companion.sh doctor --ping
```

Repository layout:

```
glm-review/
├── .claude-plugin/
│   ├── plugin.json          # plugin manifest
│   └── marketplace.json     # this repo doubles as its own marketplace
├── commands/
│   ├── review.md            # /glm-review:review
│   ├── adversarial-review.md
│   └── setup.md
├── scripts/
│   └── glm-companion.sh     # config, scope resolution, prompt building, isolated headless launch
├── tests/
│   └── companion-test.sh    # stub-based regression tests for the script
└── README.md
```

Contributions welcome — open an issue or PR.

## Uninstall

```
/plugin uninstall glm-review@glm-review
/plugin marketplace remove glm-review
```

Optionally remove `~/.glm-review/`.

## Credits and license

- Command UX modeled on OpenAI's [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) (review / adversarial-review, `--wait`/`--background`, verbatim output). The backend differs: glm-review reuses Claude Code itself in headless mode against Z.ai's Anthropic-compatible API instead of wrapping a separate CLI.
- GLM models by [Z.ai (Zhipu AI)](https://z.ai).

[MIT](LICENSE) © 2026 Roberto De Domenico
