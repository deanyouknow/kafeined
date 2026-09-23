# kafeined.ps1 — Windows keep-awake runner for AI agent sessions.
# Uses the Win32 SetThreadExecutionState API (no admin rights, no downloads).
#
# Usage:
#   kafeined.ps1 start  [-Display] [-Hours 6]
#   kafeined.ps1 while  [-Display] [-Hours 6] <command> [args...]
#   kafeined.ps1 stop
#   kafeined.ps1 status
#   kafeined.ps1 renew

param(
  [Parameter(Position = 0)]
  [ValidateSet('start', 'stop', 'status', 'renew', 'while')]
  [string]$Command = 'status',

  [switch]$Display,

  [int]$Hours = 6,

  # everything after the known parameters — the command run by `while`
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$CmdArgs
)

$ErrorActionPreference = 'SilentlyContinue'

$dir = Join-Path $env:TEMP 'kafeined'
$pidFile = Join-Path $dir 'pid'
$logFile = Join-Path $dir 'log'
$metaFile = Join-Path $dir 'meta'

# ES_CONTINUOUS | ES_SYSTEM_REQUIRED (| ES_DISPLAY_REQUIRED when -Display)
$flagsSystem = 0x80000001
$flagsDisplay = 0x80000005

function Get-AlivePid {
  if (Test-Path $pidFile) {
    $existing = [int](Get-Content $pidFile -ErrorAction SilentlyContinue)
    $proc = Get-Process -Id $existing -ErrorAction SilentlyContinue
    if ($proc) { return $existing }
  }
  return $null
}

# Spawn a detached holder that keeps the machine awake for $Hours. Returns the
# holder PID, or $null if it died immediately.
function Start-Hold {
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  Remove-Item $pidFile, $metaFile -Force -ErrorAction SilentlyContinue

  $flag = $flagsSystem
  if ($Display) { $flag = $flagsDisplay }

  # Re-spawn detached so the hold survives the calling shell exiting (agent
  # tool calls are one-shot processes). Hard cap = $Hours.
  $child = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-Command',
    "param(`$f,`$h) Add-Type -Namespace Kafeined -Name Power -MemberDefinition '[DllImport(`"kernel32.dll`")] public static extern uint SetThreadExecutionState(uint esFlags);'; [Kafeined.Power]::SetThreadExecutionState(`$f) | Out-Null; Start-Sleep -Seconds (`$h * 3600)",
    "$flag", "$Hours"
  )

  Set-Content -Path $pidFile -Value $child.Id
  Set-Content -Path $metaFile -Value ("started={0} cap={1}h display={2}" -f (Get-Date).ToString('o'), $Hours, [bool]$Display)

  Start-Sleep -Milliseconds 800
  if (Get-Process -Id $child.Id -ErrorAction SilentlyContinue) {
    return $child.Id
  }
  return $null
}

switch ($Command) {

  'status' {
    $p = Get-AlivePid
    if ($p) {
      Write-Output "kafeined: ACTIVE (pid $p, cap ${Hours}h) — machine will not auto-sleep"
      exit 0
    }
    Write-Output "kafeined: inactive"
    exit 1
  }

  'stop' {
    $p = Get-AlivePid
    if ($p) {
      Stop-Process -Id $p -Force -ErrorAction SilentlyContinue
      Write-Output "kafeined: released (killed $p)"
    } else {
      Write-Output "kafeined: nothing to release"
    }
    Remove-Item $pidFile, $metaFile -Force -ErrorAction SilentlyContinue
    exit 0
  }

  'while' {
    if (-not $CmdArgs -or $CmdArgs.Count -eq 0) {
      Write-Output "kafeined: while mode needs a command to run"
      Write-Output "example: kafeined.ps1 while -Hours 4 -- npm run build"
      exit 2
    }

    $p = Get-AlivePid
    if ($p) {
      Write-Output "kafeined: a hold is already active; while mode will reuse it"
    } else {
      $holder = Start-Hold
      if (-not $holder) {
        Write-Output "kafeined: failed to start the keep-awake hold"
        exit 1
      }
      Write-Output "kafeined: holding machine awake while the command runs (pid $holder, cap ${Hours}h)"
    }

    $exe = $CmdArgs[0]
    $rest = @($CmdArgs | Select-Object -Skip 1)
    $rc = 0
    try {
      & $exe @rest
      if ($null -ne $LASTEXITCODE) { $rc = $LASTEXITCODE }
    } finally {
      & $PSCommandPath stop | Out-Null
    }
    if ($rc -eq 0) {
      Write-Output "kafeined: command finished — hold released (☕)"
    } else {
      Write-Output "kafeined: command exited with code $rc — hold released (☕)"
    }
    exit $rc
  }

  default { # start / renew
    $p = Get-AlivePid
    if ($p) {
      if ($Command -eq 'start') {
        Write-Output "kafeined: already active (pid $p, cap ${Hours}h)"
        exit 0
      }
      # renew
      Stop-Process -Id $p -Force -ErrorAction SilentlyContinue
      Start-Sleep -Seconds 1
    }

    $holder = Start-Hold
    if ($holder) {
      Write-Output "kafeined: holding machine awake (pid $holder, cap ${Hours}h)"
      exit 0
    }
    Write-Output "kafeined: failed to start the keep-awake hold"
    exit 1
  }
}
