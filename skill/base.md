# tf base

Belongs to tf: `.tf/update.sh` replaces it. The format of `tf.md` and the built-in tags and
commands. Your own tags and commands go in the `# tags` and `# commands` sections of `tf.md`.

## format

* `tf.md` has five sections: `# todo`, `# backlog`, `# done`, `# tags`, `# commands`.
* Tasks separated from each other with 32 dashes: `--------------------------------`.
* The tf.md file should have 100 line strict word wrapping rule.
* No tabs should be used, only whitespaces
* No trailing whitespace.
* `# todo` is the agent's work; `# backlog` waits for the owner to move items into `# todo`;
  `# done` holds finished and cancelled items, newest first.
* The separator between tasks has a blank line before and after it.

## task header

Task header identifies the task and its main properties. The priority and tags lines are optional,
in this order, and indented 4 spaces. Priority: `! ` and an integer from 0 to 100; default 50,
higher is more urgent, and it doesn't change which item `tf` picks. Tags: `: ` and the tags,
comma-separated.

```
- [ ] <title>
    ! <priority>
    : <tag1>, <tag2>
```

## task state

```
- [ ] not done
- [x] done
- ~~[ ] <title>~~ cancelled
```

A cancelled task's title is struck through: `~~` goes before `[ ]` and after the last word
of the title, even when the title wraps.

## task body

Task body provides more context, cocreate examples and task updates.
Task body fields should be separated with newline from task header.
There can be multiple task fields separated with newline from each other.
Fields are indented 2 spaces. Continuation lines align under the field's text (6 spaces). Lists
inside a field start after a blank line, with the marker 2 spaces deeper than the field (column
4); wrapped lines align under the item's text, and a nested list's marker aligns under its
parent's text.

```
  D : <description>
  C : <comment>
```

```
  D : Text, wrapped
      under the text.

    1. Step one,
       wrapped.
       * nested item
```

## tags

Standard set of tags for marking tasks:

- ?    Question which requires only answer without any changes to be made.
- b    Bug
- epic Potentially huge task which requires decomposition and creation of custom tags to mark
       connected tasks

## markdown

`tf.md` is written for the raw view first; it also renders as Markdown, but never by raw-side
tricks.

* Hard wraps join into one paragraph when rendered. For a real break use a blank line or a list
  item, never trailing double spaces, a trailing `\` or HTML.
* No tables, no inline HTML.
* The separator needs a blank line before and after it, otherwise the line above it renders as
  a heading.
* The priority and tags lines render inline after the title: `[ ] fix login ! 80 : b`.
* Angle brackets (`<...>`) in titles and text go inside backticks: rendered Markdown hides bare
  ones as HTML. Templates go in code fences.
* A `#` at the start of a line renders as a heading; put `# section` names in backticks.
* Lists inside fields follow `## task body`. Inside a field, a new paragraph after a blank line
  renders as a code block (handy for examples), or, right after a bullet list, as part of its
  last item; text that should stay prose goes in the same paragraph or a new field.

## commands

A command is typed by the owner and run by the agent. One entry per command, entries separated by
a blank line; the entry header is the command in backticks, and the `D : ` field wraps like a task
body. Names start with `tf ` and can't reuse a built-in.

```
- `tf <name> <args>`

  D : <what the agent does; <args> are filled in from what the owner typed>
```

Rules for every command:

1. Re-read `.tf/tf.md` and `.tf/skill/base.md` from disk first, even if you read them earlier in the
   session: the owner edits them between commands, so a remembered state is stale.
2. Touch only the items the command works on. Keep the owner's wording and the other items as they
   are; reflow only to stay within the format. Never cancel an item (`~~...~~`) yourself.
3. Plan in plan mode when your agent has one (Claude Code: `EnterPlanMode`).
4. Own commands: when the owner types `tf <something>` that isn't a built-in, find the matching
   entry in `# commands` of `tf.md` and do what its `D : ` says, with the arguments filled in. If
   it changes the project and the description doesn't say how to handle approval, plan and get
   the owner's approval as for a task; otherwise just run it. If nothing matches, say so and list
   the commands in `# commands`.

Built-in commands:

- `tf`

  D : Work the first open item of `# todo`.

    1. Take the first item under `# todo` that is still `[ ]` (not done, not struck through)
       and not blank (skip empty placeholders). Never pick from `# backlog`. If no open item
       is left in `# todo`, say so and stop.
    2. Question (tag `?`): investigate and answer in chat, without changing the project. Then
       record the answer without asking: add a `C : ` field with the short answer, mark the
       item `[x]` and move it to the top of `# done`.
    3. Task or bug (tag `b`; find the root cause first): its `D : ` and `C : ` fields are the
       spec. Plan the implementation and ask about anything they leave open; implement only
       after the owner approves the plan.
    4. Epic (tag `epic`): plan a split into tasks instead of an implementation. In plan mode,
       investigate first, then ask the owner about everything the split depends on (scope,
       approach choices, granularity) before writing it; mark the new tasks with a new tag,
       added to `# tags`. After approval, put the tasks in `# todo` in the epic's place, mark
       the epic `[x]` with a `C : ` listing them and move it to the top of `# done`.
    5. When the work is finished and verified, mark the item `[x]`, add a short `C : ` summary
       (commit hash if any) and move it to the top of `# done`.

- `tf <n>`

  D : Work the first `<n>` open items of `# todo` together (`tf` is `tf 1`). Pick them as step 1
      of `tf` does; if fewer are open, take those and say so.

    1. Questions among them: answer in the same reply and close them as step 2 of `tf` does.
    2. Tasks, bugs and epics: one plan for all of them, with a section per item in `# todo`
       order, plus what they share (common files, an order forced by dependencies, conflicts
       between their specs). Ask all open questions at once. Epics get their split into
       tasks, as step 4 of `tf` describes.
    3. After the owner approves the plan once, implement the items one by one. Close each
       (step 5 of `tf`) as soon as it is finished and verified.
    4. If an item gets blocked midway, stop there and report it; leave it and the items after
       it open.

- `tf migrate <path>`

  D : Import the tasks of another tracker into `tf.md`.

    1. `<path>` is a file or a directory. For a directory, go through every file recursively,
       skipping `.git`, `.tf`, dependency and build folders, and binaries. Infer each file's
       format (Markdown checklists, `TODO`/`todo.txt`, org-mode, JSON or CSV issue exports,
       plain notes, ...); ignore files with no tasks.
    2. Map each task:
       * title to the header `- [ ] <title>`, description to `D : `, notes and comments to
         `C : `, keeping the source wording and reflowing it to the format;
       * priority to the priority line, scaled to 0-100; bug, question and epic to `b`, `?`
         and `epic`; other labels to the project's own tags, each added to `# tags` as
         `- <tag> <meaning>` unless already there;
       * open tasks marked as current, next, in progress or otherwise scoped go to `# todo`,
         other open tasks to `# backlog`. If the source has no such distinction and it can't
         be inferred, all open tasks go to `# backlog`;
       * done tasks to `# done` as `[x]`; cancelled or won't-do tasks to `# done` as
         `~~[ ] <title>~~`.
    3. Preview before writing: the files read and the format inferred for each, the number of
       tasks per section (todo, backlog, done, cancelled), the new tags, and every task whose
       mapping was a guess. Write only after the owner approves.
    4. Append the migrated tasks below the existing items of each section, with the usual
       separators. Never change or delete the source files.
