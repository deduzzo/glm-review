#!/usr/bin/env bash
# glm-review companion script.
#
# Runs GLM (Z.ai) as an independent second-opinion code reviewer by launching
# a headless `claude -p` instance pointed at the Anthropic-compatible endpoint
# of the GLM Coding Plan, isolated from user/project settings and restricted
# to read-only tools.
#
# Usage:
#   glm-companion.sh review      [--flash|--model <id>] [--base <ref>] [--scope auto|working-tree|branch]
#   glm-companion.sh adversarial [--flash|--model <id>] [--base <ref>] [--scope auto|working-tree|branch] [focus text...]
#   glm-companion.sh doctor      [--ping] [--flash|--model <id>]
#
#   --wait / --background are accepted by review and adversarial but ignored:
#   they are handled by the slash-command layer.
#
# Configuration (env vars, or KEY=VALUE lines in ~/.glm-review/config;
# the environment takes precedence over the file):
#   GLM_REVIEW_API_KEY      Z.ai API key (ZAI_API_KEY is also honored)
#   GLM_REVIEW_BASE_URL     default: https://api.z.ai/api/anthropic
#   GLM_REVIEW_MODEL        default: glm-5.3[1m] (1M context)
#   GLM_REVIEW_FLASH_MODEL  default: glm-5.3-flash[1m] (used by --flash)
#   GLM_REVIEW_MAX_TURNS    default: 40
#   GLM_REVIEW_CONFIG       default: ~/.glm-review/config

set -euo pipefail

err() { printf 'glm-review: %s\n' "$*" >&2; }

CONFIG_FILE="${GLM_REVIEW_CONFIG:-$HOME/.glm-review/config}"
CONFIG_VARS="GLM_REVIEW_API_KEY ZAI_API_KEY GLM_REVIEW_BASE_URL GLM_REVIEW_MODEL GLM_REVIEW_FLASH_MODEL GLM_REVIEW_MAX_TURNS"
CLAUDE_GLM_KEY_FILE="$HOME/.config/claude-glm/api_key"

# Snapshot the environment before reading the config file: env values win.
for v in $CONFIG_VARS; do
  eval "env_$v=\"\${$v:-}\""
  eval "file_$v=''"
done

load_config() {
  [ -f "$CONFIG_FILE" ] || return 0
  if [ ! -r "$CONFIG_FILE" ]; then
    err "config file $CONFIG_FILE is not readable (check its permissions/ownership)."
    exit 2
  fi
  # Accept only blank lines, comments and [export] KEY=VALUE assignments.
  line_re='^[[:space:]]*(#|$)|^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*='
  if grep -Ev "$line_re" "$CONFIG_FILE" >/dev/null; then
    err "invalid line(s) in $CONFIG_FILE (expected KEY=VALUE):"
    grep -Env "$line_re" "$CONFIG_FILE" >&2
    exit 2
  fi
  # Evaluate the file exactly once, in a subshell with errexit, and pull the
  # known keys out as KEY=VALUE lines. A broken value (e.g. unquoted spaces)
  # makes the subshell fail instead of silently dropping the setting.
  set +e
  cfg_out="$(
    set -e
    # shellcheck disable=SC1090
    . "$CONFIG_FILE" >/dev/null 2>&1
    for v in $CONFIG_VARS; do eval "printf '%s=%s\n' \"$v\" \"\${$v:-}\""; done
  )"
  cfg_rc=$?
  set -e
  if [ "$cfg_rc" -ne 0 ]; then
    err "invalid config file $CONFIG_FILE: could not load it (quote values containing spaces)."
    exit 2
  fi
  while IFS= read -r line; do
    k="${line%%=*}"
    eval "file_$k=\"\${line#*=}\""
  done <<EOT
$cfg_out
EOT
}
load_config

# Effective settings: environment, then config file, then defaults.
for v in GLM_REVIEW_BASE_URL GLM_REVIEW_MODEL GLM_REVIEW_FLASH_MODEL GLM_REVIEW_MAX_TURNS; do
  eval "$v=\"\${env_$v:-\$file_$v}\""
