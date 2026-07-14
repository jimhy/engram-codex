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

# scope kind: a management-directory db has a 'workspace' marker next to it
# (<dir>/.engram/workspace) -> the reviewer gets workspace consolidation rules.
kind="project"
[ -f "$(dirname "$project")/workspace" ] && kind="workspace"

[ -f "$prompt_tpl" ] || exit 0
prompt="$(cat "$prompt_tpl")"
prompt="${prompt//"{{TRANSCRIPT}}"/$slice}"
prompt="${prompt//"{{ENGRAM}}"/$engram}"
prompt="${prompt//"{{GENERAL_DB}}"/$general}"
prompt="${prompt//"{{PROJECT_DB}}"/$project}"
prompt="${prompt//"{{PROJECT_NAME}}"/$pname}"
prompt="${prompt//"{{KIND}}"/$kind}"
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

# ---- 代理派生（堵 403）：headless 复盘子进程若缺 HTTPS_PROXY 会走直连，被上游以
# 「403 Request not allowed」按地区限制拒绝。启动前确保 HTTPS_PROXY/HTTP_PROXY 有值，
# 优先级：① ENGRAM_REVIEWER_PROXY 显式指定；② 已有 HTTPS_PROXY/https_proxy → 继承不动；
# ③ ALL_PROXY/all_proxy → 据以设两者；④ 都没有 → 不设（直连，可能失败）。无注册表分支（POSIX）。
# 值可能是 host:port（无 scheme），统一补 http://。export 后由下方 nohup 子进程继承。
engram_norm_proxy() {
  case "$1" in
    *://*) printf '%s' "$1" ;;
    *)     printf 'http://%s' "$1" ;;
  esac
}
if [ -n "${ENGRAM_REVIEWER_PROXY:-}" ]; then
  _p="$(engram_norm_proxy "$ENGRAM_REVIEWER_PROXY")"
  export HTTPS_PROXY="$_p" HTTP_PROXY="$_p"
elif [ -n "${HTTPS_PROXY:-}" ] || [ -n "${https_proxy:-}" ]; then
  :  # 继承环境里已有的代理
elif [ -n "${ALL_PROXY:-}" ] || [ -n "${all_proxy:-}" ]; then
  _src="${ALL_PROXY:-$all_proxy}"
  _p="$(engram_norm_proxy "$_src")"
  export HTTPS_PROXY="$_p" HTTP_PROXY="$_p"
fi

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
