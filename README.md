# ☕ kafeined

**A universal "keep-awake" skill for AI coding agents.** When you mention
`/kafeined` (or `@kafeined`) in a task, your agent holds the machine awake —
no auto-sleep, no idle logout, no shutdown — until the job is done, then
releases the hold automatically.

Works with **built-in OS facilities only**, nothing to install:

| OS | Mechanism |
|---|---|
| macOS | `caffeinate` (idle-sleep assertion, self-expiring) |
| Windows | PowerShell + Win32 `SetThreadExecutionState` |
| Linux | `systemd-inhibit` (desktop fallback: `gnome-session-inhibit`) |

## Install

```bash
npx skills add deanyouknow/kafeined
```

The installer asks which agent(s) to install for (Claude Code, Cursor,
OpenCode, Codex, ...) and copies the skill into that agent's skills directory.

## Usage

Mention the skill anywhere in your task:

```
/kafeined please refactor the auth module and run all the tests
```

or

```
@kafeined migrate the database, then update the docs
```

The agent will:

1. **Before working:** run `kafeined start` → a tiny background holder keeps
   the machine awake (system only; the screen may still sleep).
2. **During work:** renew the hold if the session runs long.
3. **When done:** run `kafeined stop` → the hold is released — even if the
   task failed or was interrupted.

### Safety by design

- **Hard cap:** the hold self-expires after **6 hours** (configurable with
  `--hours N`). A crashed agent can never keep your machine awake forever.
- **Idempotent:** `start` twice is harmless; `stop` without a hold is safe.
- **System-only by default:** the screen is free to lock and turn off.
  Pass `--display` (or ask the agent) to keep the screen on too.
- **No admin rights, no downloads, no daemons.**

## Manual control

You don't need the agent — run it yourself:

```bash
# macOS / Linux / Windows (Git Bash)
bash scripts/kafeined.sh start            # hold awake (6h cap)
bash scripts/kafeined.sh start --hours 2  # custom cap
bash scripts/kafeined.sh status           # is it holding?
bash scripts/kafeined.sh stop             # release

# Windows (PowerShell)
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/kafeined.ps1 start
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/kafeined.ps1 status
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/kafeined.ps1 stop
```

## How it works

`kafeined` spawns a small **holder process** that owns an OS-level
"system required" execution assertion, independent of any single command. That
fits how agents actually work — many short tool calls instead of one long
process — unlike wrapper-style tools such as `caffeinate <command>`. The
holder writes a pid file to `${TMPDIR:-/tmp}/kafeined/`, and `stop` kills it.
The assertion expires on its own at the hard cap as a last-resort safety net.

## Notes & limits

- Closing the laptop lid or a critically low battery can still suspend the
  machine — no userspace program can prevent that.
- On macOS the default (`-i`) prevents **system** idle sleep; pass
  `--display` to also keep the screen awake (`-id`).
- On Linux without systemd, logind idle actions may not be covered; the
  scripts use `gnome-session-inhibit` when available for desktop sessions.

## License

MIT — see [LICENSE](LICENSE).
