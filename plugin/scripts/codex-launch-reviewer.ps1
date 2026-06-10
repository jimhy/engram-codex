# engram x codex - launch one detached headless reviewer via `codex exec`.
# Shared by Stop review and SessionStart catch-up. ASCII-only so PS5.1 parses it.
# All paths handed into the reviewer prompt are forward-slashed (the reviewer runs engram via a shell).
param(
    [Parameter(Mandatory = $true)][string]$Engram,
    [Parameter(Mandatory = $true)][string]$Slice,
    [Parameter(Mandatory = $true)][string]$GeneralDb,
    [Parameter(Mandatory = $true)][string]$ProjectDb,
    [Parameter(Mandatory = $true)][string]$ProjectName,
    [Parameter(Mandatory = $true)][string]$Pending,
    [Parameter(Mandatory = $true)][string]$Watermark,
    [string]$Cwd = $env:USERPROFILE
)
$ErrorActionPreference = 'Stop'

$scriptDir  = $PSScriptRoot
$pluginRoot = if ($env:PLUGIN_ROOT) { $env:PLUGIN_ROOT } elseif ($env:CLAUDE_PLUGIN_ROOT) { $env:CLAUDE_PLUGIN_ROOT } else { Split-Path -Parent $scriptDir }

# Assets bundled inside the plugin.
$promptTpl = Join-Path $pluginRoot 'scripts\reviewer-prompt.md'
$skill     = Join-Path $pluginRoot 'skills\engram\SKILL.md'

# codex executable: env override, else rely on PATH resolution inside cmd. Optional model override.
$codex = if ($env:ENGRAM_REVIEWER_CODEX) { $env:ENGRAM_REVIEWER_CODEX } else { 'codex' }
$model = $env:ENGRAM_REVIEWER_MODEL

# forward-slash helper for paths embedded in the prompt.
$fs = { param($p) if ($p) { $p -replace '\\', '/' } else { $p } }

# scope kind: a management-directory db has a 'workspace' marker next to it
# (<dir>/.engram/workspace) -> the reviewer gets workspace consolidation rules.
$kind = 'project'
try {
    $marker = Join-Path (Split-Path -Parent $ProjectDb) 'workspace'
    if (Test-Path -LiteralPath $marker) { $kind = 'workspace' }
} catch {}

$tpl = Get-Content -Raw -Encoding UTF8 -LiteralPath $promptTpl
$prompt = $tpl
$prompt = $prompt.Replace('{{TRANSCRIPT}}',   (& $fs $Slice))
$prompt = $prompt.Replace('{{ENGRAM}}',       (& $fs $Engram))
$prompt = $prompt.Replace('{{GENERAL_DB}}',   (& $fs $GeneralDb))
$prompt = $prompt.Replace('{{PROJECT_DB}}',   (& $fs $ProjectDb))
$prompt = $prompt.Replace('{{PROJECT_NAME}}', $ProjectName)
$prompt = $prompt.Replace('{{KIND}}',         $kind)
$prompt = $prompt.Replace('{{PENDING}}',      (& $fs $Pending))
$prompt = $prompt.Replace('{{WATERMARK}}',    (& $fs $Watermark))
$prompt = $prompt.Replace('{{SKILL}}',        (& $fs $skill))

# codex rollout format note appended so the reviewer reads the transcript correctly.
$codexNote = @'

## About this transcript (codex rollout JSONL)
Each line is a JSON object {timestamp, type, payload}:
- payload.type == "message": role user/assistant; content[].text holds the conversation
  (assistant phase == "final_answer" is the final answer).
- payload.type == "function_call" / "function_call_output": a tool call and its result, linked
  flatly by the SAME call_id (NOT nested; they can be many lines apart). Use this to rebuild the
  "which memory was recalled -> what the model then did" causal chain.
- type == "event_msg" (task_started/task_complete/token_count) and type "session_meta" /
  "turn_context" are UI/meta noise; ignore them when judging real use.
- The injected memory hot-index appears as a developer message; use it to see which memory was recalled.
'@
$prompt = $prompt + $codexNote

if ($env:ENGRAM_HOOK_DRYRUN -eq '1') {
    Write-Host "[dry-run] reviewer-cli = codex exec"
    Write-Host "[dry-run] codex        = $codex"
    Write-Host "[dry-run] model        = $model"
    Write-Host "[dry-run] cwd          = $Cwd"
    Write-Host "[dry-run] slice        = $Slice"
    Write-Host "[dry-run] general      = $GeneralDb"
    Write-Host "[dry-run] project      = $ProjectDb ($ProjectName, kind=$kind)"
    Write-Host "[dry-run] pending      = $Pending"
    Write-Host "[dry-run] watermark    = $Watermark"
    Write-Host "[dry-run] prompt $($prompt.Length) chars"
    return
}

# Launch FULLY DETACHED so the hook returns instantly. This is critical for the Stop hook: it
# must print its {} and return WITHOUT waiting for the multi-second reviewer. Same technique as
# the Claude adapter: write a one-shot .cmd that does its OWN stdio redirection, then Start-Process
# it with -WindowStyle Hidden (UseShellExecute=true) so it does NOT inherit this hook's stdout
# handle (which codex captures and would otherwise block on until the reviewer exits).
$promptFile = Join-Path $env:TEMP ("engram-codex-review-" + $PID + "-" + (Get-Random) + ".txt")
Set-Content -LiteralPath $promptFile -Value $prompt -Encoding UTF8
$outFile = Join-Path $env:TEMP ("engram-codex-review-out-" + $PID + "-" + (Get-Random) + ".txt")
$errFile = Join-Path $env:TEMP ("engram-codex-review-err-" + $PID + "-" + (Get-Random) + ".txt")
$cmdFile = Join-Path $env:TEMP ("engram-codex-review-" + $PID + "-" + (Get-Random) + ".cmd")

# codex exec reads the prompt from stdin via the `-` positional arg. Reviewer runs read-only on
# files but must write the redb stores (in ~/.engram and the project dir), some outside cwd, so
# we bypass the sandbox; --dangerously-bypass-hook-trust lets our own hooks fire (they no-op via
# the ENGRAM_REVIEWER guard); --ephemeral keeps this subprocess from writing its own rollout file.
$modelArg = if ($model) { ' -m "' + $model + '"' } else { '' }
$line = '"' + $codex + '" exec --ephemeral --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox --dangerously-bypass-hook-trust -C "' + $Cwd + '"' + $modelArg + ' - < "' + $promptFile + '" > "' + $outFile + '" 2> "' + $errFile + '"'
# ANSI (system codepage) so a non-ASCII TEMP path survives when cmd reads the batch file.
Set-Content -LiteralPath $cmdFile -Value $line -Encoding Default

# ENGRAM_REVIEWER=1 is inherited by the launched process (ShellExecute passes parent env), so the
# reviewer's own SessionStart/Stop hooks bail out -> no recursion.
$env:ENGRAM_REVIEWER = '1'
try {
    Start-Process -FilePath $cmdFile -WindowStyle Hidden -ErrorAction Stop
}
catch {
    Write-Host ("engram: failed to launch codex reviewer: " + $_.Exception.Message)
}
