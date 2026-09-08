#!/usr/bin/env bash
# glm-review companion script.
#
# Runs GLM (Z.ai) as an independent second-opinion code reviewer by launching
# a headless `claude -p` instance pointed at the Anthropic-compatible endpoint
# of the GLM Coding Plan, restricted to read-only tools.
#
# Usage:
#   glm-companion.sh review      [--flash|--model <id>] [--base <ref>] [--scope auto|working-tree|branch]
#   glm-companion.sh adversarial [--flash|--model <id>] [--base <ref>] [--scope auto|working-tree|branch] [focus text...]
#   glm-companion.sh doctor      [--ping] [--flash|--model <id>]
#
# Configuration (env vars, or KEY=VALUE lines in ~/.glm-review/config):
#   GLM_REVIEW_API_KEY      Z.ai API key (ZAI_API_KEY is also honored)
#   GLM_REVIEW_BASE_URL     default: https://api.z.ai/api/anthropic
#   GLM_REVIEW_MODEL        default: glm-5.3[1m] (1M context)
#   GLM_REVIEW_FLASH_MODEL  default: glm-5.3-flash[1m] (used by --flash)
#   GLM_REVIEW_MAX_TURNS    default: 40

set -euo pipefail

CONFIG_FILE="${GLM_REVIEW_CONFIG:-$HOME/.glm-review/config}"
if [ -f "$CONFIG_FILE" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG_FILE"
fi

BASE_URL="${GLM_REVIEW_BASE_URL:-https://api.z.ai/api/anthropic}"
MODEL="${GLM_REVIEW_MODEL:-glm-5.3[1m]}"
FLASH_MODEL="${GLM_REVIEW_FLASH_MODEL:-glm-5.3-flash[1m]}"
MAX_TURNS="${GLM_REVIEW_MAX_TURNS:-40}"
API_KEY="${GLM_REVIEW_API_KEY:-${ZAI_API_KEY:-}}"

# Fallback: reuse the key stored by the claude-glm wrapper kit, if present.
CLAUDE_GLM_KEY_FILE="$HOME/.config/claude-glm/api_key"
if [ -z "$API_KEY" ] && [ -f "$CLAUDE_GLM_KEY_FILE" ]; then
  API_KEY="$(head -1 "$CLAUDE_GLM_KEY_FILE" | tr -d '[:space:]')"
fi

err() { printf 'glm-review: %s\n' "$*" >&2; }

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
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

require_repo() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    err "not inside a git repository."
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

run_reviewer() {
  # $1 = prompt
  prompt="$1"
  env -u ANTHROPIC_API_KEY -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT \
    ANTHROPIC_BASE_URL="$BASE_URL" \
    ANTHROPIC_AUTH_TOKEN="$API_KEY" \
    ANTHROPIC_MODEL="$MODEL" \
    ANTHROPIC_DEFAULT_OPUS_MODEL="$MODEL" \
    ANTHROPIC_DEFAULT_SONNET_MODEL="$MODEL" \
    ANTHROPIC_DEFAULT_HAIKU_MODEL="$MODEL" \
    ANTHROPIC_SMALL_FAST_MODEL="$MODEL" \
    claude -p "$prompt" \
      --model "$MODEL" \
      --max-turns "$MAX_TURNS" \
      --allowedTools \
        "Read" "Glob" "Grep" "LS" \
        "Bash(git diff:*)" "Bash(git log:*)" "Bash(git show:*)" \
        "Bash(git status:*)" "Bash(git ls-files:*)" "Bash(git blame:*)" \
      --disallowedTools "Write" "Edit" "NotebookEdit" "WebFetch" "WebSearch" "Task"
}

build_prompt() {
  # $1 = mode (review|adversarial), $2 = target description, $3 = focus text
  mode="$1"
  target="$2"
  focus="$3"

  common_rules="$(cat <<'EOF'
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
EOF
)"

  if [ "$mode" = "adversarial" ]; then
    stance="$(cat <<'EOF'
You are performing an ADVERSARIAL second-opinion code review. Your job is to
break confidence in this change, not to validate it. Question the chosen
design, hunt for the strongest reasons this should not ship yet: hidden
assumptions, failure modes, edge cases, security issues, simpler alternatives
that were ignored. Being agreeable is a failure mode.
EOF
)"
  else
    stance="$(cat <<'EOF'
You are performing an independent second-opinion code review for a change
written by another AI agent. Be rigorous and honest: your value is in catching
what the author missed, not in agreeing with it.
EOF
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

  if [ -z "$MODEL" ]; then
    err "model id is empty."
    exit 2
  fi

  if [ "$scope" = "auto" ]; then
    if [ -n "$(git status --porcelain --untracked-files=all)" ]; then
      scope="working-tree"
    else
      scope="branch"
    fi
  fi

  if [ "$scope" = "working-tree" ]; then
    if [ -z "$(git status --porcelain --untracked-files=all)" ]; then
      echo "glm-review: working tree is clean — nothing to review."
      exit 0
    fi
    target="$(cat <<'EOF'
The uncommitted working-tree state of the current repository (staged,
unstaged, and untracked files). Start with `git status --porcelain
--untracked-files=all` and `git diff HEAD`; list untracked files with
`git ls-files --others --exclude-standard` and read them with the Read tool.
EOF
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
    if [ -z "$(git diff "$base"...HEAD 2>/dev/null)" ]; then
      echo "glm-review: no diff against $base — nothing to review."
      exit 0
    fi
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

  echo "glm-review doctor"
  echo "-----------------"
  if command -v claude >/dev/null 2>&1; then
    echo "claude CLI : $(command -v claude) ($(claude --version 2>/dev/null | head -1 || echo 'version unknown'))"
  else
    echo "claude CLI : NOT FOUND — glm-review needs the claude binary on PATH."
  fi
  echo "config file: $CONFIG_FILE $( [ -f "$CONFIG_FILE" ] && echo '(found)' || echo '(absent)')"
  if [ -z "${GLM_REVIEW_API_KEY:-}${ZAI_API_KEY:-}" ] && [ -n "$API_KEY" ] && [ -f "$CLAUDE_GLM_KEY_FILE" ]; then
    echo "API key    : $(mask_key "$API_KEY") [from $CLAUDE_GLM_KEY_FILE]"
  else
    echo "API key    : $(mask_key "$API_KEY")"
  fi
  echo "endpoint   : $BASE_URL"
  echo "model      : $MODEL"
  echo "flash model: $FLASH_MODEL (via --flash)"
  echo "max turns  : $MAX_TURNS"

  if [ "$ping" = "1" ]; then
    require_key
    echo
    echo "pinging $MODEL via $BASE_URL ..."
    if out="$(env -u ANTHROPIC_API_KEY -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT \
      ANTHROPIC_BASE_URL="$BASE_URL" \
      ANTHROPIC_AUTH_TOKEN="$API_KEY" \
      ANTHROPIC_MODEL="$MODEL" \
      claude -p "Reply with exactly: GLM-REVIEW-OK" --model "$MODEL" --max-turns 1 2>&1)"; then
      echo "response   : $out"
      case "$out" in
        *GLM-REVIEW-OK*) echo "status     : OK — GLM is reachable and responding." ;;
        *) echo "status     : reachable, but unexpected reply (model/plan mismatch?)." ;;
      esac
    else
      echo "status     : FAILED"
      echo "$out"
      exit 1
    fi
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