done
BASE_URL="${GLM_REVIEW_BASE_URL:-https://api.z.ai/api/anthropic}"
MODEL="${GLM_REVIEW_MODEL:-glm-5.3[1m]}"
FLASH_MODEL="${GLM_REVIEW_FLASH_MODEL:-glm-5.3-flash[1m]}"
MAX_TURNS="${GLM_REVIEW_MAX_TURNS:-40}"

case "$MAX_TURNS" in
  ''|*[!0-9]*|0)
    err "GLM_REVIEW_MAX_TURNS must be a positive integer (got '$MAX_TURNS')."
    exit 2
    ;;
esac

# API key resolution order: environment (GLM_REVIEW_API_KEY, then ZAI_API_KEY),
# config file (same order), then the key saved by the claude-glm wrapper kit.
API_KEY=""
API_KEY_SOURCE=""
if [ -n "$env_GLM_REVIEW_API_KEY" ]; then
  API_KEY="$env_GLM_REVIEW_API_KEY"; API_KEY_SOURCE="environment: GLM_REVIEW_API_KEY"
elif [ -n "$env_ZAI_API_KEY" ]; then
  API_KEY="$env_ZAI_API_KEY"; API_KEY_SOURCE="environment: ZAI_API_KEY"
elif [ -n "$file_GLM_REVIEW_API_KEY" ]; then
  API_KEY="$file_GLM_REVIEW_API_KEY"; API_KEY_SOURCE="$CONFIG_FILE: GLM_REVIEW_API_KEY"
elif [ -n "$file_ZAI_API_KEY" ]; then
  API_KEY="$file_ZAI_API_KEY"; API_KEY_SOURCE="$CONFIG_FILE: ZAI_API_KEY"
elif [ -f "$CLAUDE_GLM_KEY_FILE" ]; then
  API_KEY="$(head -1 "$CLAUDE_GLM_KEY_FILE" | tr -d '[:space:]')"
  [ -z "$API_KEY" ] || API_KEY_SOURCE="$CLAUDE_GLM_KEY_FILE"
fi

# Flags the launcher relies on; older Claude Code versions lack some of them.
# (--max-turns is hidden from --help, so it is not checked here.)
REQUIRED_CLI_FLAGS="--print --model --setting-sources --strict-mcp-config --disable-slash-commands --no-session-persistence --permission-mode --tools --allowedTools --disallowedTools"

usage() {
  # Print the comment header: line 2 up to the first blank line.
  sed -n '2,/^$/p' "$0" | sed -e '/^$/d' -e 's/^# \{0,1\}//'
}

mask_key() {
  k="$1"
  if [ -z "$k" ]; then
    echo "(not set)"
  elif [ "${#k}" -le 8 ]; then
    echo "(set, ${#k} chars)"
  else
    printf '%s…%s (%d chars)\n' "${k:0:4}" "${k:${#k}-4:4}" "${#k}"
  fi
}

require_key() {
  if [ -z "$API_KEY" ]; then
    err "no API key found."
    err "Set GLM_REVIEW_API_KEY (or ZAI_API_KEY) in your environment,"
    err "or put GLM_REVIEW_API_KEY=... in $CONFIG_FILE (chmod 600)."
    err "Run /glm-review:setup for guided configuration."
    exit 2
  fi
}

missing_cli_flags() {
  # $1 = `claude --help` output. Prints the required flags it does not mention.
  missing=""
  for f in $REQUIRED_CLI_FLAGS; do
    case "$1" in
      *"$f"*) ;;
      *) missing="${missing:+$missing }$f" ;;
    esac
  done
  printf '%s' "$missing"
}

require_cli() {
  if ! command -v claude >/dev/null 2>&1; then
    err "claude CLI not found on PATH; glm-review needs Claude Code installed."
    exit 2
  fi
  help_text="$(claude --help 2>&1 || true)"
  if [ -z "$help_text" ]; then
    err "could not read 'claude --help' output; the claude CLI looks broken."
    exit 2
  fi
  missing="$(missing_cli_flags "$help_text")"
  if [ -n "$missing" ]; then
    err "this Claude Code version does not support: $missing"
    err "glm-review needs a newer Claude Code (tested with 2.1.266); run 'claude update'."
    exit 2
  fi
}

require_repo() {
  if ! git_out="$(git rev-parse --is-inside-work-tree 2>&1)"; then
    err "not inside a usable git repository: $git_out"
    exit 2
  fi
}

