#!/usr/bin/env bash
# Regression tests for scripts/glm-companion.sh.
#
# No API calls are made: a stub `claude` is placed first in PATH and simply
# echoes its argv, its stdin and the relevant environment. Requires bash 3.2+
# and git. Run from anywhere:
#
#   bash tests/companion-test.sh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/glm-companion.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/glm-review-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# --- stub claude -----------------------------------------------------------
mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "--help" ]; then
  [ -z "${STUB_HELP_FAILS:-}" ] || exit 1
  for f in --print --model --max-turns --setting-sources --strict-mcp-config --disable-slash-commands --no-session-persistence --permission-mode --tools --allowedTools --disallowedTools; do
    [ "$f" = "${STUB_MISSING_FLAG:-}" ] || printf '  %s <x>\n' "$f"
  done
  exit 0
fi
if [ "${1:-}" = "--version" ]; then echo "9.9.9 (stub)"; exit 0; fi
echo "STUB-ARGV-BEGIN"; for a in "$@"; do printf '%s\n' "$a"; done; echo "STUB-ARGV-END"
[ -z "${STUB_ARGV_FILE:-}" ] || printf '%s\n' "$@" > "$STUB_ARGV_FILE"
echo "STUB-STDIN-BEGIN"; [ -t 0 ] || input="$(cat)"; printf '%s\n' "${input:-}"; echo "STUB-STDIN-END"
echo "STUB-ENV ANTHROPIC_MODEL=${ANTHROPIC_MODEL:-} ANTHROPIC_BASE_URL=${ANTHROPIC_BASE_URL:-} CLAUDECODE=${CLAUDECODE:-unset} ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-unset}"
case "${input:-}" in *GLM-REVIEW-OK*) echo "GLM-REVIEW-OK sandbox=${STUB_SANDBOX:-DENIED}" ;; esac
STUB
chmod +x "$TMP/bin/claude"
export PATH="$TMP/bin:$PATH"
export GLM_REVIEW_API_KEY="fake-key-for-tests"
export GLM_REVIEW_CONFIG="$TMP/no-such-config"
export STUB_ARGV_FILE="$TMP/last-argv"
export ANTHROPIC_API_KEY="must-be-unset-for-reviewer"
unset GLM_REVIEW_MODEL GLM_REVIEW_FLASH_MODEL GLM_REVIEW_BASE_URL GLM_REVIEW_MAX_TURNS ZAI_API_KEY

# --- helpers ---------------------------------------------------------------
pass=0; fail=0; out=""; rc=0; IN="$TMP"
ok() { pass=$((pass+1)); printf 'ok   - %s\n' "$1"; }
ko() { fail=$((fail+1)); printf 'FAIL - %s\n       %s\n' "$1" "$2"; }
# run [VAR=value ...] bash "$SCRIPT" args...   (executed inside $IN)
run() { out="$(cd "$IN" && env "$@" </dev/null 2>&1)"; rc=$?; }
assert_rc() { if [ "$rc" -eq "$2" ]; then ok "$1"; else ko "$1" "exit code $rc, expected $2"; fi; }
assert_contains() { case "$2" in *"$3"*) ok "$1" ;; *) ko "$1" "expected to find: $3" ;; esac; }
assert_not_contains() { case "$2" in *"$3"*) ko "$1" "did not expect: $3" ;; *) ok "$1" ;; esac; }
section() { s="$(printf '%s\n' "$out" | sed -n "/STUB-$1-BEGIN/,/STUB-$1-END/p")"; printf '%s' "$s"; }

mk_repo() {
  git init -q "$1" && git -C "$1" symbolic-ref HEAD refs/heads/main
  git -C "$1" config user.email t@t && git -C "$1" config user.name t
}
commit_file() { echo "$2" > "$1/$2" && git -C "$1" add "$2" && git -C "$1" commit -qm "$2"; }

# repo A: main (2 commits) + feature branch (1 commit ahead)
A="$TMP/repo-a"; mk_repo "$A"; commit_file "$A" one; commit_file "$A" two
git -C "$A" checkout -q -b feature; commit_file "$A" three
# repo B: main + an orphan branch with no merge base
B="$TMP/repo-b"; mk_repo "$B"; commit_file "$B" one
git -C "$B" checkout -q --orphan unrelated && git -C "$B" rm -q -rf . && commit_file "$B" other

# --- usage -----------------------------------------------------------------
IN="$A"
run bash "$SCRIPT" --help
assert_rc "usage: exit 0" 0
assert_not_contains "usage: no stray 'set -euo pipefail' line" "$out" "set -euo pipefail"
assert_contains "usage: documents --wait/--background" "$out" "--wait"
assert_contains "usage: documents GLM_REVIEW_CONFIG" "$out" "GLM_REVIEW_CONFIG"

