# engram-codex

> [Engram](https://github.com/jimhy/engram) — brain-inspired long-term memory — for **Codex**. Injects relevant memory at session start, consolidates at session end, and recalls on demand via a skill. One Rust binary, zero deps, **memory store shared with the Claude Code version**.

**English** | [中文](./README.zh-CN.md)

---

## Install

```bash
codex plugin marketplace add jimhy/engram-codex
codex plugin add engram@engram-codex
```

Open `codex`; approve the engram hooks when prompted. Uninstall: `codex plugin remove engram@engram-codex`.

## Update

```bash
codex plugin marketplace upgrade engram-codex   # pull the latest from GitHub
codex plugin add engram@engram-codex            # reinstall from the refreshed snapshot
```

`marketplace upgrade` refreshes the git snapshot, then `plugin add` reinstalls from it — this refreshes the cached content **even when the version number is unchanged** (no need to `remove` first).

## What you get

| codex mechanism | what it does |
|---|---|
| `SessionStart` hook | Injects the **hot index** (relevant memory) into context via `engram hot-index` → `additionalContext`; also **catches up** any consolidation a previous session didn't finish |
| `Stop` hook | Spins up a headless `codex exec` reviewer that consolidates only the **increment since the last watermark** (writes new memories, promotes/demotes, supersedes, merges) |
| engram **skill** | recall-first: when asked "have we handled X / what's the project / what's left to do", the agent recalls from memory before scanning the code |

The memory store is **shared with the Claude Code version** (`~/.engram/general.redb` + per-project `<project>/.engram/engram.redb`), so memories written from Codex and Claude Code are common to both.

## How it works

Same engine as [engram](https://github.com/jimhy/engram) — tiered, ACT-R-style activation, self-forgetting (forgetting = demotion, not deletion). See the main project for the full model.

| Tier | Role |
|---|---|
| **L1** | "subconscious" — core identity / global preferences (almost never forgotten) |
| **L2** | important, cross-project |
| **L3** | ordinary general notes |
| **L4** | per-project, in `<project>/.engram/engram.redb`, located via the `.engram/` anchor |

## Structure

```
.agents/plugins/marketplace.json   codex marketplace manifest (source: ./plugin)
plugin/                            the codex plugin
  .codex-plugin/plugin.json        manifest
  hooks/hooks.json                 SessionStart/Stop, ${PLUGIN_ROOT}-relative
  scripts/                         codex-{session-start,stop-review,launch-reviewer}.{ps1,sh}
                                   + reviewer-prompt.md
  skills/engram/SKILL.md           engram agent interface + judgment rubric
  bin/                             four-platform engine binaries
```

## Platforms

- **Windows**: `.ps1` (tested)
- **macOS / Linux**: `.sh` (`hooks.json` routes via `command` / `commandWindows`)

## Differences from the Claude Code adapter

- **`Stop` instead of `SessionEnd`**: codex has no `SessionEnd`; `Stop` fires every turn, so a review only runs when the increment ≥ `ENGRAM_REVIEW_MIN_LINES` (default 40) — otherwise the pending marker is left for the next `SessionStart` catch-up.
- **`Stop` stdout must be valid JSON**: the hook always returns `{}`.
- **Reviewer via `codex exec`** (not `claude -p`), with `ENGRAM_REVIEWER=1` guarding against recursion.
- Injection / review hooks fire only in the **interactive `codex` TUI** — `codex exec` (non-interactive) does not trigger lifecycle hooks.

## Configuration

- `ENGRAM_REVIEW_MIN_LINES` — transcript-line increment needed to trigger a review (default `40`).
- `ENGRAM_REVIEWER_CODEX` — the codex executable the reviewer launches (default `codex`).
- `ENGRAM_REVIEWER_MODEL` — model override for the headless reviewer.

## License

MIT