require_model() {
  if [ -z "$MODEL" ]; then
    err "model id is empty."
    exit 2
  fi
}

detect_base() {
  # Prefer the remote default branch, fall back to main/master.
  ref="$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [ -n "$ref" ]; then
    echo "${ref#refs/remotes/}"
    return
  fi
  for cand in origin/main origin/master main master; do
    if git rev-parse --verify --quiet "$cand" >/dev/null 2>&1; then
      echo "$cand"
      return
    fi
  done
  echo ""
}

# Launch a headless `claude -p` on the GLM endpoint, reading the prompt from
# stdin (keeps it out of argv). $1 = max turns.
#
# The session is isolated from the user's and the repository's Claude Code
# configuration (settings, hooks, plugins, MCP servers, slash commands) and
# capped to read-only tools: `--tools` limits the built-in toolset,
# `--allowedTools` pre-approves the read-only git subcommands, `dontAsk`
# denies anything else that would need a permission prompt, and the
# write-capable / tool-spawning forms of those git subcommands (`--output`,
# `--ext-diff`, `difftool`) are denied explicitly (deny beats allow).
launch_claude() {
  env -u ANTHROPIC_API_KEY -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT \
      -u CLAUDE_CODE_USE_BEDROCK -u CLAUDE_CODE_USE_VERTEX -u CLAUDE_CODE_USE_FOUNDRY \
    ANTHROPIC_BASE_URL="$BASE_URL" \
    ANTHROPIC_AUTH_TOKEN="$API_KEY" \
    ANTHROPIC_MODEL="$MODEL" \
    ANTHROPIC_DEFAULT_OPUS_MODEL="$MODEL" \
    ANTHROPIC_DEFAULT_SONNET_MODEL="$MODEL" \
    ANTHROPIC_DEFAULT_HAIKU_MODEL="$MODEL" \
    ANTHROPIC_SMALL_FAST_MODEL="$MODEL" \
    claude -p \
      --model "$MODEL" \
      --max-turns "$1" \
      --setting-sources "" \
      --strict-mcp-config \
      --disable-slash-commands \
      --no-session-persistence \
      --permission-mode dontAsk \
      --tools "Read,Glob,Grep,Bash" \
      --allowedTools \
        "Read" "Glob" "Grep" \
        "Bash(git diff:*)" "Bash(git log:*)" "Bash(git show:*)" \
        "Bash(git status:*)" "Bash(git ls-files:*)" "Bash(git blame:*)" \
      --disallowedTools \
        "Write" "Edit" "NotebookEdit" "WebFetch" "WebSearch" "Task" "Agent" \
        "Bash(git diff *--output*)" "Bash(git log *--output*)" "Bash(git show *--output*)" \
        "Bash(git diff *--ext-diff*)" "Bash(git log *--ext-diff*)" "Bash(git show *--ext-diff*)" \
        "Bash(git difftool:*)"
}

run_reviewer() {
  # $1 = prompt
  printf '%s\n' "$1" | launch_claude "$MAX_TURNS"
}

build_prompt() {
  # $1 = mode (review|adversarial), $2 = target description, $3 = focus text
  mode="$1"
  target="$2"
  focus="$3"

  common_rules="$(cat <<'EOT'
Rules:
- You are READ-ONLY. Never modify files, never run commands that change state.
- Investigate context with your tools (Read, Grep, Glob, git diff/log/show/blame)
  before judging: a diff line is not enough to condemn or absolve code.
- Report only findings you actually verified in the code. No speculation
  presented as fact; if unsure, say so and label it as a question.

Output format (plain markdown):
1. One-paragraph summary of what the change does.
2. Findings, ranked by severity:
   - P0 (blocker), P1 (major), P2 (minor), P3 (nit)
   - For each: `file:line`, the issue, why it matters, a concrete failure
     scenario, and a suggested direction (no patches, no diffs).
3. Final verdict: SHIP / SHIP WITH FIXES / DO NOT SHIP, with one sentence why.

If you find no significant issues, say so plainly instead of inventing nits.
EOT
)"

  if [ "$mode" = "adversarial" ]; then
    stance="$(cat <<'EOT'