# --- configuration ---------------------------------------------------------
cfg="$TMP/config"; printf 'GLM_REVIEW_MODEL=from-file\n# comment\n\nexport GLM_REVIEW_MAX_TURNS=7\n' > "$cfg"
run GLM_REVIEW_CONFIG="$cfg" bash "$SCRIPT" doctor
assert_contains "config: file value used when env unset" "$out" "model      : from-file"
assert_contains "config: 'export KEY=VALUE' lines accepted" "$out" "max turns  : 7"
run GLM_REVIEW_CONFIG="$cfg" GLM_REVIEW_MODEL=from-env bash "$SCRIPT" doctor
assert_contains "config: environment wins over config file" "$out" "model      : from-env"
bad="$TMP/bad-config"; printf 'GLM_REVIEW_MODEL = x\n' > "$bad"
run GLM_REVIEW_CONFIG="$bad" bash "$SCRIPT" doctor
assert_rc "config: malformed line -> exit 2" 2
assert_contains "config: malformed line -> clear message" "$out" "invalid"
unreadable="$TMP/unreadable-config"; printf 'GLM_REVIEW_MODEL=x\n' > "$unreadable"; chmod 000 "$unreadable"
run GLM_REVIEW_CONFIG="$unreadable" bash "$SCRIPT" doctor
assert_rc "config: unreadable file -> exit 2" 2
assert_contains "config: unreadable file -> says not readable, not invalid" "$out" "not readable"
chmod 600 "$unreadable"
run GLM_REVIEW_MAX_TURNS=abc bash "$SCRIPT" doctor
assert_rc "config: non-numeric GLM_REVIEW_MAX_TURNS -> exit 2" 2
assert_contains "config: non-numeric GLM_REVIEW_MAX_TURNS -> message" "$out" "GLM_REVIEW_MAX_TURNS"
run GLM_REVIEW_MAX_TURNS=0 bash "$SCRIPT" doctor
assert_rc "config: GLM_REVIEW_MAX_TURNS=0 -> exit 2" 2
spaces="$TMP/spaces-config"; printf 'GLM_REVIEW_MODEL=a b\n' > "$spaces"
run GLM_REVIEW_CONFIG="$spaces" bash "$SCRIPT" doctor
assert_rc "config: unquoted value with spaces -> exit 2" 2
assert_contains "config: unquoted value with spaces -> clear message" "$out" "could not load"
once="$TMP/once-config"; printf 'GLM_REVIEW_MODEL="$(echo evaluated >> %s; echo from-file)"\n' "$TMP/side-effect" > "$once"
run GLM_REVIEW_CONFIG="$once" bash "$SCRIPT" doctor
assert_contains "config: shell-evaluated value applied" "$out" "model      : from-file"
if [ "$(wc -l < "$TMP/side-effect" | tr -d ' ')" = "1" ]; then ok "config: file is evaluated exactly once"; else ko "config: file is evaluated exactly once" "evaluated $(wc -l < "$TMP/side-effect" | tr -d ' ') times"; fi

# --- API key resolution order ---------------------------------------------
keys="$TMP/keys-config"; printf 'GLM_REVIEW_API_KEY=filekey-0123456789\nZAI_API_KEY=filezai-0123456789\n' > "$keys"
run GLM_REVIEW_CONFIG="$keys" GLM_REVIEW_API_KEY= ZAI_API_KEY=envzai-0123456789 bash "$SCRIPT" doctor
assert_contains "key order: env ZAI_API_KEY beats config-file GLM_REVIEW_API_KEY" "$out" "API key    : envz…6789"
assert_contains "key order: doctor reports the environment source" "$out" "[from environment: ZAI_API_KEY]"
run GLM_REVIEW_CONFIG="$keys" GLM_REVIEW_API_KEY= bash "$SCRIPT" doctor
assert_contains "key order: file GLM_REVIEW_API_KEY beats file ZAI_API_KEY" "$out" "API key    : file…6789"
assert_contains "key order: doctor reports the config-file source" "$out" "[from $keys: GLM_REVIEW_API_KEY]"
run GLM_REVIEW_CONFIG="$keys" GLM_REVIEW_API_KEY=envkey-0123456789 bash "$SCRIPT" doctor
assert_contains "key order: env GLM_REVIEW_API_KEY beats everything" "$out" "API key    : envk…6789"

# --- doctor ----------------------------------------------------------------
run bash "$SCRIPT" doctor --model ''
assert_rc "doctor: empty --model -> exit 2" 2
run bash "$SCRIPT" doctor --model
assert_rc "doctor: --model without value -> exit 2" 2
run bash "$SCRIPT" doctor
assert_contains "doctor: reports CLI flags OK" "$out" "CLI flags  : OK"
run STUB_MISSING_FLAG=--setting-sources bash "$SCRIPT" doctor
assert_contains "doctor: reports a missing CLI flag" "$out" "CLI flags  : MISSING --setting-sources"
run STUB_HELP_FAILS=1 bash "$SCRIPT" doctor
assert_contains "doctor: unreadable 'claude --help' is reported as such, not as missing flags" "$out" "CLI flags  : UNKNOWN"
run bash "$SCRIPT" doctor --ping
assert_contains "doctor --ping: reaches the stub" "$out" "status     : OK"
assert_contains "doctor --ping: sandbox check passes when the write probe is denied" "$out" "sandbox    : OK"
run STUB_SANDBOX=ALLOWED bash "$SCRIPT" doctor --ping
assert_contains "doctor --ping: sandbox check fails when the write probe is allowed" "$out" "sandbox    : FAILED"
assert_rc "doctor --ping: sandbox failure -> exit 1" 1
assert_contains "doctor --ping: uses the isolated launch" "$(cat "$STUB_ARGV_FILE")" "--setting-sources"
assert_contains "doctor --ping: response line shows only the model's reply (last line)" "$out" "response   : GLM-REVIEW-OK"
assert_not_contains "doctor --ping: response line does not dump the whole output" "$out" "response   : STUB-ARGV-BEGIN"

