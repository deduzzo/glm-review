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

Execution mode rules:
- If the raw arguments include `--wait`, do not ask. Run the review in the foreground.
- If the raw arguments include `--background`, do not ask. Run the review in a Claude background task.
- Otherwise, estimate the review size before asking:
  - For working-tree review, inspect `git status --short --untracked-files=all`, `git diff --shortstat --cached`, and `git diff --shortstat`.
  - For base-branch review, use `git diff --shortstat <base>...HEAD`.
  - Treat untracked files as reviewable work even when `git diff --shortstat` is empty.
  - Recommend waiting only when the review is clearly tiny (roughly 1-2 files). In every other case, including unclear size, recommend background.
- Then use `AskUserQuestion` exactly once. Include the execution-mode question, putting the recommended option first and suffixing its label with `(Recommended)`:
  - `Wait for results`
  - `Run in background`

Model choice rules:
- If the raw arguments include `--flash` or `--model`, do not ask about the model; pass the flag through.
- Otherwise, add a second question to the same `AskUserQuestion` call:
  - `GLM-5.3 (Recommended)` — full model, deeper review
  - `GLM-5.3-Flash` — faster and cheaper, lighter review
- If the user picks Flash, append `--flash` to the script arguments; otherwise append nothing.

Argument handling:
- Preserve the user's arguments exactly; pass them through unchanged.
- Do not add extra review instructions or rewrite the user's intent.
- If the user needs custom focus instructions or a harsher stance, they should use `/glm-review:adversarial-review`.

Foreground flow:
- Run:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/glm-companion.sh" review $ARGUMENTS
```
- Return the command stdout verbatim, exactly as-is.
- Do not paraphrase, summarize, or add commentary before or after it.
- Do not fix any issues mentioned in the review output.

Background flow:
- Launch the same command with `Bash` and `run_in_background: true`.
- Do not call `BashOutput` or wait for completion in this turn.
- After launching, tell the user: "GLM review started in the background. I'll report the findings when it completes."

Error handling:
- If the script exits with an error about a missing API key, tell the user to run `/glm-review:setup` and stop.
