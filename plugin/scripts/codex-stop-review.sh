#!/usr/bin/env bash
# engram x codex - Stop hook (posix). Mirror of codex-stop-review.ps1.
#   Codex fires Stop at the END OF EVERY TURN and requires valid JSON on stdout when it exits 0.
#   So we ALWAYS finish by printing "{}" and do consolidation bookkeeping as a side effect:
#     - review-prepare computes the incremental slice since the watermark + drops a pending.
#     - Only when the new increment is big enough (>= ENGRAM_REVIEW_MIN_LINES, default 40) do we
#       launch a detached reviewer; otherwise the pending is left for the next SessionStart
#       catch-up. This avoids a full review after every single turn.
#   ENGRAM_REVIEWER guard: print {} and bail inside the reviewer subprocess (no recursion).
write_result() { printf '{}\n'; }
[ "$ENGRAM_REVIEWER" = "1" ] && { write_result; exit 0; }

# Read hook stdin with a hard 3s timeout so we never hang if codex does not close the pipe.
# If it times out / is empty, $transcript will be missing below and we just skip this turn.
raw="$(timeout 3 cat 2>/dev/null || true)"

jget() { printf '%s' "$raw" | sed -n "s/.*\"$1\"[ ]*:[ ]*\"\\([^\"]*\\)\".*/\\1/p"; }
transcript="$(jget transcript_path)"
cwd="$(jget cwd)"; [ -n "$cwd" ] || cwd="$(pwd)"
sid="$(jget session_id)"
[ -n "$transcript" ] || { write_result; exit 0; }
[ -n "$sid" ] || sid="codex-session"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_root="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(dirname "$script_dir")}}"
case "$(uname -s)" in
  Darwin) case "$(uname -m)" in arm64|aarch64) bin="engram-macos-aarch64" ;; *) bin="engram-macos-x86_64" ;; esac ;;
  *)      bin="engram-linux-x86_64" ;;
esac
engram="${ENGRAM_BIN:-$plugin_root/bin/$bin}"
[ -x "$engram" ] || { write_result; exit 0; }

base="$HOME/.engram/codex"; work="$base/pending"; wm="$base/watermark.json"

# resolve db paths for the current scope (engine anchors from cwd up to nearest .engram).
paths="$("$engram" resolve --project-dir "$cwd" --format json 2>/dev/null)"
pget() { printf '%s' "$paths" | sed -n "s/.*\"$1\":\"\\([^\"]*\\)\".*/\\1/p"; }
gdb="$(pget general_db)"; pdb="$(pget project_db)"; pname="$(pget project_name)"

# compute incremental slice since the watermark + drop a pending marker.
plan="$("$engram" review-prepare --transcript "$transcript" --session-id "$sid" \
  --watermark "$wm" --work-dir "$work" --general-db "$gdb" --project-db "$pdb" --project-name "$pname" 2>/dev/null)"

case "$plan" in
  *'"action":"review"'*)
    start="$(printf '%s' "$plan" | sed -n 's/.*"start_line":\([0-9]*\).*/\1/p')"
    end="$(printf '%s' "$plan" | sed -n 's/.*"end_line":\([0-9]*\).*/\1/p')"
    [ -n "$start" ] || start=0
    [ -n "$end" ] || end=0
    min="${ENGRAM_REVIEW_MIN_LINES:-40}"
    if [ $((end - start)) -ge "$min" ]; then
      "$script_dir/codex-launch-reviewer.sh" "$plan" >/dev/null 2>&1 &
    fi
    # else: leave the pending; next SessionStart catch-up consolidates it once it grows / on restart.
    ;;
esac
write_result
exit 0
