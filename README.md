# kai

Markdown kanban for a git repo. Items are files with YAML frontmatter; the board is driven only through this CLI. Agents must not scan `.kai/` — they call `./kai`.

**This repo is the CLI.** Companion UI (optional): [kaitui](https://github.com/atagulalan/kaitui) (or your fork).

## Install into a project

Fastest (via [kaijou](https://github.com/atagulalan/kaijou)):

```bash
cd /path/to/your-project
npx kaijou                 # copies ./kai + init if .kai/ missing
./kai add --author user --title "First card" --priority 10
```

Manual:

```bash
cp kai /path/to/your-project/kai
chmod +x /path/to/your-project/kai
cd /path/to/your-project
./kai init MyProj          # prefix for ids (default: Kai)
./kai add --author user --title "First card" --priority 10
./kai list
```

After `init`:

```
./kai                 # this script
.kai/
  config              # prefix, columns, workflow, agents
  BOARD.md            # generated overview (do not hand-edit)
  items/*.md          # cards
  images/             # assets from ./kai image
```

## Commands

| Command | Purpose |
|---------|---------|
| `init [prefix]` | Create `.kai/` skeleton |
| `list [--all] [--column C] [--details]` | Show columns (default: top N per column) |
| `ready [--all] [--details]` | Items whose `depends` are all done |
| `show <id>` | Full item + ready/blocked note |
| `add --author user\|ai --title "…" [opts]` | Create next id (`U` = user, `A` = ai) |
| `depend <id> <dep-id>` / `undepend …` | Manage dependencies |
| `move <id> <column>` | Move if workflow allows |
| `priority <id> <n>` | Set priority (higher sorts first) |
| `done <id>` | Move to `done_column` |
| `image <path>` | Copy into `.kai/images/`, print relative path |
| `board` | Regenerate and print `BOARD.md` |
| `workflow` | Columns + legal transitions |
| `tui` | Launch **kaitui** if installed beside this repo |
| `help` | Usage |

Examples:

```bash
./kai add --author ai --title "Ship TUI" --priority 20 --depends MyProjU001
./kai move MyProjA001 doing
./kai ready --details
./kai board
```

`add` options: `--column`, `--priority`, `--body`, `--depends id1,id2`.

## Config (`.kai/config`)

```
prefix=MyProj
columns=todo,doing,done
workflow=todo>doing|doing>todo,done|done>todo
start_column=todo
done_column=done
default_limit=5
deps_mode=soft
agent=codex
agent.codex=codex exec -m gpt-5.6-luna -c model_reasoning_effort="low" -s workspace-write {prompt}
agent.cursor=cursor agent -p --force {prompt}
agent.claude=claude -p {prompt}
```

| Key | Meaning |
|-----|---------|
| `prefix` | Id prefix (`MyProjU001`, `MyProjA001`, …) |
| `columns` | Ordered column names |
| `workflow` | `from>to1,to2\|from2>to3` (empty after `>` = no exits) |
| `start_column` / `done_column` | Defaults for new cards / `done` |
| `default_limit` | Rows per column in `list` without `--all` |
| `deps_mode` | `soft` = annotate only; `hard` = blocked items may only move to `start_column` |
| `agent` | Fixed TUI agent name, or `none` (hides prompt) |
| `agent.<name>` | Shell template; `{prompt}` and optional `{id}` |

## Workflow and depends

- Illegal moves are rejected; check `./kai workflow` before inventing transitions.
- `depends: IdA,IdB` — item is **ready** when every dep is in `done_column`.
- `./kai ready` lists parallelizable work.
- Soft mode: deps are notes. Hard mode: blocked cards cannot leave toward mid/done columns except returning to start.

## Item format

`.kai/items/<id>.md`:

```markdown
---
id: MyProjA001
column: todo
priority: 20
title: Ship TUI
created: 2026-10-08
author: ai
depends: MyProjU001
---

Optional body…
```

Ids: `{prefix}{U|A}{###}` — `U` from `--author user`, `A` from `--author ai`, numeric suffix incremental per letter.

## Cursor skill

Copy [`.cursor/skills/kai/SKILL.md`](.cursor/skills/kai/SKILL.md) into a project’s `.cursor/skills/kai/` so agents use `./kai` only and never index `.kai/`.

## kaitui (optional)

```bash
npx kaitui
```

Or place a built binary next to `./kai` and run `./kai tui`. See [kaitui](https://github.com/atagulalan/kaitui).

## Tests

```bash
make test
# or: ./tests/kai_test.sh
```

## License

Same as the parent project license unless this repo ships its own `LICENSE`.
