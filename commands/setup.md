---
description: Configure glm-review (Z.ai API key, endpoint, model) and verify it works
argument-hint: '[--ping]'
allowed-tools: Read, Bash(bash:*), Bash(mkdir:*), Bash(chmod:*), Bash(git:*), AskUserQuestion
---

Help the user configure and verify glm-review.

Raw slash-command arguments:
`$ARGUMENTS`

Steps:

1. Run the doctor to see the current state:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/glm-companion.sh" doctor
```

2. If the API key is missing, explain the two options and let the user choose:
   - **Shell environment**: add `export GLM_REVIEW_API_KEY="..."` (or `ZAI_API_KEY`)
     to their shell profile.
   - **Config file** (recommended): store it in `~/.glm-review/config`.
     Never ask the user to paste the key into the chat. Instead, tell them to run
     this themselves (the `!` prefix runs it in this session), substituting their key:
     ```
     ! mkdir -p ~/.glm-review && printf 'GLM_REVIEW_API_KEY=%s\n' 'PASTE_KEY_HERE' > ~/.glm-review/config && chmod 600 ~/.glm-review/config
     ```
   The key comes from https://z.ai/manage-apikey/apikey-list (GLM Coding Plan
   subscribers can use their coding-plan key).

3. Mention the optional overrides they can add to the same config file:
   - `GLM_REVIEW_MODEL` (default `glm-5.3`)
   - `GLM_REVIEW_FLASH_MODEL` (default `glm-5.3-flash`, used by the `--flash` flag)
   - `GLM_REVIEW_BASE_URL` (default `https://api.z.ai/api/anthropic`;
     mainland China: `https://open.bigmodel.cn/api/anthropic`)
   - `GLM_REVIEW_MAX_TURNS` (default `40`)
   Note: if the claude-glm wrapper kit is installed, its saved key
   (`~/.config/claude-glm/api_key`) is picked up automatically as a fallback —
   in that case no key configuration is needed at all.

4. Once a key is present (or if `$ARGUMENTS` contains `--ping`), verify the
   connection end-to-end:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/glm-companion.sh" doctor --ping
```

5. Report the result plainly. If the ping fails, show the error verbatim and
   suggest checking the key, the endpoint URL for their region, and whether
   their plan includes the configured model.

Never print or echo the API key value; the doctor output already masks it.
