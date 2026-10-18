# tf: task flow

A task list your coding agent works through, one item at a time. It's a single Markdown file in
your repo, and it works with Claude Code and Codex.

- **Everything in one file.** `tf.md` holds what to do next, the backlog, what's done and why.
- **Scoped and controllable.** The agent only takes the first open item under `# todo`. You decide
  what goes there; `# backlog` is never touched.
- **Minimal setup.** No server, no database, no CLI: one folder and two lines of config. Any model
  that can read files can follow it.
- **Explicit and configurable per repo.** The format is written in the file itself; your own tags go
  in `# custom tags`.

## Install

From your project root:

```bash
git clone https://github.com/blitzarx1/tf .tf && .tf/install.sh
```

`install.sh`:
- turns `.tf` into a plain folder by deleting `.tf/.git`;
- links it as the `tf` skill (`.claude/skills/tf`, `.agents/skills/tf`);
- adds `@.tf/AGENTS.md` to `CLAUDE.md` and a pointer line to `AGENTS.md`;
- gitignores `.tf/` and the links, since the task list is personal. Remove those lines to share it.

## Use

| You type | The agent |
|---|---|
| `tf` | re-reads `.tf/tf.md` and works the first open `# todo` item: answers a question, plans and then implements a task or bug, splits an epic into tasks. Then it moves the item to `# done` with a summary. |
| `tf new <title>` | adds `- [ ] <title>` at the top of `# backlog`. |

Edit `tf.md` yourself whenever you like. Move items into `# todo`, and add `D : ` descriptions and
`C : ` comments. The agent re-reads the file every time.

## Update

```bash
.tf/update.sh
```

This replaces `AGENTS.md`, `SKILL.md`, `update.sh` and the `# info` section of `tf.md` with the
latest versions. It never touches `# todo`, `# backlog`, `# done` or `# custom tags`. The previous
file is kept as `.tf/tf.md.bak`.

## Files

| File | What |
|---|---|
| `tf.md` | The task file: your sections, then `# info` with the format |
| `AGENTS.md` | The rules the agent follows |
| `SKILL.md` | The `tf` command |
| `install.sh`, `update.sh` | Setup (`install.sh` deletes itself) and updates |
