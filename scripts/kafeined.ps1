# kafeined.ps1 — Windows keep-awake holder for AI agent sessions.
# Uses the Win32 SetThreadExecutionState API (no admin rights, no downloads).
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File kafeined.ps1 start  [-Display] [-Hours 6]
#   powershell -NoProfile -ExecutionPolicy Bypass -File kafeined.ps1 stop
#   powershell -NoProfile -ExecutionPolicy Bypass -File kafeined.ps1 status
#   powershell -NoProfile -ExecutionPolicy Bypass -File kafeined.ps1 renew

param(
  [Parameter(Position = 0)]
  [ValidateSet('start', 'stop', 'status', 'renew')]
  [string]$Command = 'status',

  [switch]$Display,

  [int]$Hours = 6
)

$ErrorActionPreference = 'SilentlyContinue'

$dir = Join-Path $env:TEMP 'kafeined'
$pidFile = Join-Path $dir 'pid'
$logFile = Join-Path $dir 'log'
$metaFile = Join-Path $dir 'meta'
$scriptPath = $PSCommandPath

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

Add-Type -Namespace Kafeined -Name Power -MemberDefinition '
[DllImport("kernel32.dll")]
public static extern uint SetThreadExecutionState(uint esFlags);
' -ErrorAction SilentlyContinue

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

    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Remove-Item $pidFile, $metaFile -Force -ErrorAction SilentlyContinue

    # Re-spawn ourselves detached so the hold survives the calling shell
    # exiting (agent tool calls are one-shot processes).
    $flag = $flagsSystem
    if ($Display) { $flag = $flagsDisplay }

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
      Write-Output "kafeined: holding machine awake (pid $($child.Id), cap ${Hours}h)"
      exit 0
    }
    Write-Output "kafeined: failed to start the keep-awake hold"
    exit 1
  }
}
