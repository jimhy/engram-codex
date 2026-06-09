#!/usr/bin/env bash
# engram x codex - SessionStart hook (posix). Mirror of codex-session-start.ps1.
#   1. ENGRAM_REVIEWER guard: bail inside the reviewer subprocess (no inject / no catch-up).
#   2. Inject: engram hot-index --emit json. No stdin read (codex runs the hook with the session
#      cwd as its working dir, so hot-index anchors the scope from current_dir). Its single-line
#      JSON is the ONLY thing written to stdout; codex consumes it as injected context.
#   3. Catch-up: re-run a leftover review if a previous session left a pending marker.
# Best-effort: a hook failure must never break session startup -> swallow errors, always exit 0.
[ "$ENGRAM_REVIEWER" = "1" ] && exit 0

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# plugin root: codex injects PLUGIN_ROOT (compat CLAUDE_PLUGIN_ROOT); fall back to the script's
# parent for local dev (scripts/ sits directly under the plugin root).
plugin_root="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(dirname "$script_dir")}}"
case "$(uname -s)" in
  Darwin) case "$(uname -m)" in arm64|aarch64) bin="engram-macos-aarch64" ;; *) bin="engram-macos-x86_64" ;; esac ;;
  *)      bin="engram-linux-x86_64" ;;
esac
engram="${ENGRAM_BIN:-$plugin_root/bin/$bin}"
base="$HOME/.engram/codex"
[ -x "$engram" ] || exit 0

# 2) inject (stdout passthrough). --state gates re-injection when the scope root is unchanged.
"$engram" hot-index --emit json --hook-event SessionStart \
  --state "$base/active.state" --status-file "$base/status.txt" --log "$base/hook.log" 2>/dev/null

# 3) catch-up a leftover review (best-effort). catchup-scan is a cheap dir scan; the reviewer it
#    may launch is itself fully detached, so this does not stall startup.
plan="$("$engram" catchup-scan --work-dir "$base/pending" 2>/dev/null)"
case "$plan" in
  *'"action":"review"'*)
    "$script_dir/codex-launch-reviewer.sh" "$plan" >/dev/null 2>&1 &
    ;;
esac
exit 0
