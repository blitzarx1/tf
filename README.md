# tf: task flow

*T'fuck task tracker for millenial vibecoders ~~enjoying~~ suffering from OCD...*

A task list your coding agent works through. It's a single `.tfmd` file
in your repo, with skills for Claude and Codex.

Control plane for your llm: while the agent works, you plan the next moves.

## Why

- **Code-first.** One plain-text file in your repo. It reads well in any editor, diffs cleanly.
  The format is written down in `skill/base.md`, not hidden in a tool.
- **You control the llm.** The agent takes only the first open item under `# todo`, plans before
  it changes anything and asks about what the task leaves open. `# backlog` is never touched.
- **Human-first.** You write tasks in your own words; the agent records what it did and why.
  Commit `tasks.tfmd` and its git log is your task history.
- **Minimal setup.** No server, no database, no CLI: one folder and two lines of config. Any model
  that can read files can follow it. Your own tags and commands go in `tasks.tfmd`.

## Install

From your project root:

```bash
git clone https://github.com/blitzarx1/tf .tf && .tf/install.sh
```

`install.sh`:
- turns `.tf` into a plain folder by deleting `.tf/.git`;
- links `.tf/skill` as the `tf` skill (`.claude/skills/tf`, `.agents/skills/tf`);
- adds `@.tf/skill/AGENTS.md` to `CLAUDE.md` and a pointer line to `AGENTS.md`;
- deletes `README.md` and itself from `.tf`, leaving `tasks.tfmd`, `update.sh`, `VERSION` and `skill/`.

To keep the task list private, add `.tf/`, `.claude/skills/tf` and `.agents/skills/tf` to
`.gitignore`.

Already have a task list (a `TODO.md`, a folder of notes, an issues export)? Type
`tf migrate <path>`: the agent reads it, shows what goes where, and fills `tasks.tfmd` once you
agree. Your old files stay as they are.

## Use

| You type | The agent |
|---|---|
| `tf` | re-reads `.tf/tasks.tfmd` and works the first open `# todo` item: answers a question, plans and then implements a task or bug, or asks you questions and splits an epic into tasks. Then it moves the item to `# done` with a summary. |
| `tf <n>` | works the first `<n>` open `# todo` items together: one plan covering all of them, one approval, then implements them in order and closes each. |
| `tf migrate <path>` | reads your old tracker (a file or a folder), shows what goes to `# todo`, `# backlog` and `# done`, and appends the tasks to `tasks.tfmd` once you agree. Open tasks it can't place go to `# backlog`. |

Edit `tasks.tfmd` yourself whenever you like. Add new items to `# todo` or `# backlog`, move them
between the two, and add `D : ` descriptions and `C : ` comments. The agent re-reads the file
every time.

Add your own commands under `# commands` in `tasks.tfmd` (the built-in ones are in `skill/base.md`), then type
them like the built-ins.

## Example

You write a task in `# todo`:

```
- [ ] login redirect drops the return url
    ! 80
    : b

  D : After logging in from /settings the user lands on /. Keep the page they came from.
```

You type `tf`. The agent finds the cause, shows a plan, you approve, it fixes the bug and moves
the task to `# done`:

```
- [x] login redirect drops the return url
    ! 80
    : b

  D : After logging in from /settings the user lands on /. Keep the page they came from.

  C : Root cause: the auth callback ignored `next`. It now checks `next` against the site
      origin and redirects there; added a test for /settings. 3f9c2a1
```

`! 80` is the priority (0-100, default 50) and `: b` the tags (`b` is a bug). A task can also carry
an id, `. 1792321201`: a unix timestamp in UTC (here 2026-10-18T11:00:01Z). Header lines go in the
order id, priority, type, tags. A title is one sentence that starts in lowercase. The full format
is in `skill/base.md`.

## Update

```bash
.tf/update.sh
```

This replaces `skill/`, `VERSION` and `update.sh` with the latest versions and prints the version
change. It never touches `tasks.tfmd`.

## Emacs

`emacs/tf-ts-mode.el` is a major mode for `.tfmd` files (needs the `tree-sitter-tfmd` grammar).
Keys, all under `C-c C-`:

| Key | Does |
|---|---|
| `n` / `p` | next / previous task |
| `t` | new task below the current one, with an id and priority 50 |
| `h` / `l` | raise / lower the priority of the task by 10 (0 to 100) |
| `d` / `m` | add a `D : ` description / a `C : ` comment |
| `s` / `a` | separator below / above the task |
| `v` | move the task one stage on: backlog, todo, done, cancelled, and back to backlog |
| `u` | run `.tf/update.sh` after a confirmation |
| `i` | show the task's id as a date (also shown by eldoc on the id line) |

Typing `. `, `! `, `; ` or `: ` on a
header line moves it to its place in the header.

Typing backticks helps too: one pairs (`` ` `` becomes a pair with the cursor between), the second
steps over the closing one, and a third on an empty line makes a code block: the fences on their
own lines and the cursor on the code line between them, 4 columns deeper. Inline code and code
blocks are highlighted monospace on a subtle background.

## Files

| File | What |
|---|---|
| `tasks.tfmd` | Your tasks, tags and commands |
| `skill/base.md` | The format, and the built-in tags and commands with their full definitions (tf's; replaced by updates) |
| `skill/AGENTS.md` | Points the agent to `skill/base.md` and `tasks.tfmd` |
| `skill/SKILL.md` | The `tf` skill, linked as `.claude/skills/tf` and `.agents/skills/tf` |
| `VERSION` | Installed tf version: the release tag, then the commit hash (written by install and update) |
| `update.sh` | Updates `skill/`, `VERSION` and itself |
| `install.sh` | Setup; deletes itself |
