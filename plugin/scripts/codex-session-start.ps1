# engram x codex - SessionStart hook adapter. ASCII-only so Windows PowerShell 5.1 parses it.
#   1. ENGRAM_REVIEWER guard: when running inside the reviewer subprocess, bail immediately
#      (no inject, no catch-up) so the reviewer's own SessionStart does not recurse.
#   2. Inject: forward the hook stdin JSON to `engram hot-index --emit json`; its single-line
#      JSON (hookSpecificOutput.additionalContext) is the ONLY thing written to stdout, which
#      codex consumes as injected developer context.
#   3. Catch-up: if a previous session ended abnormally and left a pending review, launch a
#      detached reviewer on that leftover increment (nothing lost, nothing redone).
# Best-effort: a hook failure must never break session startup -> swallow errors, always exit 0.
if ($env:ENGRAM_REVIEWER -eq '1') { exit 0 }

# We deliberately do NOT read stdin here. codex runs hook commands with the session cwd as their
# working directory, so `hot-index` (without --from-hook-stdin) anchors the scope from current_dir
# directly. Avoiding stdin sidesteps any risk of blocking on a stdin that codex might not close.
try {
    $scriptDir  = $PSScriptRoot
    # plugin root: codex injects PLUGIN_ROOT (compat CLAUDE_PLUGIN_ROOT); fall back to the
    # script's parent for local dev (scripts/ sits directly under the plugin root).
    $pluginRoot = if ($env:PLUGIN_ROOT) { $env:PLUGIN_ROOT } elseif ($env:CLAUDE_PLUGIN_ROOT) { $env:CLAUDE_PLUGIN_ROOT } else { Split-Path -Parent $scriptDir }
    $engram = if ($env:ENGRAM_BIN) { $env:ENGRAM_BIN } else { Join-Path $pluginRoot 'bin\engram-windows-x86_64.exe' }

    $base       = Join-Path $env:USERPROFILE '.engram\codex'
    $state      = Join-Path $base 'active.state'
    $statusFile = Join-Path $base 'status.txt'
    $log        = Join-Path $base 'hook.log'
    $work       = Join-Path $base 'pending'
    $wm         = Join-Path $base 'watermark.json'

    if (Test-Path $engram) {
        # 2) inject (stdout passthrough). hot-index anchors the scope from cwd (= session cwd here);
        #    --state gates re-injection when the scope root is unchanged.
        & $engram hot-index --emit json --hook-event SessionStart --state $state --status-file $statusFile --log $log

        # 3) catch-up a leftover review (best-effort). catchup-scan is a cheap dir scan; the
        #    reviewer it may launch is itself fully detached, so this does not stall startup.
        $planRaw = & $engram catchup-scan --work-dir $work
        $plan = $null
        if ($planRaw) { try { $plan = $planRaw | ConvertFrom-Json } catch { $plan = $null } }
        if ($plan -and $plan.action -eq 'review') {
            & (Join-Path $scriptDir 'codex-launch-reviewer.ps1') `
                -Engram $engram -Slice $plan.slice `
                -GeneralDb $plan.general_db -ProjectDb $plan.project_db -ProjectName $plan.project_name `
                -Pending $plan.pending -Watermark $wm *>$null
        }
    }
}
catch {
    # swallow: injection (if any) already reached stdout; startup must proceed.
}
exit 0
