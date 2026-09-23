#!/usr/bin/env bash
# kafeined.sh — universal keep-awake runner for AI agent sessions.
# Works on macOS, Linux, and Windows (run from Git Bash / MSYS2, which every
# agent on Windows already provides; it delegates the hold to PowerShell).
#
# Commands:
#   kafeined.sh start [--display] [--hours N]   hold the machine awake (idempotent)
#   kafeined.sh stop                            release the hold (safe if not running)
#   kafeined.sh status                          print status; exit 0 = held, 1 = not
#   kafeined.sh renew                           restart the hold with a fresh timer
#
# Exit codes: 0 ok · 1 not held / failed · 2 usage · 3 unsupported OS
#
# State lives in ${KAFEINED_STATE_DIR:-${TMPDIR:-/tmp}}/kafeined/ so holds are
# scoped per user and never pollute the repo.

set -u

COMMAND="${1:-}"
[ $# -gt 0 ] && shift

# ---------- configuration ----------------------------------------------------

KAFEINED_DIR="${KAFEINED_STATE_DIR:-${TMPDIR:-/tmp}}/kafeined"
KAFEINED_PID_FILE="$KAFEINED_DIR/pid"
KAFEINED_LOG_FILE="$KAFEINED_DIR/log"
KAFEINED_META_FILE="$KAFEINED_DIR/meta"
KAFEINED_HOURS="${KAFEINED_HOURS:-6}"   # hard cap so a crashed agent can never
                                        # keep the machine awake forever
DISPLAY_FLAG=0
while [ $# -gt 0 ]; do
  case "$1" in
    --display) DISPLAY_FLAG=1 ;;
    --hours)
      if [ $# -lt 2 ]; then
        printf 'kafeined: --hours requires a value\n'
        exit 2
      fi
      shift
      KAFEINED_HOURS="$1"
      ;;
  esac
  shift
done

# ---------- helpers ----------------------------------------------------------

say() { printf '%s\n' "$*"; }

on_windows() {
  [ -n "${WINDIR:-}" ] || uname -s | grep -qi mingw
}

alive() {
  [ -f "$KAFEINED_PID_FILE" ] || return 1
  kill -0 "$(cat "$KAFEINED_PID_FILE" 2>/dev/null)" 2>/dev/null
}

# Stop the detached PowerShell holder tree on Windows (orphan safety net).
windows_cleanup() {
  powershell.exe -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { \$_.CommandLine -match 'kafeined-hold' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue }" >/dev/null 2>&1
}

case "$KAFEINED_HOURS" in ''|*[!0-9]*) say "kafeined: --hours must be a positive integer"; exit 2 ;; esac
SECONDS_CAP=$((KAFEINED_HOURS * 3600))

# Cap recorded by the running holder, falling back to the default.
current_cap() {
  local c
  c="$(sed -n 's/.*cap=\([0-9][0-9]*\).*/\1/p' "$KAFEINED_META_FILE" 2>/dev/null)"
  [ -n "$c" ] && { echo "$c"; return; }
  echo "$KAFEINED_HOURS"
}

# ---------- command: status --------------------------------------------------

if [ "$COMMAND" = "status" ]; then
  if alive; then
    say "kafeined: ACTIVE (pid $(cat "$KAFEINED_PID_FILE"), cap $(current_cap)h) — machine will not auto-sleep"
    exit 0
  fi
  rm -f "$KAFEINED_PID_FILE" 2>/dev/null
  say "kafeined: inactive"
  exit 1
fi

# ---------- command: stop ----------------------------------------------------

if [ "$COMMAND" = "stop" ]; then
  if alive; then
    PID="$(cat "$KAFEINED_PID_FILE")"
    kill "$PID" 2>/dev/null && say "kafeined: released (killed $PID)"
  else
    say "kafeined: nothing to release"
  fi
  rm -f "$KAFEINED_PID_FILE" "$KAFEINED_META_FILE" 2>/dev/null
  if on_windows; then
    windows_cleanup
  fi
  exit 0
