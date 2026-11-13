# tf base

Belongs to tf: `.tf/update.sh` replaces it. The format of `tasks.tfmd` and the built-in tags and
commands.

## format

* `tasks.tfmd` has four sections: `# todo`, `# backlog`, `# done`, `# jobs`.
* Tasks separated from each other with 32 dashes: `--------------------------------`.
* `tasks.tfmd` is wrapped strictly at 100 columns.
* Spaces only, no tabs; indent in multiples of 2 spaces (headers' property lines: 4).
* No trailing whitespace.
* `# todo` is the agent's work; `# backlog` waits for the owner to move items into `# todo`;
  `# done` holds finished and cancelled items, newest first; `# jobs` holds the jobs (type `j`),
  which stay there permanently.
* The separator between tasks has a blank line before and after it.
* `.tfmd` is plain text for the raw view; it is not rendered as Markdown. Editors use the
  `tfmd` tree-sitter grammar (`tree-sitter-tfmd/`).

## task header

Task header identifies the task and its main properties. The property lines are optional, in this
order, and indented 4 spaces. Id: `. ` and an integer. Priority: `! ` and an integer from 0 to
100; default 50, higher is more urgent, and it doesn't change which item `tf` picks. Type: `; `
and a lowercase word, one of the types below. Tags: `: ` and the tags, separated by spaces.

A property that is absent has its default: priority 50, type `t`, no tags. A new task is written
with the title and the id only; the other lines appear when they differ from the default.

```
- [ ] <title>
    . <id>
    ! <priority>
    ; <type>
    : <tag1> <tag2>
```

A long title wraps onto lines indented 4 spaces, before the property lines.

The title is one sentence that starts with a lowercase letter; it can wrap over several lines but
has no empty lines and no triple backticks. The id is a unix timestamp in seconds (UTC), unique
within the file; it reads as an RFC3339 date, so `. 1792321201` is `2026-10-18T11:00:01Z`.

## task type

The type says what the item is and how `tf` works it:

- t    Task, the default when there is no `; ` line.
- q    Question which requires only answer without any changes to be made.
- b    Bug.
- e    Epic: potentially huge task which requires decomposition into tasks.
- j    Job: a repeatable piece of work with reusable instructions (`J : `); see `## jobs`.

## task state

```
- [ ] not done
- [<n>] split into tasks, <n> of them still open
- [x] done
- ~~[ ] <title>~~ cancelled
```

A `[<n>]` item is an epic that was split: its tasks carry the tag `e<id>` of the epic (see `tf`),
and `<n>` counts those of them that are open, in `# todo` or `# backlog` (done and cancelled ones
don't count). The count is kept up to date when a task changes stage; at `[0]` the epic stays
open until the owner closes it (`C-c C-v` in the editor) or `tf` does (see step 1). A cancelled
task's title is struck through: `~~` goes before `[ ]` and after
the last word of the title, even when the title wraps.

## jobs

A job automates work that is done many times. Its logic is explicit: plain-word instructions for
the agent and/or a script the agent runs, kept in the `J : ` field. The instructions may be empty
at first; they are drafted and refined by the runs.

* A job is created as a task of type `j` in `# todo` or `# backlog`, worked like any task. On
  closing (step 5 of `tf`) it goes to the top of `# jobs` as `- [<n>]` instead of `# done`, and
  stays there. Never `[x]`.
* In `# jobs`, `[<n>]` is the number of runs, not open tasks (the section tells it from a split
  epic). A job that has just been worked and closed is `[1]`.
* `tf` never picks from `# jobs`; the owner runs a job with `tf -j <ref>`.
* Every `tf` reads `# jobs` as the tools it can advise the owner to use on other tasks. When an
  action the agent did for a task looks repeatable, it offers to make it a job; on yes it refines
  the parameters with the owner and creates the job in `# jobs` (rule 2 applies).
* A job may take parameters. Its `J : ` lists them in a paragraph that starts with the line
  `Parameters:`, followed after a blank line by one bullet per parameter:
  `` `name`: meaning, default: <value> ``, or `no default` when it has none. The steps of the job
  refer to a parameter by its backticked name. A job without that paragraph takes no
  parameters. Refine the list when a run shows a parameter is missing.

  ```
    J : Write the release notes for a version.

        Parameters:

        * `version`: the version to describe, no default
        * `since`: the previous tag, default: the latest tag
        * `format`: `md` or `txt`, default: `md`

        Steps:

        1. Collect the commits since `since`.
        2. Group them by type and write the notes in `format`.
  ```
* Refine a job by editing `J : ` and by adding `A : ` follow-ups and `C : ` comments.

## task body

Task body provides more context, cocreate examples and task updates.
Task body fields should be separated with newline from task header.
There can be multiple task fields separated with newline from each other.
Fields are indented 2 spaces. Continuation lines align under the field's text (6 spaces). Lists
inside a field start after a blank line, with the marker aligned under the field's text (column
6); wrapped lines align under the item's text, and a nested list's marker aligns under its
parent's text.

`D : ` is the description and `C : ` the owner's comment. `A : ` is the agent's: its answers,
comments, summaries and follow-ups. The agent never writes `C : `. `J : ` is the instructions of a
job (type `j`): the agent drafts and refines it, the owner may edit it.

```
  D : <description>
  C : <comment>
  A : <agent note>
  J : <job instructions>
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

Tags are free: they need no registration, write them on the `: ` line. A tag `e<id>` links a task
to the epic with that id.

## commands

A command is typed by the owner and run by the agent. Rules for every command:

1. Re-read `.tf/tasks.tfmd` and `.tf/skill/base.md` from disk first, even if you read them
   earlier in the session: the owner edits them between commands, so a remembered state is
   stale. Load the whole `tasks.tfmd` (every section, in full) into context, so you know all the
   tasks and jobs of the project while working the current one.
2. Touch only the items the command works on. Keep the owner's wording and the other items as they
   are; reflow only to stay within the format. Never cancel an item (`~~...~~`) yourself.
   Edit `.tf/tasks.tfmd` only after the owner explicitly approves that edit, since the owner may
   be writing in it: say what you are about to write and wait for the answer. An approved plan is
   not that approval. In the session of a task, the option chosen in step 5 of `tf` covers the
   follow-ups on it.
3. Plan in plan mode when your agent has one (Claude Code: `EnterPlanMode`).
4. If the owner types `tf <something>` that isn't a built-in, say so and list the built-ins.
5. Flags `-t <ref>` and `-j <ref>` of `tf` pick an item instead of the first open one. `<ref>` is
   a task or job id, or natural-language words. An id matches exactly; words are matched against
   the titles and descriptions of the candidates (`-t`: open items of `# todo`; `-j`: items of
   `# jobs`). Name the one match in the plan; if several or none match, ask. They don't combine
   with `tf <n>` (say so) and `tf migrate` doesn't take them. The text after `-j` may also hold
   the parameter values of the job in natural language (`tf -j release notes for version 2.1`):
   the words that name the job are the reference, the rest are the values; if the split is
   unclear, ask.
