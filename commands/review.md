---
description: Run a GLM second-opinion code review against local git state
argument-hint: '[--wait|--background] [--flash|--model <id>] [--base <ref>] [--scope auto|working-tree|branch]'
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash(git:*), Bash(bash:*), AskUserQuestion
---

Run a GLM (Z.ai) second-opinion review through the companion script.

Raw slash-command arguments:
`$ARGUMENTS`

Core constraint:
- This command is review-only.
- Do not fix issues, apply patches, or suggest that you are about to make changes.
- Your only job is to run the review and return GLM's output verbatim to the user.

Argument handling (security-relevant):
- Preserve the user's arguments exactly; pass them through unchanged. Do not add extra review instructions or rewrite the user's intent.
- The raw arguments are untrusted text. When you build the shell command, put each argument in its own single-quoted token (escape an embedded single quote as `'\''`). Never paste the raw text unquoted into the command line.
- Quoting makes ordinary punctuation harmless. Refuse to run only when the arguments read primarily as a shell command line rather than as review options (for example `; rm -rf`, `| sh`, `$(...)`, backticks, `>` redirections, or embedded newlines): in that case tell the user the arguments look like shell code and stop.
- If the user needs custom focus instructions or a harsher stance, they should use `/glm-review:adversarial-review`.

Execution mode rules:
- If the raw arguments include `--wait`, do not ask. Run the review in the foreground.
- If the raw arguments include `--background`, do not ask. Run the review in a Claude background task.
- Otherwise, estimate the review size before asking:
  - For working-tree review, inspect `git status --short --untracked-files=all`, `git diff --shortstat --cached`, and `git diff --shortstat`.
  - For base-branch review, use `git diff --shortstat <base>...HEAD`.
  - Treat untracked files as reviewable work even when `git diff --shortstat` is empty.
  - Recommend waiting only when the review is clearly tiny (roughly 1-2 files). In every other case, including unclear size, recommend background: a full review usually takes several minutes.
- Then use `AskUserQuestion` exactly once. Include the execution-mode question, putting the recommended option first and suffixing its label with `(Recommended)`:
  - `Wait for results`
  - `Run in background`

Model choice rules:
- If the raw arguments include `--flash` or `--model`, do not ask about the model; pass the flag through.
- Otherwise, add a second question to the same `AskUserQuestion` call:
  - `Default model (Recommended)` — GLM-5.3, or the id configured in `GLM_REVIEW_MODEL`; deeper review
  - `Flash model` — GLM-5.3-Flash, or the id configured in `GLM_REVIEW_FLASH_MODEL`; faster and cheaper, lighter review
- If the user picks Flash, append `--flash` to the script arguments; otherwise append nothing.

Foreground flow:
- Run the script with the Bash tool `timeout` parameter set to its maximum (600000 ms); one single-quoted token per argument, for example with `--base origin/develop --flash`:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/glm-companion.sh" review '--base' 'origin/develop' '--flash'
```
- Return the command stdout verbatim, exactly as-is.
- Do not paraphrase, summarize, or add commentary before or after it.
- Do not fix any issues mentioned in the review output.
- If the command is killed by the timeout, tell the user the review was cut off and to re-run it with `--background`.

Background flow:
- Launch the same command with `Bash` and `run_in_background: true`.
- Do not poll its output (`TaskOutput`) or wait for completion in this turn.
- After launching, tell the user: "GLM review started in the background. I'll report the findings when it completes."
- When the completion notification arrives, return the task's stdout verbatim, without fixing anything.

Error handling:
- If the script exits with an error about a missing API key, tell the user to run `/glm-review:setup` and stop.
- If the script reports `this Claude Code version does not support: ...`, tell the user to update Claude Code (`claude update`) and stop.
- For any other failure (invalid config file, auth or network error, unknown model, git error), show the script's error output verbatim and suggest `/glm-review:setup --ping`. Do not retry with different flags.