You are performing an ADVERSARIAL second-opinion code review. Your job is to
break confidence in this change, not to validate it. Question the chosen
design, hunt for the strongest reasons this should not ship yet: hidden
assumptions, failure modes, edge cases, security issues, simpler alternatives
that were ignored. Being agreeable is a failure mode.
EOT
)"
  else
    stance="$(cat <<'EOT'
You are performing an independent second-opinion code review for a change
written by another AI agent. Be rigorous and honest: your value is in catching
what the author missed, not in agreeing with it.
EOT
)"
  fi

  focus_block=""
  if [ -n "$focus" ]; then
    focus_block="
Additional reviewer focus requested by the user:
$focus
"
  fi

  printf '%s\n\nChanges under review:\n%s\n%s\n%s\n' \
    "$stance" "$target" "$focus_block" "$common_rules"
}

cmd_review() {
  mode="$1"
  shift

  require_repo
  require_key
  require_cli

  scope="auto"
  base=""
  focus=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --base)
        base="${2:-}"
        shift 2 || { err "--base requires a ref"; exit 2; }
        ;;
      --scope)
        scope="${2:-}"
        shift 2 || { err "--scope requires a value"; exit 2; }
        ;;
      --flash)
        MODEL="$FLASH_MODEL"
        shift
        ;;
      --model)
        MODEL="${2:-}"
        shift 2 || { err "--model requires a model id"; exit 2; }
        ;;
      --wait|--background)
        # Handled by the slash-command layer; ignore here.
        shift
        ;;
      *)
        focus="${focus:+$focus }$1"
        shift
        ;;
    esac
  done

  case "$scope" in
    auto|working-tree|branch) ;;
    *) err "invalid --scope '$scope' (use auto|working-tree|branch)"; exit 2 ;;
  esac

  require_model

  if [ "$scope" = "auto" ]; then
    if [ -n "$(git status --porcelain --untracked-files=all)" ]; then
      scope="working-tree"
    else
      scope="branch"
    fi
  fi

  if [ "$scope" = "working-tree" ]; then
    if [ -n "$base" ]; then
      err "note: --base is ignored with --scope working-tree."
      base=""
    fi
    if [ -z "$(git status --porcelain --untracked-files=all)" ]; then
      echo "glm-review: working tree is clean — nothing to review."
      exit 0
    fi
    target="$(cat <<'EOT'
The uncommitted working-tree state of the current repository (staged,
unstaged, and untracked files). Start with `git status --porcelain
--untracked-files=all` and `git diff HEAD`; list untracked files with
`git ls-files --others --exclude-standard` and read them with the Read tool.
EOT
)"
  else
    if [ -z "$base" ]; then
      base="$(detect_base)"
    fi
    if [ -z "$base" ]; then
      err "could not detect a base branch; pass one with --base <ref>."
      exit 2
    fi
    if ! git rev-parse --verify --quiet "$base" >/dev/null 2>&1; then
      err "base ref '$base' does not exist."
      exit 2
    fi
    # --quiet: exit 0 = no differences, 1 = differences, anything else = error.
    diff_rc=0
    diff_err="$(git diff --quiet "$base"...HEAD 2>&1 >/dev/null)" || diff_rc=$?
    case "$diff_rc" in
      0)
        echo "glm-review: no diff against $base — nothing to review."
        exit 0
        ;;
      1) ;;
      *)
        err "git diff $base...HEAD failed: $diff_err"
        exit 2
        ;;
    esac
    target="Everything on the current branch relative to \`$base\`. Start with \`git diff $base...HEAD\` and \`git log --oneline $base..HEAD\`, then read surrounding code as needed."
  fi

  prompt="$(build_prompt "$mode" "$target" "$focus")"

  echo "== GLM second-opinion review =="
  echo "model: $MODEL | endpoint: $BASE_URL | scope: $scope${base:+ | base: $base}"
  echo "==============================="
  echo
  run_reviewer "$prompt"
}

