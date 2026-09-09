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
# 二进制解析三档：ENGRAM_BIN 覆盖 → 公共位置（全机一份，与 ~/.engram 库同目录、
# 不隶属任何 CLI）→ 插件自带的兜底（离线 / 未装公共位置时）。
shared="$HOME/.engram/bin/$bin"
if [ -n "${ENGRAM_BIN:-}" ]; then engram="$ENGRAM_BIN"
elif [ -f "$shared" ];      then engram="$shared"
else                             engram="$plugin_root/bin/$bin"; fi
# 把引擎收敛到公共位置 ~/.engram/bin（全机一份、谁新用谁）。静默 best-effort：
# 失败绝不影响会话，上面解析出的 $engram 照常可用。
bash "$script_dir/ensure-engram.sh" >/dev/null 2>&1 || true

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
