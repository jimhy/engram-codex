# engram x codex - Stop hook adapter. ASCII-only so Windows PowerShell 5.1 parses it.
#   Codex fires Stop at the END OF EVERY TURN, and requires this hook to print valid JSON on
#   stdout when it exits 0 (plain text is rejected). So we ALWAYS finish by printing "{}" (which
#   lets the session stop normally) and do consolidation bookkeeping purely as a side effect:
#     - review-prepare computes the incremental slice since the last watermark + drops a pending.
#     - Only when the new increment is big enough (>= ENGRAM_REVIEW_MIN_LINES, default 40) do we
#       launch a detached reviewer; otherwise the pending is left for the next SessionStart
#       catch-up. This avoids running a full review after every single turn.
#   ENGRAM_REVIEWER guard: inside the reviewer subprocess, print {} and bail (no recursion).
# Best-effort: never disrupt the session; on any error still print {} and exit 0.

function Write-StopResult { Write-Output '{}' }

if ($env:ENGRAM_REVIEWER -eq '1') { Write-StopResult; exit 0 }

# Read hook stdin with a hard timeout so we never hang if codex does not close the pipe.
# If it times out empty, $transcript will be missing below and we simply skip this turn's review.
$raw = ''
try {
    $sr = New-Object System.IO.StreamReader([Console]::OpenStandardInput())
    $rt = $sr.ReadToEndAsync()
    if ($rt.Wait(3000)) { $raw = $rt.Result } else { $raw = '' }
} catch { $raw = '' }

try {
    $hook = $null
    if ($raw) { try { $hook = $raw | ConvertFrom-Json } catch { $hook = $null } }
    $transcript = if ($hook -and $hook.transcript_path) { [string]$hook.transcript_path } else { '' }
    $cwd = if ($hook -and $hook.cwd) { [string]$hook.cwd } else { (Get-Location).Path }
    $sid = if ($hook -and $hook.session_id) { [string]$hook.session_id } else { '' }
    if (-not $transcript) { Write-StopResult; exit 0 }
    if (-not $sid) { $sid = [System.IO.Path]::GetFileNameWithoutExtension($transcript) }
    if (-not $sid) { $sid = 'codex-session' }

    $scriptDir  = $PSScriptRoot
    $pluginRoot = if ($env:PLUGIN_ROOT) { $env:PLUGIN_ROOT } elseif ($env:CLAUDE_PLUGIN_ROOT) { $env:CLAUDE_PLUGIN_ROOT } else { Split-Path -Parent $scriptDir }
    $engram = if ($env:ENGRAM_BIN) { $env:ENGRAM_BIN } else { Join-Path $pluginRoot 'bin\engram-windows-x86_64.exe' }
    if (-not (Test-Path $engram)) { Write-StopResult; exit 0 }

    $base = Join-Path $env:USERPROFILE '.engram\codex'
    $work = Join-Path $base 'pending'
    $wm   = Join-Path $base 'watermark.json'

    # resolve db paths for the current scope (engine anchors from cwd up to nearest .engram).
    $paths = & $engram resolve --project-dir $cwd --format json | ConvertFrom-Json

    # compute incremental slice since the watermark + drop a pending marker.
    $planRaw = & $engram review-prepare --transcript $transcript --session-id $sid --watermark $wm --work-dir $work `
        --general-db $paths.general_db --project-db $paths.project_db --project-name $paths.project_name
    $plan = $null
    if ($planRaw) { try { $plan = $planRaw | ConvertFrom-Json } catch { $plan = $null } }

    if ($plan -and $plan.action -eq 'review') {
        $minLines = 40
        if ($env:ENGRAM_REVIEW_MIN_LINES) { [int]::TryParse([string]$env:ENGRAM_REVIEW_MIN_LINES, [ref]$minLines) | Out-Null }
        $newLines = [int]$plan.end_line - [int]$plan.start_line
        if ($newLines -ge $minLines) {
            & (Join-Path $scriptDir 'codex-launch-reviewer.ps1') `
                -Engram $engram -Slice $plan.slice `
                -GeneralDb $plan.general_db -ProjectDb $plan.project_db -ProjectName $plan.project_name `
                -Pending $plan.pending -Watermark $wm -Cwd $cwd *>$null
        }
        # else: leave the pending; next SessionStart catch-up consolidates it once it grows / on restart.
    }
}
catch {
    # swallow; we still must return valid JSON below.
}
Write-StopResult
exit 0