6. Session follow-ups: a session belongs to the task it worked. Any later owner message in the
   session is worked as a follow-up and its outcome is appended as a new `A : Follow-up: ...`
   field on that task (it stays in `# done`; no new task, never `C : `). After `tf <k>`, the
   follow-up goes to the item it concerns; ask if it is unclear. Write it for a human reader:

   * the first line is the outcome in one sentence; details follow in short paragraphs, a blank
     line between them;
   * names, paths and commands in single backticks; multi-line code or output in a fenced block;
   * several changes or steps as a list or an enumeration, not a long run of prose.

   * a last, separate paragraph `Deploy: ...` and/or `Note: ...`, only when needed. Deploy is meant
     broadly: whatever the owner must do to make the change take effect and be visible and working
     for the end user (build and release, restart a service or editor, upgrade or reload a
     package, run `update.sh` or a migration, rebuild a library, clear a cache), not just a
     release to prod or test. `Note:` is anything non-obvious the owner should know. If the steps
     are obvious or there are none, leave the paragraph out. The same goes for the `A : ` summary
     of a closed item.

   ```
     A : Follow-up: `update.sh` now prints a status per destination.

         Statuses:

         * `created`
         * `updated`
         * `unchanged`, the copy is skipped

         Committed in 3352895.

         Deploy: run `.tf/update.sh` in the installed projects to get the new output.
   ```
7. One `tf` per session: if a `tf` command (any form but `tf migrate`) already ran in this
   session, decline a new one. Warn the owner that this breaks the session-per-task flow, name
   the task of the session, and ask them to start a fresh session (`/clear` or a new one) and
   type `tf` there. Don't work the next item; you can't clear your own context. Exception: if
   the session's last `tf` split an epic or worked a task tagged `e<id>`, a new `tf` is allowed
   when the item it picks is that epic or another task of it; any other item is declined as
   above.

Built-in commands:

