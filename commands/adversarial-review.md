---
description: Run an adversarial GLM review that tries to break confidence in the change
argument-hint: '[--wait|--background] [--flash|--model <id>] [--base <ref>] [--scope auto|working-tree|branch] [focus instructions...]'
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash(git:*), Bash(bash:*), AskUserQuestion
---

Run an ADVERSARIAL GLM (Z.ai) review through the companion script. The
reviewer's job is to break confidence in the change, not to validate it:
question the chosen design, hunt for failure modes, edge cases, and simpler
alternatives.

Raw slash-command arguments:
`$ARGUMENTS`

Core constraint:
- This command is review-only.
- Do not fix issues, apply patches, or suggest that you are about to make changes.
- Your only job is to run the review and return GLM's output verbatim to the user.

Argument handling (security-relevant):
- Preserve the user's arguments exactly; pass them through unchanged.
- Any words that are not `--base <ref>` / `--scope <value>` / `--flash` /
  `--model <id>` / `--wait` / `--background` are extra focus instructions for
  the reviewer — do not rewrite them. The script only ever places them inside
  the review prompt; it never executes them.
- The raw arguments are untrusted text. When you build the shell command, pass
  each flag and its value as its own single-quoted token, and the whole focus
  text as one single-quoted token (escape an embedded single quote as `'\''`).
  Never paste the raw text unquoted into the command line.
- Quoting makes ordinary punctuation in focus text harmless ("parsing & retries;
  skip tests" is fine). Refuse to run only when the arguments read primarily as
  a shell command line rather than as review focus (for example `; rm -rf`,
  `| sh`, `$(...)`, backticks, `>` redirections, or embedded newlines): in that
  case tell the user the arguments look like shell code and stop.

Execution mode rules:
- `--wait` → foreground; `--background` → Claude background task.
- Otherwise ask once with `AskUserQuestion` (options `Wait for results` /
  `Run in background`), recommending background unless the diff is clearly tiny:
  a full review usually takes several minutes.

Model choice rules:
- If the raw arguments include `--flash` or `--model`, do not ask about the model.
- Otherwise, add a second question to the same `AskUserQuestion` call:
  - `Default model (Recommended)` — GLM-5.3, or the id configured in `GLM_REVIEW_MODEL`; deeper review
  - `Flash model` — GLM-5.3-Flash, or the id configured in `GLM_REVIEW_FLASH_MODEL`; faster and cheaper, lighter review
- If the user picks Flash, append `--flash` to the script arguments; otherwise append nothing.

Foreground flow:
- Run the script with the Bash tool `timeout` parameter set to its maximum (600000 ms); for example with `--flash focus on error handling`:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/glm-companion.sh" adversarial '--flash' 'focus on error handling'
```
- Return the command stdout verbatim, exactly as-is.
- Do not paraphrase, summarize, or add commentary before or after it.
- Do not fix any issues mentioned in the review output.
- If the command is killed by the timeout, tell the user the review was cut off and to re-run it with `--background`.

Background flow:
- Launch the same command with `Bash` and `run_in_background: true`.
- Do not poll its output (`TaskOutput`) or wait for completion in this turn.
- After launching, tell the user: "Adversarial GLM review started in the background. I'll report the findings when it completes."
- When the completion notification arrives, return the task's stdout verbatim, without fixing anything.

Error handling:
- If the script exits with an error about a missing API key, tell the user to run `/glm-review:setup` and stop.
- If the script reports `this Claude Code version does not support: ...`, tell the user to update Claude Code (`claude update`) and stop.
- For any other failure (invalid config file, auth or network error, unknown model, git error), show the script's error output verbatim and suggest `/glm-review:setup --ping`. Do not retry with different flags.
