#!/usr/bin/env bash
# kafeined.sh — universal keep-awake runner for AI agent sessions.
# Works on macOS, Linux, and Windows (run from Git Bash / MSYS2, which every
# agent on Windows already provides; it delegates the hold to PowerShell).
#
# Commands:
#   kafeined.sh start  [--display] [--hours N]      hold the machine awake (idempotent)
#   kafeined.sh while  [--display] [--hours N] CMD  hold awake while CMD runs, auto-release
#   kafeined.sh stop                                release the hold (safe if not running)
#   kafeined.sh status                              print status; exit 0 = held, 1 = not
#   kafeined.sh renew                               restart the hold with a fresh timer
#
# Exit codes: 0 ok · 1 not held / failed · 2 usage · 3 unsupported OS
#             while mode also propagates CMD's exit code.
#
# State lives in ${KAFEINED_STATE_DIR:-${TMPDIR:-/tmp}}/kafeined/ so holds are
# scoped per user and never pollute the repo.

set -u

COMMAND="${1:-}"
[ $# -gt 0 ] && shift

# ---------- helpers ----------------------------------------------------------

say() { printf '%s\n' "$*"; }

usage() {
  say "usage: kafeined.sh {start [--display] [--hours N] | while [--display] [--hours N] CMD | stop | status | renew}"
  exit 2
}

battery_note() {
  # Warn when running on battery power; holding a battery machine awake for
  # hours drains it. Best-effort, macOS only — silence everywhere else.
  local s
  s="$(pmset -g batt 2>/dev/null)" || return 0
  case "$s" in
    *"'AC Power'"*) : ;;
    *"AC Power"*) : ;;
    *"Battery Power"*)
      say "kafeined: note — machine is on battery; the hold will drain it faster"
      ;;
  esac
}

# ---------- per-command option parsing ---------------------------------------
# Valid orders: start/while/renew take [--display] [--hours N] [CMD...];
# stop/status take nothing.

case "$COMMAND" in
  start|while|renew)
    DISPLAY_FLAG=0
    KAFEINED_HOURS="${KAFEINED_HOURS:-6}"
    while [ $# -gt 0 ]; do
      case "$1" in
        --display) DISPLAY_FLAG=1 ;;
        --hours)
          if [ $# -lt 2 ]; then
            say "kafeined: --hours requires a value"
            exit 2
          fi
          shift
          case "$1" in
            ''|*[!0-9]*) say "kafeined: --hours must be a positive integer"; exit 2 ;;
          esac
          KAFEINED_HOURS="$1"
          ;;
        -*)
          say "kafeined: unknown option '$1'"
          exit 2
          ;;
        *)
          if [ "$COMMAND" = "while" ]; then
            break   # rest of the args are CMD
          fi
          say "kafeined: unexpected argument '$1'"
          exit 2
          ;;
      esac
      shift
    done
    case "$KAFEINED_HOURS" in
      ''|*[!0-9]*|0) say "kafeined: --hours must be a positive integer"; exit 2 ;;
    esac
    ;;
  stop|status) : ;;
  *) usage ;;
esac

KAFEINED_HOURS="${KAFEINED_HOURS:-6}"
SECONDS_CAP=$((KAFEINED_HOURS * 3600))

# ---------- configuration ----------------------------------------------------

KAFEINED_DIR="${KAFEINED_STATE_DIR:-${TMPDIR:-/tmp}}/kafeined"
KAFEINED_PID_FILE="$KAFEINED_DIR/pid"
KAFEINED_LOG_FILE="$KAFEINED_DIR/log"
KAFEINED_META_FILE="$KAFEINED_DIR/meta"

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

# Cap recorded by the running holder, falling back to the default.
current_cap() {
  local c
  c="$(sed -n 's/.*cap=\([0-9][0-9]*\).*/\1/p' "$KAFEINED_META_FILE" 2>/dev/null)"
  [ -n "$c" ] && { echo "$c"; return; }
  echo "${KAFEINED_HOURS:-6}"
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

# ---------- shared: spawn a holder (used by start and while) ------------------
# Expects DISPLAY_FLAG, KAFEINED_HOURS, SECONDS_CAP set. Sets HOLDER_PID,
# CMD_KIND. Returns non-zero if the holder died immediately.

spawn_holder() {
  mkdir -p "$KAFEINED_DIR" 2>/dev/null
  rm -f "$KAFEINED_PID_FILE" "$KAFEINED_META_FILE" 2>/dev/null
  : > "$KAFEINED_LOG_FILE" 2>/dev/null || KAFEINED_LOG_FILE=/dev/null

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
  kill -0 "$HOLDER_PID" 2>/dev/null
}

# ---------- command: start / renew -------------------------------------------

if [ "$COMMAND" = "start" ] || [ "$COMMAND" = "renew" ]; then
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

  if spawn_holder; then
    battery_note
    say "kafeined: holding machine awake (pid $HOLDER_PID, cap ${KAFEINED_HOURS}h, kind $CMD_KIND)"
    exit 0
  fi
  say "kafeined: failed to start the keep-awake hold (see $KAFEINED_LOG_FILE)"
  rm -f "$KAFEINED_PID_FILE" "$KAFEINED_META_FILE"
  exit 1
fi

# ---------- command: while ---------------------------------------------------
# Hold awake while CMD runs; release automatically when it exits — success,
# failure, or interrupt. The hold is bounded by the cap either way.

if [ $# -eq 0 ]; then
  say "kafeined: while mode needs a command to run"
  say "example: kafeined.sh while --hours 4 -- npm run build"
  exit 2
fi

if alive; then
  say "kafeined: a hold is already active; while mode will reuse it"
else
  spawn_holder || { say "kafeined: failed to start the keep-awake hold (see $KAFEINED_LOG_FILE)"; exit 1; }
  battery_note
  say "kafeined: holding machine awake while the command runs (pid $HOLDER_PID, cap ${KAFEINED_HOURS}h)"
fi

"$@"
RC=$?

"$0" stop >/dev/null 2>&1
case "$RC" in
  0) say "kafeined: command finished — hold released (☕)" ;;
  *) say "kafeined: command exited with code $RC — hold released (☕)" ;;
esac
exit "$RC"