cmd_doctor() {
  ping=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --ping) ping=1; shift ;;
      --flash) MODEL="$FLASH_MODEL"; shift ;;
      --model) MODEL="${2:-}"; shift 2 || { err "--model requires a model id"; exit 2; } ;;
      *) err "unknown doctor option '$1'"; exit 2 ;;
    esac
  done

  require_model

  echo "glm-review doctor"
  echo "-----------------"
  if command -v claude >/dev/null 2>&1; then
    echo "claude CLI : $(command -v claude) ($(claude --version 2>/dev/null | head -1 || echo 'version unknown'))"
    help_text="$(claude --help 2>&1 || true)"
    missing="$(missing_cli_flags "$help_text")"
    if [ -z "$help_text" ]; then
      echo "CLI flags  : UNKNOWN — could not read 'claude --help' output (broken install?)"
    elif [ -z "$missing" ]; then
      echo "CLI flags  : OK — all flags used by glm-review are supported"
    else
      echo "CLI flags  : MISSING $missing — Claude Code too old for glm-review; run 'claude update'"
    fi
  else
    echo "claude CLI : NOT FOUND — glm-review needs the claude binary on PATH."
  fi
  echo "config file: $CONFIG_FILE $( [ -f "$CONFIG_FILE" ] && echo '(found)' || echo '(absent)')"
  echo "API key    : $(mask_key "$API_KEY")${API_KEY_SOURCE:+ [from $API_KEY_SOURCE]}"
  echo "endpoint   : $BASE_URL"
  echo "model      : $MODEL"
  echo "flash model: $FLASH_MODEL (via --flash)"
  echo "max turns  : $MAX_TURNS"
  echo "sandbox    : isolated session (no user/project settings, hooks, plugins, MCP), read-only tools"

  if [ "$ping" = "1" ]; then
    require_key
    require_cli
    echo
    echo "pinging $MODEL via $BASE_URL ..."
    # The ping doubles as a sandbox check: the reviewer is asked to write a
    # file through an allowlisted git command plus a shell redirection. The
    # permission layer must deny it; the file's absence is the objective proof.
    probe_file="${TMPDIR:-/tmp}/glm-review-sandbox-probe.$$"
    rm -f "$probe_file"
    ping_prompt="Step 1: try to run this exact Bash command once: \`git status --short > $probe_file\`. It is expected to be denied by the permission system; do not try alternatives or workarounds. Step 2: reply with exactly one line and nothing else: GLM-REVIEW-OK sandbox=DENIED if the command was denied, or GLM-REVIEW-OK sandbox=ALLOWED if it ran (even if it failed)."
    ping_rc=0
    out="$(printf '%s\n' "$ping_prompt" | launch_claude 3 2>&1)" || ping_rc=$?
    if [ "$ping_rc" -ne 0 ]; then
      echo "status     : FAILED"
      echo "$out"
      rm -f "$probe_file"
      exit 1
    fi
    # The reply is the last non-empty line; CLI warnings may precede it.
    reply="$(printf '%s\n' "$out" | sed -e '/^[[:space:]]*$/d' | tail -1)"
    echo "response   : $reply"
    case "$reply" in
      *GLM-REVIEW-OK*) echo "status     : OK — GLM is reachable and responding." ;;
      *) echo "status     : reachable, but unexpected reply (model/plan mismatch?)." ;;
    esac
    if [ -e "$probe_file" ]; then
      rm -f "$probe_file"
      echo "sandbox    : FAILED — the reviewer wrote $probe_file; this Claude Code version does not enforce the read-only sandbox. Do not use glm-review with it."
      exit 1
    fi
    case "$reply" in
      *sandbox=DENIED*)  echo "sandbox    : OK — write attempt denied, no file written." ;;
      *sandbox=ALLOWED*) echo "sandbox    : FAILED — the reviewer reports the write attempt was allowed. Do not use glm-review with this Claude Code version."; exit 1 ;;
      *)                 echo "sandbox    : INCONCLUSIVE — no file was written, but the reply did not report the probe outcome." ;;
    esac
  fi
}

main() {
  cmd="${1:-}"
  [ $# -gt 0 ] && shift
  case "$cmd" in
    review)      cmd_review review "$@" ;;
    adversarial) cmd_review adversarial "$@" ;;
    doctor)      cmd_doctor "$@" ;;
    ""|-h|--help) usage ;;
    *) err "unknown subcommand '$cmd'"; usage; exit 2 ;;
  esac
}

main "$@"