# --- argument parsing ------------------------------------------------------
run bash "$SCRIPT" review --scope branch --base
assert_rc "review: --base without value -> exit 2" 2
run bash "$SCRIPT" review --scope bogus
assert_rc "review: invalid --scope -> exit 2" 2
run bash "$SCRIPT" review --scope branch --model ''
assert_rc "review: empty --model -> exit 2" 2
run bash "$SCRIPT" bogus
assert_rc "unknown subcommand -> exit 2" 2

# --- scope resolution ------------------------------------------------------
run bash "$SCRIPT" review --scope working-tree
assert_rc "working-tree: clean tree -> exit 0" 0
assert_contains "working-tree: clean tree -> message" "$out" "nothing to review"
run bash "$SCRIPT" review --scope branch --base main
assert_rc "branch: diff against base -> launches reviewer" 0
assert_contains "branch: header shows base" "$out" "| base: main"
run bash "$SCRIPT" review --scope branch --base HEAD
assert_rc "branch: base == HEAD -> exit 0" 0
assert_contains "branch: base == HEAD -> nothing to review" "$out" "nothing to review"
IN="$B"
run bash "$SCRIPT" review --scope branch --base main
assert_rc "branch: no merge base -> exit 2, not a silent 'nothing to review'" 2
assert_contains "branch: no merge base -> git error forwarded" "$out" "no merge base"
IN="$A"; echo dirty >> "$A/one"
run bash "$SCRIPT" review --scope working-tree --base main
assert_rc "working-tree: --base is tolerated" 0
assert_contains "working-tree: --base is reported as ignored" "$out" "ignored"
assert_not_contains "working-tree: ignored --base not shown in header" "$out" "| base:"
run bash "$SCRIPT" review
assert_contains "auto scope: dirty tree -> working-tree" "$out" "scope: working-tree"
git -C "$A" checkout -q -- one

# --- reviewer launch -------------------------------------------------------
run bash "$SCRIPT" review --scope branch --base main
argv="$(section ARGV)"; stdin="$(section STDIN)"
assert_contains "launch: prompt is passed on stdin" "$stdin" "Changes under review"
assert_not_contains "launch: prompt is not passed as an argument" "$argv" "Changes under review"
assert_contains "launch: --setting-sources isolation" "$argv" "--setting-sources"
assert_contains "launch: --strict-mcp-config" "$argv" "--strict-mcp-config"
assert_contains "launch: --disable-slash-commands" "$argv" "--disable-slash-commands"
assert_contains "launch: --no-session-persistence" "$argv" "--no-session-persistence"
assert_contains "launch: --permission-mode dontAsk" "$argv" "dontAsk"
assert_contains "launch: --tools hard cap" "$argv" "Read,Glob,Grep,Bash"
assert_contains "launch: Agent disallowed" "$argv" "Agent"
assert_contains "launch: git diff --output denied" "$argv" "Bash(git diff *--output*)"
assert_contains "launch: git log --output denied" "$argv" "Bash(git log *--output*)"
assert_contains "launch: git difftool denied" "$argv" "Bash(git difftool:*)"
assert_contains "launch: Task disallowed" "$argv" "Task"
assert_contains "launch: --max-turns default" "$argv" "40"
assert_contains "launch: ANTHROPIC_API_KEY unset for the reviewer" "$out" "ANTHROPIC_API_KEY=unset"
assert_contains "launch: CLAUDECODE unset for the reviewer" "$out" "CLAUDECODE=unset"
run STUB_MISSING_FLAG=--strict-mcp-config bash "$SCRIPT" review --scope branch --base main
assert_rc "launch: refuses to run on a Claude Code lacking a required flag" 2
assert_contains "launch: names the unsupported flag" "$out" "does not support: --strict-mcp-config"
run bash "$SCRIPT" review --scope branch --base main --flash
assert_contains "launch: --flash selects the flash model" "$out" "ANTHROPIC_MODEL=glm-5.3-flash[1m]"
run bash "$SCRIPT" adversarial --scope branch --base main 'focus with "quotes" and $(not expanded)'
assert_contains "adversarial: focus text reaches the prompt verbatim" "$(section STDIN)" 'focus with "quotes" and $(not expanded)'
assert_contains "adversarial: adversarial stance" "$(section STDIN)" "ADVERSARIAL"
run bash "$SCRIPT" review --scope branch --base main --wait --background
assert_rc "review: --wait/--background accepted as no-ops" 0

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
