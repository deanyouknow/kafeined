# ☕ kafeined

> Your machine kept falling asleep in the middle of long AI agent runs?
> Mine too. This fixes it.

**kafeined** is a keep-awake guard for AI coding agents. Mention `/kafeined`
in your prompt and the agent holds your machine awake *before* it starts
working — no auto-sleep, no idle logout — then releases the hold when the
task is done.

```
you: /kafeined 2h migrate the db, fix the tests, update the docs
agent: ☕ holding machine awake (2h cap) → *does the work* → ☕ hold released
```

## Install

```bash
npx skills add deanyouknow/kafeined
```

Works with any agent that supports the [skills standard](https://agentskills.io)
(Claude Code, Cursor, Codex, OpenCode, Freebuff, ...).

Claude Code user? This repo is also a plugin marketplace:

```
/plugin marketplace add deanyouknow/kafeined
/plugin install kafeined@kafeined
```

## How it works

There is no universal "don't sleep" command, but every OS already ships one —
so kafeined just uses whatever your machine has. **Nothing to install, no
admin rights, no third-party anything.**

| OS | Mechanism |
|---|---|
| macOS | `caffeinate` |
| Windows | PowerShell + Win32 `SetThreadExecutionState` |
| Linux | `systemd-inhibit` |

When triggered, the agent spawns a tiny **holder process** that owns an
OS-level "stay awake" assertion, independent of any single command — that fits
how agents work (dozens of short tool calls). When the task ends, the agent
kills the holder and confirms with `☕ hold released`.

**Safety by design:** the hold hard-caps at 6 hours (configurable, even
per-prompt: `/kafeined 2h ...`) so a crashed agent can never keep your machine
awake forever, and a `while` mode auto-releases the moment a single command
finishes.

## Repository layout

```
skills/kafeined/        ← the actual skill (SKILL.md + scripts + full docs)
.claude-plugin/         ← makes this repo a Claude Code plugin marketplace
```

📖 **Full documentation, usage examples, and manual usage:**
[skills/kafeined/README.md](skills/kafeined/README.md)

## License

MIT — see [skills/kafeined/LICENSE](skills/kafeined/LICENSE).
