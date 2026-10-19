# tf: task flow

*T'fuck task tracker for millenial vibecoders ~~enjoying~~ suffering from OCD...*

Agents control plane: a task list your coding agent works through, one item at a time. It's a
single Markdown file in your repo, and it works with Claude Code and Codex.

While the agent works, you plan the next moves.

- **Everything in one file.** `tf.md` holds what to do next, the backlog, what's done and why.
- **Scoped and controllable.** The agent only takes the first open item under `# todo`. You decide
  what goes there; `# backlog` is never touched.
- **Minimal setup.** No server, no database, no CLI: one folder and two lines of config. Any model
  that can read files can follow it.
- **Explicit and configurable per repo.** The format is written in the file itself; your own tags go
  in `# tags`.

## Install

From your project root:

```bash
git clone https://github.com/blitzarx1/tf .tf && .tf/install.sh
```

`install.sh`:
- turns `.tf` into a plain folder by deleting `.tf/.git`;
- links `.tf/skill` as the `tf` skill (`.claude/skills/tf`, `.agents/skills/tf`);
- adds `@.tf/skill/AGENTS.md` to `CLAUDE.md` and a pointer line to `AGENTS.md`;
- deletes `README.md` and itself from `.tf`, leaving `tf.md`, `update.sh`, `VERSION` and `skill/`;
- gitignores `.tf/` and the links, since the task list is personal. Remove those lines to share it.

Already have a task list (a `TODO.md`, a folder of notes, an issues export)? Type
`tf migrate <path>`: the agent reads it, shows what goes where, and fills `tf.md` once you
agree. Your old files stay as they are.

## Use

| You type | The agent |
|---|---|
| `tf` | re-reads `.tf/tf.md` and works the first open `# todo` item: answers a question, plans and then implements a task or bug, splits an epic into tasks. Then it moves the item to `# done` with a summary. |
| `tf <n>` | works the first `<n>` open `# todo` items together: one plan covering all of them, one approval, then implements them in order and closes each. |
| `tf migrate <path>` | reads your old tracker (a file or a folder), shows what goes to `# todo`, `# backlog` and `# done`, and appends the tasks to `tf.md` once you agree. Open tasks it can't place go to `# backlog`. |

Edit `tf.md` yourself whenever you like. Add new items to `# todo` or `# backlog`, move them
between the two, and add `D : ` descriptions and `C : ` comments. The agent re-reads the file
every time.

Add your own commands under `# commands` in `tf.md` (the built-in ones are in `skill/base.md`), then type
them like the built-ins.

## Update

```bash
.tf/update.sh
```

This replaces `skill/`, `VERSION` and `update.sh` with the latest versions and prints the version
change. It never touches `tf.md`.

## Files

| File | What |
|---|---|
| `tf.md` | Your tasks, tags and commands |
| `skill/base.md` | The format, and the built-in tags and commands with their full definitions (tf's; replaced by updates) |
| `skill/AGENTS.md` | Points the agent to `skill/base.md` and `tf.md` |
| `skill/SKILL.md` | The `tf` skill, linked as `.claude/skills/tf` and `.agents/skills/tf` |
| `VERSION` | Installed tf version: the release tag, then the commit hash (written by install and update) |
| `update.sh` | Updates `skill/`, `VERSION` and itself |
| `install.sh` | Setup; deletes itself |
