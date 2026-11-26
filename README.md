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
  that can read files can follow it.

## Install

tf lives in one place, `$HOME/.tf`, wherever you start the agent:

```bash
git clone https://github.com/blitzarx1/tf ~/.tf && ~/.tf/install.sh
```

One `.tf` serves every project below `$HOME`; a task says which projects it is about in its `/ `
header line (paths relative to `$HOME`, several separated by a space). `install.sh` asks nothing:
- turns `.tf` into a plain folder by deleting `.tf/.git` (from a clone elsewhere it first moves the
  clone to `$HOME/.tf`);
- links `~/.claude/skills/tf` and `~/.agents/skills/tf` to `~/.tf/skill`, the one original;
- adds `@.tf/skill/AGENTS.md` to `~/CLAUDE.md` and a pointer line to `~/AGENTS.md`; agents started
  in a project below read those parent files too;
- deletes `README.md` and itself from `.tf`, leaving `tasks.tfmd`, `update.sh`, `VERSION` and `skill/`.

`.tf/` is not a git repository; keep your own backup of `tasks.tfmd` if you want its history.

## Use

| You type | The agent |
|---|---|
| `tf` | loads `~/.tf/tasks.tfmd` (always that one) and works the first open `# todo` item: answers a question, plans and then implements a task (a bug too), or asks you questions and splits an epic into tasks. Then it offers numbered options built from what was done (close, commit, push to the feature branch, worktree summary, and their combinations; answer with digits; never a push to `main` unless the task says so), and moves the item to `# done` with a summary (a job, type `j`, goes to `# jobs` instead and stays there). |
| `tf <n>` | works the first `<n>` open `# todo` items together: one plan covering all of them, one approval, then implements them in order and closes each. |
| `tf -t <ref>` | works the `# todo` item with that id, or the one your words describe, instead of the first. One `tf` per session: later messages in it are follow-ups, recorded as readable `A :` notes on that task; a second `tf` is declined, start a fresh session (unless the first split an epic: its tasks can follow in the same session). |
| `tf -j <ref>` | runs the job from `# jobs` with that id or description, following its `J :` instructions (give parameter values in words after the job, or it asks for them), then (after your approval) raises its run count `[<n>]` and records the refined instructions. |

Edit `tasks.tfmd` yourself whenever you like. Add new items to `# todo` or `# backlog`, move them
between the two, and add `D : ` descriptions and `C : ` comments. The agent answers in `A : `
fields and re-reads the file every time.

## Example

You write a task in `# todo`:

```
- [ ] login redirect drops the return url
    ! 80

  D : After logging in from /settings the user lands on /. Keep the page they came from.
```

You type `tf`. The agent finds the cause, shows a plan, you approve, it fixes the bug and moves
the task to `# done`:

```
- [x] login redirect drops the return url
    ! 80

  D : After logging in from /settings the user lands on /. Keep the page they came from.

  A : Root cause: the auth callback ignored `next`. It now checks `next` against the site
      origin and redirects there; added a test for /settings. 3f9c2a1
```

`! 80` is the priority (0-100, default 50). The optional type line `; <letter>` marks a `q`
question, an `e` epic or a `j` job; a task without it (a bug too) is a plain task. Tags go on a
`: ` line. `/ services/api` is the project the task
belongs to: a path relative to the folder that holds `.tf` (absent: that folder itself). Absent
lines mean the defaults, so a new task is only a title and an id, `. 1792321201`: a unix timestamp
in UTC (here 2026-10-18T11:00:01Z). Header lines go in the order id, project, priority, type,
tags. A title is one sentence that starts in
lowercase. The full format is in `skill/base.md`.

An epic (`; e`) that `tf` splits stays in `# todo` as `- [<n>] <title>`, `<n>` being the number of
its open tasks (in `# todo` or `# backlog`); they get the tag `e<epic id>` plus the epic's tags.
When `<n>` reaches 0 the epic stays open: you close it, or `tf` asks to. `tf` asks before working
the first open task of a split epic.

## Projects

One `.tf` serves every project below `$HOME`. A task's `/ ` line names its projects.

A task that changes the files of one project whose folder is a clean git repository is worked on a
feature branch in the project folder itself, with no `summary.tfmd`.

