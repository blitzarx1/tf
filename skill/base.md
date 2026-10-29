# tf base

Belongs to tf: `.tf/update.sh` replaces it. The format of `tasks.tfmd` and the built-in tags and
commands.

## format

* `tasks.tfmd` has three sections: `# todo`, `# backlog`, `# done`.
* Tasks separated from each other with 32 dashes: `--------------------------------`.
* `tasks.tfmd` is wrapped strictly at 100 columns.
* Spaces only, no tabs; indent in multiples of 2 spaces (headers' property lines: 4).
* No trailing whitespace.
* `# todo` is the agent's work; `# backlog` waits for the owner to move items into `# todo`;
  `# done` holds finished and cancelled items, newest first.
* The separator between tasks has a blank line before and after it.
* `.tfmd` is plain text for the raw view; it is not rendered as Markdown. Editors use the
  `tfmd` tree-sitter grammar (`tree-sitter-tfmd/`).

## task header

Task header identifies the task and its main properties. The property lines are optional, in this
order, and indented 4 spaces. Id: `. ` and an integer. Priority: `! ` and an integer from 0 to
100; default 50, higher is more urgent, and it doesn't change which item `tf` picks. Type: `; `
and a lowercase word. Tags: `: ` and the tags, comma-separated.

```
- [ ] <title>
    . <id>
    ! <priority>
    ; <type>
    : <tag1>, <tag2>
```

A long title wraps onto lines indented 4 spaces, before the property lines.

The title is one sentence that starts with a lowercase letter; it can wrap over several lines but
has no empty lines. The id is a unix timestamp in seconds (UTC), unique within the file; it reads
as an RFC3339 date, so `. 1792321201` is `2026-10-18T11:00:01Z`.

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
inside a field start after a blank line, with the marker aligned under the field's text (column
6); wrapped lines align under the item's text, and a nested list's marker aligns under its
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

Inline code goes in single backticks, on one line: `` `code` ``. A code block is three backticks
on their own line, the code lines 4 columns deeper, and three backticks again, with no language
tag. The fences go where the field's text starts (column 6).

```
  C : Text before the block.

      ```
          code line 1
          code line 2
      ```
```

## tags

Standard set of tags for marking tasks:

- ?    Question which requires only answer without any changes to be made.
- b    Bug
- epic Potentially huge task which requires decomposition and creation of custom tags to mark
       connected tasks

Your own tags need no registration: write them on the `: ` line.

## commands

A command is typed by the owner and run by the agent. Rules for every command:

1. Re-read `.tf/tasks.tfmd` and `.tf/skill/base.md` from disk first, even if you read them
   earlier in the session: the owner edits them between commands, so a remembered state is
   stale.
2. Touch only the items the command works on. Keep the owner's wording and the other items as they
   are; reflow only to stay within the format. Never cancel an item (`~~...~~`) yourself.
3. Plan in plan mode when your agent has one (Claude Code: `EnterPlanMode`).
4. If the owner types `tf <something>` that isn't a built-in, say so and list the built-ins.

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
         approach choices, granularity) before writing it; mark the new tasks with a new tag.
         After approval, put the tasks in `# todo` in the epic's place, mark
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

  D : Import the tasks of another tracker into `tasks.tfmd`.

      1. `<path>` is a file or a directory. For a directory, go through every file recursively,
         skipping `.git`, `.tf`, dependency and build folders, and binaries. Infer each file's
         format (Markdown checklists, `TODO`/`todo.txt`, org-mode, JSON or CSV issue exports,
         plain notes, ...); ignore files with no tasks.
      2. Map each task:
         * title to the header `- [ ] <title>`, description to `D : `, notes and comments to
           `C : `, keeping the source wording and reflowing it to the format;
         * priority to the priority line, scaled to 0-100; bug, question and epic to `b`, `?`
           and `epic`; other labels to the project's own tags;
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
