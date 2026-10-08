---
name: kai
description: >-
  Manages the project markdown kanban board via ./kai. Use when
  creating, listing, moving, prioritizing, or completing tasks; when the user
  mentions kai, kanban, board, todo, doing, done, depends, ready, workflow, tui,
  kaitui, or project tasks; or when an agent needs to track parallel or blocked work.
  Never scan .kai/ directly — only use the CLI.
---

# Kai board

## Hard rule

**Never** scan, index, glob, or explore `.kai/` (items, images, config, BOARD.md).
That tree is task state, not source to discover. Use only the CLI (`./kai`).

## CLI

```bash
./kai workflow
./kai list [--all] [--column C] [--details]
./kai ready [--all] [--details]
./kai show <id>
./kai add --author ai --title "…" [--depends id1,id2]
./kai depend <id> <dep-id> / undepend / move / priority / done / image / board
./kai tui                          # mouse-first board (needs kaitui binary)
```

## Columns + workflow

```
columns=todo,doing,done
workflow=todo>doing|doing>todo,done|done>todo
start_column=todo
done_column=done
deps_mode=soft
```

- Never invent illegal transitions; check `./kai workflow`.
- `deps_mode=hard`: blocked items may only move to `start_column`.

## TUI agents (config)

```
agent=codex
agent.codex=codex exec -m gpt-5.6-luna -c model_reasoning_effort="low" -s workspace-write {prompt}
```

- Agent is **fixed in config** (not switched in the TUI). `agent=none` hides the prompt.
- Named agents inject a preamble: use `./kai` only; never scan `.kai/`.
- Templates use `{prompt}` and optional `{id}` (selected card(s), comma-separated).
- TUI: left-click detail · right-click multi-select · Enter asks agent · `/refresh` `/quit` `/clear` `/help`; agent sees all selected ids.

## Depends + parallel

- `depends: IdA,IdB` — ready when every dep is in `done_column`.
- Before taking work: `./kai ready`.

## Rules for agents

- Always `--author ai` when adding items.
- Attach images with `./kai image` only.
- Do not hand-edit `BOARD.md`.

## Tests (kai CLI repo)

```bash
./tests/kai_test.sh
```
