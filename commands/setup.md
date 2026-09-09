---
description: Configure glm-review (Z.ai API key, endpoint, model) and verify it works
argument-hint: '[--ping]'
allowed-tools: Read, Bash(bash:*), Bash(git:*), AskUserQuestion
---

Help the user configure and verify glm-review.

Raw slash-command arguments:
`$ARGUMENTS`

Steps:

1. Run the doctor to see the current state:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/glm-companion.sh" doctor
```
   If it exits with `invalid line(s) in ...` or `could not load` the config
   file, show the message verbatim and explain that the file may only contain
   `KEY=VALUE` lines (values with spaces must be quoted).
   If it prints `CLI flags  : MISSING ...`, this Claude Code version is too old
   for the plugin: tell the user to update it (`claude update`) and re-run the
   doctor before going further.

2. If the API key is missing, explain the two options and let the user choose:
   - **Shell environment**: add `export GLM_REVIEW_API_KEY="..."` (or `ZAI_API_KEY`)
     to their shell profile.
   - **Config file** (recommended): store it in `~/.glm-review/config`.
     Never ask the user to paste the key into the chat, and do not tell them to
     run the command through this session (the `!` prefix included): anything
     run here lands in the session transcript on disk. Tell them to open a
     separate terminal window and run this there, substituting their key
     (a leading space keeps it out of most shell histories):
     ```
      mkdir -p ~/.glm-review && printf 'GLM_REVIEW_API_KEY=%s\n' 'PASTE_KEY_HERE' > ~/.glm-review/config && chmod 600 ~/.glm-review/config
     ```
   The key comes from https://z.ai/manage-apikey/apikey-list (GLM Coding Plan
   subscribers can use their coding-plan key). Environment variables take
   precedence over the config file; the doctor's `API key` line says where the
   active key comes from.

3. Mention the optional overrides they can add to the same config file:
   - `GLM_REVIEW_MODEL` (default `glm-5.3[1m]`, 1M context)
   - `GLM_REVIEW_FLASH_MODEL` (default `glm-5.3-flash[1m]`, used by the `--flash` flag)
   - `GLM_REVIEW_BASE_URL` (default `https://api.z.ai/api/anthropic`;
     mainland China: `https://open.bigmodel.cn/api/anthropic`)
   - `GLM_REVIEW_MAX_TURNS` (default `40`, must be a positive integer)
   Note: if the claude-glm wrapper kit is installed, its saved key
   (`~/.config/claude-glm/api_key`) is picked up automatically as a fallback —
   in that case no key configuration is needed at all.

4. Once a key is present (or if `$ARGUMENTS` contains `--ping`), verify the
   connection end-to-end. The ping uses the same isolated, read-only session
   as a real review and doubles as a sandbox check (it asks the reviewer to
   write a temporary file and verifies the permission layer denied it):
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/glm-companion.sh" doctor --ping
```

5. Report the result plainly. If the ping fails, show the error verbatim and
   suggest checking the key, the endpoint URL for their region, and whether
   their plan includes the configured model. If it prints `sandbox : FAILED`,
   tell the user not to use glm-review with this Claude Code version until it
   is updated and the ping passes.

Never print or echo the API key value; the doctor output already masks it.