- `tf [-t <ref>] [-j <ref>]`

  D : Work the first open item of `# todo`, or the one `-t` names (rule 5), or run the job `-j`
      names.

      1. Take the first item under `# todo` that is still `[ ]` or `[<n>]` (not done, not struck
         through) and not blank (skip empty placeholders); with `-t`, the open item of `# todo`
         that `<ref>` names. With `-j`, go to step 6 instead. Never pick from `# backlog` or
         `# jobs` otherwise. If no open item is left in `# todo`, say so and stop. A split epic
         `[<n>]` is not worked itself:

         * if some of its tasks (tagged `e<id>`) are open in `# todo`, ask the owner whether
           you may proceed with the first of them, and on yes work that task as step 2 or 3
           says; on no, stop;
         * if `<n>` is 0, ask whether to close it (`[x]`, an `A : ` summary, top of `# done`);
         * otherwise do nothing for it and take the next open item.
      2. Question (type `q`): investigate and answer in chat, without changing the project. Then
         ask (rule 2) to record the answer; on approval add an `A : ` field with the short
         answer, mark the item `[x]` and move it to the top of `# done`.
      3. Task, bug or job (type `t`, `b` or `j`; find the root cause of a bug first): its `D : `
         and `C : ` fields are the spec (`A : ` holds earlier agent notes). Plan the
         implementation and ask about anything they leave open; implement only after the owner
         approves the plan. For a job, doing the work includes drafting or refining its `J : `
         instructions so the next run can follow them.
      4. Epic (type `e`, state `[ ]`, no task tagged `e<id>` yet): plan a split into tasks
         instead of an implementation. Only such an epic is split by the agent; if tasks tagged
         with its id exist, it is already split: its header must read `[<n>]`, fix `<n>` and
         go on as step 1 says. In plan mode, investigate first, then ask the owner about
         everything the split depends on (scope, approach choices, granularity) before writing
         it. After approval of the split, ask for the approval to write it (rule 2) with the
         numbered options of step 5, the word "close" replaced by "write the split":

         1. write the split;
         2. write the split and commit;
         3. write the split, commit and push.

         On the answer:

         * the epic stays in `# todo` as `- [<n>] <title>` with its `D : `, an id and `; e`,
           `<n>` being the number of new tasks; if it has no id, create one as `## task header`
           says;
         * put the new tasks in `# todo` right below it, each with its own id created as
           `## task header` says, tagged `e<epic id>` plus the epic's own tags; add an `A : ` to
           the epic listing them.

         The owner can also split any task by hand (`C-c C-s` in the editor), which turns it
         into an epic of the same shape.
      5. When the work is finished and verified, do not touch `tasks.tfmd` yet: the owner may be
         writing in it. Report in chat and offer the numbered options below, so the owner answers
         with a number:

         1. close the task;
         2. close and commit;
         3. close, commit and push.

         Only after the answer (a number or the option's words), mark the item `[x]`, add a short
         `A : ` summary (commit hash if any, and which option the owner chose) and move it to the
         top of `# done`, then commit and push as chosen. A job (type `j`) is not marked `[x]`: it
         becomes `- [1]` and goes to the top of `# jobs`. If the item is tagged `e<id>`, lower
         `<n>` in the header of the epic with that id by one; at `[0]` leave the epic open, it is
         closed as step 1 says. Later follow-ups (rule 6) keep the last choice unless the owner
         says otherwise.
      6. Run a job (`-j <ref>`): the job is in `# jobs`; read its `J : ` and the `A : ` and `C : `
         notes. Take the values of its parameters from the text the owner gave after the job's
         reference, and ask the owner explicitly for every parameter that has no value and no
         default. Plan the run, naming the parameter values, ask about anything else left open,
         run it after the owner approves the plan, and refine the instructions the run showed to
         be wrong or missing, the parameter list included.
         Then, as in step 5, report and offer the numbered options:

         1. record the run;
         2. record the run and commit;
         3. record the run, commit and push.

         Only after the answer, raise the job's `[<n>]` by one, put the refined instructions in
         `J : ` and a short `A : ` note of the run (commit hash if any, and the option chosen),
         then commit and push as chosen. The job stays where it is. The session belongs to the
         job (rules 6 and 7).

- `tf <n>`

  D : Work the first `<n>` open items of `# todo` together (`tf` is `tf 1`). Pick them as step 1
      of `tf` does, counting open tasks, not epics: a split epic is asked about once, as there, and
      its open tasks are the items; if fewer are open, take those and say so.

      1. Questions among them: answer in the same reply and close them as step 2 of `tf` does.
      2. Tasks, bugs, jobs and epics: one plan for all of them, with a section per item in `# todo`
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
         * priority to the priority line, scaled to 0-100; bug, question and epic to the types
           `b`, `q` and `e`; other labels to the project's own tags;
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
