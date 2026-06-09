#!/usr/bin/env bash
# engram x codex - launch one detached headless reviewer via `codex exec` (posix).
# Shared by Stop review and SessionStart catch-up. Arg 1 = plan JSON (from review-prepare /
# catchup-scan); fields are extracted with sed so there is no jq dependency.
plan="$1"
[ -n "$plan" ] || exit 0

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_root="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(dirname "$script_dir")}}"
case "$(uname -s)" in
  Darwin) case "$(uname -m)" in arm64|aarch64) bin="engram-macos-aarch64" ;; *) bin="engram-macos-x86_64" ;; esac ;;
  *)      bin="engram-linux-x86_64" ;;
esac
engram="${ENGRAM_BIN:-$plugin_root/bin/$bin}"
prompt_tpl="$plugin_root/scripts/reviewer-prompt.md"
skill="$plugin_root/skills/engram/SKILL.md"
wm="$HOME/.engram/codex/watermark.json"
codex="${ENGRAM_REVIEWER_CODEX:-codex}"

jget() { printf '%s' "$plan" | sed -n "s/.*\"$1\":\"\\([^\"]*\\)\".*/\\1/p"; }
slice="$(jget slice)"; general="$(jget general_db)"; project="$(jget project_db)"
pname="$(jget project_name)"; pending="$(jget pending)"

[ -f "$prompt_tpl" ] || exit 0
prompt="$(cat "$prompt_tpl")"
prompt="${prompt//"{{TRANSCRIPT}}"/$slice}"
prompt="${prompt//"{{ENGRAM}}"/$engram}"
prompt="${prompt//"{{GENERAL_DB}}"/$general}"
prompt="${prompt//"{{PROJECT_DB}}"/$project}"
prompt="${prompt//"{{PROJECT_NAME}}"/$pname}"
prompt="${prompt//"{{PENDING}}"/$pending}"
prompt="${prompt//"{{WATERMARK}}"/$wm}"
prompt="${prompt//"{{SKILL}}"/$skill}"

# codex rollout format note (so the reviewer reads the transcript correctly).
prompt="$prompt

## About this transcript (codex rollout JSONL)
Each line is a JSON object {timestamp, type, payload}:
- payload.type == \"message\": role user/assistant; content[].text holds the conversation
  (assistant phase == \"final_answer\" is the final answer).
- payload.type == \"function_call\" / \"function_call_output\": a tool call and its result, linked
  flatly by the SAME call_id (NOT nested; they can be many lines apart). Use this to rebuild the
  \"which memory was recalled -> what the model then did\" causal chain.
- type == \"event_msg\" / \"session_meta\" / \"turn_context\" are UI/meta noise; ignore them.
- The injected memory hot-index appears as a developer message."

# Launch FULLY DETACHED so the hook returns instantly (critical for Stop: it must print its {} and
# return without waiting for the multi-second reviewer). ENGRAM_REVIEWER=1 is inherited so the
# reviewer's own hooks bail out (no recursion). Bypass sandbox so the reviewer can write the redb
# stores in ~/.engram and the project dir (some outside cwd); --ephemeral keeps it from writing its
# own rollout file. Prompt goes in via stdin (the `-` positional arg).
ENGRAM_REVIEWER=1 nohup "$codex" exec --ephemeral --skip-git-repo-check \
  --dangerously-bypass-approvals-and-sandbox --dangerously-bypass-hook-trust - \
  >/dev/null 2>&1 <<EOF &
$prompt
EOF
exit 0