A task that needs several projects, or one whose folder has uncommitted changes, gets a folder in
`~/.tf/.worktrees` with a fresh clone of each project it needs (`<task folder>/<project>/`, link
from the project's `origin`, or the agent asks for it), and afterwards the agent writes a
`summary.tfmd` there: a reader's summary that only refers to `~/.tf/tasks.tfmd`, which stays the
source of truth.

## Update

```bash
~/.tf/update.sh
```

It is the general update, for agent instructions only; integrations have their own (Emacs:
`emacs/update-grammar.sh`). It replaces `skill/`, `VERSION` and `update.sh` with the latest
versions, makes sure the skill links exist and prints the version change. It never touches
`tasks.tfmd` or `.worktrees`.

## Emacs

`emacs/tf-ts-mode.el` is a major mode for `.tfmd` files (needs the `tree-sitter-tfmd` grammar: build and install it with `emacs/update-grammar.sh`, and again after
each `package-vc-upgrade` that changes the grammar; `C-c C-u` does it too).
Keys, all under `C-c C-`:

| Key | Does |
|---|---|
| `n` / `p` | next / previous task |
| `t` | new task below the current one in 3 steps: the title (one line, not blank), the project path (completion from the paths in use and the folders of the root; blank: none), the tags (completion, separated by `, `; blank: none). It gets an id; priority 50 and no type are the defaults |
| `l` | link the task to another one: choose a task (id and title) and its id goes into an `L : ` field, created before `R : ` when missing. `M-.` on an id of an `L : ` item jumps to the task, eldoc shows its title. |
| `C-c >` / `C-c <` | raise / lower the priority of the task by 10 (0 to 100) |
| `d` / `m` | add a `D : ` description / a `C : ` comment |
| `j` | add a `J : ` job instructions field with `Parameters:` and `Steps:` lists, or go to the existing one; a job in `# todo` moves to `# jobs` with `v` |
| `M-.` | on a reference of an `R : ` field (`path:line`, relative to `$HOME`), jump to it |
| `s` | split the task into subtasks (asks for titles until an empty one); it becomes an epic `- [<n>]` |
| `v` | move the task one stage on: backlog, todo, done, cancelled, and back to backlog. An epic moves with its subtasks when they share a stage; with some open and some not, nothing moves; the epic's `<n>` follows its subtasks |
| `C-c SPC` / `C-c S-SPC` | separator below / above the task |
| `u` | after a confirmation, run `~/.tf/update.sh` (the agent instructions) and `emacs/update-grammar.sh` (rebuilds the `tfmd` grammar for Emacs; also runnable by hand) |
| `i` | show the task's id as a date (also shown by eldoc on the id line) |

Typing `. `, `/ `, `! `, `; ` or `: ` on a header line moves it to its place in the header. A
`/ ` line is highlighted as a path, and eldoc on it shows the folder it points to. Splitting a task
(`s`) gives the subtasks its `/ ` line too.

Typing backticks helps too: one pairs (`` ` `` becomes a pair with the cursor between), the second
steps over the closing one, and a third on an empty line makes a code block: the fences on their
own lines and the cursor on the code line between them, 4 columns deeper. Inline code and code
blocks are highlighted monospace on a subtle background. A code line less than 4 columns deeper
than its fence, or a closing fence off the opening one's column, is marked red, and `TAB` moves it
into place. Away from a code block, text past the column limit is hidden behind `...` and
lines past the first 10 (`tf-ts-mode-max-block-lines`, nil: no limit) fold into one
`... N more lines` row; the block at point is shown whole.

The label of a `C :` field (yours), from the line start to the `:`, gets a pastel yellow
background, that of an `A :` field (the agent's) a pastel blue one and that of a `J :` field (job
instructions) a pastel green one (`tf-ts-comment-face`, `tf-ts-agent-face`, `tf-ts-job-face`).

## Files

| File | What |
|---|---|
| `tasks.tfmd` | Your tasks |
| `skill/base.md` | The format, the task types (`q`, `e`, `j`) and the built-in commands with their full definitions (tf's; replaced by updates) |
| `skill/AGENTS.md` | Points the agent to `skill/base.md` and `tasks.tfmd` |
| `skill/SKILL.md` | The `tf` skill, the original: `~/.claude/skills/tf` and `~/.agents/skills/tf` link to it |
| `VERSION` | Installed tf version: the release tag, then the commit hash (written by install and update) |
| `update.sh` | Updates `skill/`, `VERSION` and itself |
| `install.sh` | Setup; deletes itself |