fi

# ---------- command: start / renew -------------------------------------------

if [ "$COMMAND" != "start" ] && [ "$COMMAND" != "renew" ]; then
  say "usage: kafeined.sh {start [--display] [--hours N] | stop | status | renew}"
  exit 2
fi

# Idempotent: already holding.
if alive; then
  if [ "$COMMAND" = "start" ]; then
    say "kafeined: already active (pid $(cat "$KAFEINED_PID_FILE"), cap $(current_cap)h)"
    exit 0
  fi
  # renew = fresh timer
  "$0" stop >/dev/null 2>&1
  sleep 1
fi

mkdir -p "$KAFEINED_DIR" 2>/dev/null
rm -f "$KAFEINED_PID_FILE" "$KAFEINED_META_FILE" 2>/dev/null
: > "$KAFEINED_LOG_FILE" 2>/dev/null || KAFEINED_LOG_FILE=/dev/null

# ---------- spawn the holder --------------------------------------------------

if on_windows; then
  CMD_KIND="powershell"
  PS_FLAGS=0x80000001                       # ES_CONTINUOUS | ES_SYSTEM_REQUIRED
  [ "$DISPLAY_FLAG" = "1" ] && PS_FLAGS=0x80000005  # + ES_DISPLAY_REQUIRED
  powershell.exe -NoProfile -Command "
    # kafeined-hold: detached keep-awake holder (hard cap $KAFEINED_HOURS h)
    Add-Type -Namespace Kafeined -Name Power -MemberDefinition '[DllImport(\"kernel32.dll\")] public static extern uint SetThreadExecutionState(uint esFlags);'
    [Kafeined.Power]::SetThreadExecutionState($PS_FLAGS) | Out-Null
    Start-Sleep -Seconds $SECONDS_CAP
  " >"$KAFEINED_LOG_FILE" 2>&1 &
  HOLDER_PID=$!
else
  OS="$(uname -s)"
  if [ "$OS" = "Darwin" ]; then
    CMD_KIND="caffeinate"
    if [ "$DISPLAY_FLAG" = "1" ]; then
      caffeinate -id -t "$SECONDS_CAP" >"$KAFEINED_LOG_FILE" 2>&1 &
    else
      caffeinate -i -t "$SECONDS_CAP" >"$KAFEINED_LOG_FILE" 2>&1 &
    fi
  elif [ "$OS" = "Linux" ]; then
    if [ "$DISPLAY_FLAG" = "1" ] && command -v gnome-session-inhibit >/dev/null 2>&1; then
      CMD_KIND="gnome-session-inhibit"
      gnome-session-inhibit --inhibit 'suspend:idle' --inhibit-only sleep "$SECONDS_CAP" >"$KAFEINED_LOG_FILE" 2>&1 &
    else
      CMD_KIND="systemd-inhibit"
      systemd-inhibit --what='sleep:idle' sleep "$SECONDS_CAP" >"$KAFEINED_LOG_FILE" 2>&1 &
    fi
  else
    say "kafeined: unsupported OS '$OS'"
    exit 3
  fi
fi

HOLDER_PID=$!
echo "$HOLDER_PID" > "$KAFEINED_PID_FILE"
printf 'started=%s cap=%s kind=%s display=%s\n' \
  "$(date +%s)" "$KAFEINED_HOURS" "$CMD_KIND" "$DISPLAY_FLAG" > "$KAFEINED_META_FILE"

sleep 1
if ! kill -0 "$HOLDER_PID" 2>/dev/null; then
  say "kafeined: failed to start the keep-awake hold (see $KAFEINED_LOG_FILE)"
  rm -f "$KAFEINED_PID_FILE" "$KAFEINED_META_FILE"
  exit 1
fi

say "kafeined: holding machine awake (pid $HOLDER_PID, cap ${KAFEINED_HOURS}h, kind $CMD_KIND)"
exit 0
