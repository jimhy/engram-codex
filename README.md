# engram-codex

> [Engram](https://github.com/jimhy/engram) — brain-inspired long-term memory — for **Codex**. **Tiered, self-forgetting, auto-consolidating.** Injects relevant memory at session start, consolidates at session end, and recalls on demand via a skill. One Rust binary, zero deps, no vector DB, **memory store shared with the Claude Code version**.

**English** | [中文](./README.zh-CN.md)

---

## Why

Most "memory" for AI agents dumps everything into a vector database and stuffs chunks back into the prompt — token-heavy, noisy, and awkward to actually use. Engram takes the opposite approach, modeled on how human memory works:

- **Remember the gist, not the details.** Each memory is a one-line *cue* + a *pointer* to the ground truth (`file:line`, a doc, a URL). You recall the cue, then follow the pointer when you need detail — **verification, not reconstruction**.
- **Store the complement of your artifacts.** Your code is already the perfect detail store (`grep` finds it). Engram only stores what the code *doesn't* capture: intent, decisions, dead-ends, the "why".
- **Forget the noise.** Memories decay over time (ACT-R-style) unless reinforced by real use; low-value ones demote out of the hot set. *Forgetting = demotion, not deletion.*

The result: a tiny, always-relevant **hot index** in your context, plus a much larger searchable **cold store** — **without a vector database**.

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
| `Stop` hook | Spins up an **independent** headless `codex exec` reviewer that consolidates only the **increment since the last watermark** (writes new memories, promotes/demotes, supersedes, merges) |
| engram **skill** | recall-first: when asked "have we handled X / what's the project / what's left to do", the agent recalls from memory before scanning the code |

The memory store is **shared with the Claude Code version** (`~/.engram/general.redb` + per-project `<project>/.engram/engram.redb`), so memories written from Codex and Claude Code are common to both.

## How it works

Memory is **tiered**, like human memory:

| Tier | Role | Decay |
|------|------|-------|
| **L1** | "subconscious" — core identity / preferences | almost never (high floor) |
| **L2** | important | slow |
| **L3** | ordinary | medium |
| **L4** | per-project, lives in `<project>/.engram/engram.redb` | scoped to the project, located via the `.engram/` anchor |

- **Activation = importance + recency + frequency** (ACT-R base-level), with a per-tier floor so L1 stays put.
- **Climbing requires earned activation; falling is cushioned** by the floor and a grace period — new and important memories aren't killed early.
- **Consolidation** runs at session end via an *independent* `codex exec` reviewer reading the transcript, so the judgment of "what was actually used / worth keeping" isn't self-serving.

### What goes in each tier

A memory is only worth keeping if it **can't be cheaply recovered** from the code/docs/git — engram stores the *complement* of your artifacts (intent, the "why", dead-ends, decisions, open loops), distilled into a one-line cue + a pointer to the ground truth.

**General — cross-project, in the shared store (`~/.engram/general.redb`):**
- **L1** — core identity & always-on global rules: who you are, how to address you, language, hard global conventions. Tiny, almost never forgotten.
- **L2** — important reusable knowledge that holds across projects (a tool gotcha, a durable preference).
- **L3** — ordinary, easily-forgotten general notes.

**Per-project — L4, in that project's store (`<project>/.engram/engram.redb`):**
- **L4.1** — project hard rules: the inviolable conventions / taboos for *this* repo, learned from your "always / never" directives or hard-won corrections. *Not* a copy of AGENTS.md / lint configs (those are auto-loaded artifacts); L4.1 holds what they **don't** say.
- **L4.2** — durable project knowledge: what the project is, its **architecture / module mental-map** (what each part does and why it's split that way — distilled, not an `ls` dump), and settled / debated decisions (what was chosen, what was rejected and why — so a later session won't re-propose a dead option).
- **L4.3** — transient: open loops / hand-off-able work (current progress, what's blocked, next step). Decays fast; superseded once done.

> Golden rule: **store the distilled mental model, never what a single `grep` / `ls` already gives you.** File locations live in the pointer, not the cue.

## Where memory lives

- **Shared** (cross-project L1-3): `~/.engram/general.redb` (auto-created)
- **Per-project** (L4): `<project>/.engram/engram.redb` (travels with the project)

Storage is **[redb](https://github.com/cberner/redb)** (embedded, single-file, ACID) — no server, no external database. These are **the same stores the Claude Code version uses**, so memory is common to both CLIs.

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
