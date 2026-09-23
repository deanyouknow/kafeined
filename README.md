# ☕ kafeined

> My machine kept falling asleep in the middle of long AI agent runs — builds,
> migrations, that one refactor that takes 40 minutes. So I fixed it. Sharing
> it here in case your machine betrays you the same way.

**kafeined** is a tiny skill for AI coding agents. Drop `/kafeined` (or
`@kafeined`) into your prompt and the agent holds your machine awake *before*
it starts working, then releases the hold when it's done. No auto-sleep, no
idle logout, no "display went to sleep" mid-task.

```
you: /kafeined migrate the db, fix the failing tests, then update the docs
agent: ☕ holding machine awake (6h cap) → *does the work* → ☕ hold released
```

## Install

```bash
npx skills add deanyouknow/kafeined
```

The installer asks which agent(s) to install for (Claude Code, Cursor,
OpenCode, Codex, Freebuff, ...) and copies the skill over. That's it.

## Usage

Just mention it anywhere in your task:

```
/kafeined please refactor the auth module and run all the tests
@kafeined do a full dependency upgrade and tell me what breaks
```

The agent will:

1. **Before working:** start a tiny background holder that keeps the machine
   awake (system only — your screen can still sleep normally).
2. **During work:** renew the hold if the job runs long.
3. **When done:** release the hold — even if the task failed or you hit Esc
   halfway through.

Want the screen kept on too (e.g. you're watching the agent work)? Say so:
`/kafeined --display ...` or just ask in plain words.

## Why it works this way

There's no universal "don't sleep" command, but every OS already ships one,
so kafeined just uses whatever your machine has — **nothing to install, no
admin rights, no third-party anything**:

| OS | What it uses |
|---|---|
| macOS | `caffeinate` |
| Windows | PowerShell + Win32 `SetThreadExecutionState` |
| Linux | `systemd-inhibit` (or `gnome-session-inhibit` on desktops) |

Instead of wrapping every command, it spawns one small **holder process** with
a pid file under `${TMPDIR:-/tmp}/kafeined/`. That fits how agents actually
work — dozens of short tool calls instead of one long command.

## Safety

I didn't want a bug keeping my laptop awake overnight, so:

- **Hard cap:** the hold auto-expires after **6 hours** (`--hours N` to
  change). A crashed agent can't hold your machine hostage.
- **Idempotent:** `start` twice is harmless, `stop` with nothing held is safe.
- **Always releases:** success, failure, or interrupt — the skill tells the
  agent to stop the hold as its final step.
- **System-only by default:** your screen locks and dims like normal.

## Without an agent

It's just a script, run it yourself:

```bash
bash scripts/kafeined.sh start            # hold awake (6h cap)
bash scripts/kafeined.sh start --hours 2  # custom cap
bash scripts/kafeined.sh status           # is it holding?
bash scripts/kafeined.sh stop             # release

# Windows (PowerShell)
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/kafeined.ps1 start
```

## Testing

No CI here (it's two scripts, not a startup). If you want to check it works
on your machine:

```bash
bash scripts/smoke-test.sh
```

## Known limits (honesty section)

- Closing the laptop lid or a critically low battery can still suspend the
  machine — no program can stop that, and I'm not going to pretend otherwise.
- On Linux without systemd, some idle actions may not be covered.

## License

MIT — take it, break it, fork it.
