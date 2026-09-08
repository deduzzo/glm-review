---
description: Run an adversarial GLM review that tries to break confidence in the change
argument-hint: '[--flash|--model <id>] [--base <ref>] [--scope auto|working-tree|branch] [focus instructions...]'
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

Argument handling:
- Preserve the user's arguments exactly; pass them through unchanged.
- Any words that are not `--base <ref>` / `--scope <value>` / `--flash` /
  `--model <id>` / `--wait` / `--background` are treated as extra focus
  instructions for the reviewer — do not rewrite them.

Execution mode rules:
- `--wait` → foreground; `--background` → Claude background task.
- Otherwise ask once with `AskUserQuestion` (options `Wait for results` /
  `Run in background`), recommending background unless the diff is clearly tiny.

Model choice rules:
- If the raw arguments include `--flash` or `--model`, do not ask about the model.
- Otherwise, add a second question to the same `AskUserQuestion` call:
  - `GLM-5.3 (Recommended)` — full model, deeper review
  - `GLM-5.3-Flash` — faster and cheaper, lighter review
- If the user picks Flash, append `--flash` to the script arguments; otherwise append nothing.

Foreground flow:
- Run:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/glm-companion.sh" adversarial $ARGUMENTS
```
- Return the command stdout verbatim, exactly as-is.
- Do not paraphrase, summarize, or add commentary before or after it.
- Do not fix any issues mentioned in the review output.

Background flow:
- Launch the same command with `Bash` and `run_in_background: true`.
- Do not call `BashOutput` or wait for completion in this turn.
- After launching, tell the user: "Adversarial GLM review started in the background. I'll report the findings when it completes."

Error handling:
- If the script exits with an error about a missing API key, tell the user to run `/glm-review:setup` and stop.
