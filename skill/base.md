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
order, and indented 4 spaces. Id: `. ` and an integer. Project: `/ ` and one or several paths,
separated by a space, relative to the `home folder` (`$HOME`), without a leading `/`. Priority:
`! ` and an integer from 0 to 100; default 50, higher is more urgent, and it doesn't change which
item `tf` picks. Type: `; ` and one letter, one of the types below (a plain task has none). Tags:
`: ` and the tags, separated by spaces.

A property that is absent has its default: no project (also when the line is empty), priority 50,
no type (a plain task), no tags. A new task is written with the title and the id only; the other
lines appear when they differ from the default.

```
- [ ] <title>
    . <id>
    / <project path> <project path>
    ! <priority>
    ; <type>
    : <tag1> <tag2>
```

A long title wraps onto lines indented 4 spaces, before the property lines.

The title is one sentence that starts with a lowercase letter; it can wrap over several lines but
has no empty lines and no triple backticks. The id is a unix timestamp in seconds (UTC), unique
within the file; it reads as an RFC3339 date, so `. 1792321201` is `2026-10-18T11:00:01Z`.

## task type

The type says how `tf` works an item that is not a plain task; a task without a `; ` line is a
plain task (a bug is one too: find its root cause first). Any other letter is flagged by the
editor:

- q    Question which requires only answer without any changes to be made.
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

* A job runs from the folder of its `/ :` path (the first one, if several; the home folder when
  it has none): its steps and scripts start there.
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
job (type `j`): the agent drafts and refines it, the owner may edit it. `L : ` holds the links of
the task (see below).

```
  D : <description>
  C : <comment>
  A : <agent note>
  J : <job instructions>
  L :

      * <task id>
```

`L : ` holds the links: a list, after a blank line, of the ids of the tasks this task is connected
to (one id per item, `D : `, `C : `, `A : ` and `J : ` may stand before or after it). A task links
to tasks of `tasks.tfmd`. The owner adds a link in the editor (`C-c C-l`); the agent may offer
links, but writes one only after approval (rule 2).

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

## projects

There is one `.tf`: `$HOME/.tf`, and its `home folder` is `$HOME`. It serves every project below
it; the folders of the projects are anywhere under `$HOME`. A task's `/ :` names its projects,
relative to `$HOME` (`dev/homeradar`), one path or several separated by a space; a task that needs
no project in particular has no `/ :`.

* A task that changes files of a project is worked in one of two ways:

  * one project whose folder is a git repository with a clean working tree: no clone; the agent
    makes a feature branch in the project folder (named from the task title, lowercase words joined
    by `-`, or by the project's own branch convention), changes the code and commits only there. It
    records the branch in an `A : ` note of the task. No worktree;
  * several projects, or one whose folder has uncommitted changes (the agent never touches them): a
    worktree. The agent makes sure `$HOME/.tf/.worktrees` exists, creates in it a folder named by
    the task id (`.worktrees/<id>`) and clones each project it needs into that folder, as
    `<id>/<project>/`; the code is changed there. A folder worked by several tasks (`tf <n>`, or a
    later task that reuses it) is named by all their ids, ascending, joined by `-`
    (`.worktrees/<id1>-<id2>`); the agent creates it so from the start, or renames the existing
    folder when a task joins it, and fixes the paths in the earlier `A : ` notes. The clone link is
    the `origin` of the project in `$HOME`; if there is none, the agent asks the owner for it. The
    folder's path is recorded in an `A : ` note of the task; the editor opens it with `C-c C-w`.
* Branches: when the work starts (project folder), or right after cloning (worktree), the agent
  creates a feature branch (named from the task title, lowercase words joined by `-`, or by the
  project's own branch convention) and commits only there. It pushes only that branch
  (`git push -u origin <branch>`); rule 10 of `## commands` forbids the default one.
* Not covered: edits of `tasks.tfmd` and the other files of `.tf` (bookkeeping), and work that
  changes no project file (a question, type `q`).

## commands

A command is typed by the owner and run by the agent. Rules for every command:

1. The `.tf` is always `$HOME/.tf`, wherever the agent was started; no searching. Read `base.md`
   and `tasks.tfmd` from it from disk, even if you read them earlier in the session: the owner
   edits them between commands, so a remembered state is stale. Load `tasks.tfmd` in full (all
   sections) into context, so you know all the tasks and jobs while working the current one.
2. Touch only the items the command works on. Keep the owner's wording and the other items as they
   are; reflow only to stay within the format. Never cancel an item (`~~...~~`) yourself.
   Edit a `tasks.tfmd` only after the owner explicitly approves that edit, since the owner may
   be writing in it: say what you are about to write and wait for the answer. An approved plan is
   not that approval. In the session of a task, the options chosen as rule 8 says cover the
   follow-ups on it.
3. Every execution plan (steps 3, 4 and 6 of `tf`, the plan of `tf <n>`) is made in plan mode
   (Claude Code: `EnterPlanMode`), even if the session is in auto mode or another permission
   mode: enter it before investigating, and leave it only when the owner approves the plan. Never
   write the plan in chat instead. An agent without plan mode states the plan and waits for
   approval.
4. If the owner types `tf <something>` that isn't a built-in, say so and list the built-ins.
5. Flags `-t <ref>` and `-j <ref>` of `tf` pick an item instead of the first open one. `<ref>` is
   a task or job id, or natural-language words. An id matches exactly; words are matched against
   the titles and descriptions of the candidates (`-t`: open items of `# todo`; `-j`: items of
   `# jobs`). Name the one match in the plan; if several or none match, ask. They don't combine
   with `tf <n>` (say so). The text after `-j` may also hold
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
7. One `tf` per session: if a `tf` command already ran in this
   session, decline a new one. Warn the owner that this breaks the session-per-task flow, name
   the task of the session, and ask them to start a fresh session (`/clear` or a new one) and
   type `tf` there. Don't work the next item; you can't clear your own context. Exception: if
   the session's last `tf` split an epic or worked a task tagged `e<id>`, a new `tf` is allowed
   when the item it picks is that epic or another task of it; any other item is declined as
   above.
8. Options: whenever the owner has to choose what happens next (closing a task, recording a job
   run, writing an epic split, after a follow-up), build the numbered list from the context and
   what was done, never from a fixed template, and present it once, in one message, so that one
   answer with digits settles everything. Enumerate every sensible combination of the independent
   actions that apply here: record the item in `tasks.tfmd` (close, run, split, follow-up note),
   commit, push, each commit and push per repository when several changed, and doing nothing
   more. Leave out what is impossible, and say in one line what was left out and why (not a git
   repository, no changes, no remote, nothing to record). Several digits
   may be answered (`1,3`). After the answer do all the chosen actions and nothing else; never
   leave an action of the list for a later question. The three-way
   `close` / `close and commit` / `close, commit and push` is only the minimal case. Every push
   option names its branch (`push to <branch>`); none pushes to the default branch unless rule 10's
   exception applies. Say in the "left out" line when that rule removed an option.
9. Links: before planning a task (steps 3, 4 and 6 of `tf`, and every item of `tf <n>`), read the
   tasks its `L : ` links to (by id, in any section of `tasks.tfmd`; a link to
   an id that is not there is skipped) to expand the context. While analysing and planning, if
   other tasks are clearly connected to it, advise the owner to link them in the plan; the
   link is written after approval (rule 2).
10. Pushes: never push to the default branch of a repository (`main`, `master`, or what
    `origin/HEAD` points to), and never force-push it. A push goes only to a feature branch
    (`## projects`, Branches). Exception: the task's `D : ` or `C : ` explicitly requires a push to
    the default branch; then the plan and the option label name it. An approved plan or an earlier
    choice of "push" is not that requirement.

Built-in commands:

- `tf [-t <ref>] [-j <ref>]`

  D : Work the first open item of `# todo`, or the one `-t` names (rule 5), or run the job `-j`
      names.

      1. Take the first item under `# todo` that is still `[ ]` or `[<n>]` (not done, not struck
         through) and not blank (skip empty placeholders); with `-t`, the open item of `# todo`
         that `<ref>` names. With `-j`, go to step 6 instead. Never pick from `# backlog` or
         `# jobs` otherwise. If no open item is left in `# todo`, say so and stop. Started in
         `$HOME`, every item counts; started in a folder below it, only the items with a `/ :`
         path that is that folder or a folder below it count (items without `/ :` are skipped),
         and the same filter applies to `tf <n>` and to `-t` (`-j` is never filtered). A split
         epic `[<n>]` is not worked itself:

         * if some of its tasks (tagged `e<id>`) are open in `# todo`, ask the owner whether
           you may proceed with the first of them, and on yes work that task as step 2 or 3
           says; on no, stop;
         * if `<n>` is 0, ask whether to close it (`[x]`, an `A : ` summary, top of `# done`);
         * otherwise do nothing for it and take the next open item.
      2. Question (type `q`): investigate and answer in chat, without changing the project. Then
         ask (rule 2) to record the answer; on approval add an `A : ` field with the short
         answer, mark the item `[x]` and move it to the top of `# done`.
      3. Task or job (no type, or type `j`; find the root cause of a bug first): its `D : `
         and `C : ` fields are the spec (`A : ` holds earlier agent notes). Project files are
         changed only as `## projects` says: on a feature branch in the project folder, or in the
         task's worktree folder (which project or projects it needs, from its `/ :` or the spec,
         and which of the two ways applies, is part of the plan).
         Plan (plan mode, rule 3) the implementation and ask about anything they leave open;
         implement only after the owner approves the plan. For a job, doing the work includes
         drafting or refining its `J : ` instructions so the next run can follow them.
      4. Epic (type `e`, state `[ ]`, no task tagged `e<id>` yet): plan (plan mode, rule 3) a
         split into tasks instead of an implementation. Only such an epic is split by the agent;
         if tasks tagged with its id exist, it is already split: its header must read `[<n>]`,
         fix `<n>` and go on as step 1 says. In plan mode, investigate first, then ask the owner
         about everything the split depends on (scope, approach choices, granularity) before
         writing it. After approval of the split, ask for the approval to write it (rule 2) with the
         options of rule 8, with "write the split" in place of "close".

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
         writing in it. Report in chat and offer the options of rule 8 (close the task, commit,
         push, and their combinations), so the owner answers with digits.

         Only after the answer (digits or the options' words), mark the item `[x]`, add a short
         `A : ` summary (commit hash if any, and which option the owner chose) and move it to the
         top of `# done`, then commit and push as chosen (to the feature branch, rule 10). A job
         (type `j`) is not marked `[x]`: it becomes `- [1]` and goes to the top of `# jobs`. If the
         item is tagged `e<id>`, lower `<n>` in the header of the epic with that id by one; at `[0]`
         leave the epic open, it is closed as step 1 says. Later follow-ups (rule 6) keep the last
         choice unless the owner says otherwise.
      6. Run a job (`-j <ref>`): the job is in `# jobs`; read its `J : ` and the `A : ` and `C : `
         notes. Take the values of its parameters from the text the owner gave after the job's
         reference, and ask the owner explicitly for every parameter that has no value and no
         default. Plan (plan mode, rule 3) the run, naming the parameter values, ask about anything
         else left open (a job starts in the folder of its `/ :`), run it after the owner approves
         the plan, and refine the instructions
         the run showed to be wrong or missing, the parameter list included.
         Then, as in step 5, report and offer the options of rule 8, with "record the run" in
         place of "close".

         Only after the answer, raise the job's `[<n>]` by one, put the refined instructions in
         `J : ` and a short `A : ` note of the run (commit hash if any, and the option chosen),
         then commit and push as chosen (to the feature branch, rule 10). The job stays where it
         is. The session belongs to the job (rules 6 and 7).

- `tf <n>`

  D : Work the first `<n>` open items of `# todo` together (`tf` is `tf 1`). Pick them as step 1
      of `tf` does, counting open tasks, not epics: a split epic is asked about once, as there, and
      its open tasks are the items; if fewer are open, take those and say so.

      1. Questions among them: answer in the same reply and close them as step 2 of `tf` does.
      2. Tasks, jobs and epics: one plan (plan mode, rule 3) for all of them, with a
         section per item in `# todo` order, plus what they share (common files, an order forced by
         dependencies, conflicts between their specs). Ask all open questions at once. Epics get
         their split into tasks, as step 4 of `tf` describes.
      3. After the owner approves the plan once, implement the items one by one. Close each
         (step 5 of `tf`) as soon as it is finished and verified.
      4. If an item gets blocked midway, stop there and report it; leave it and the items after
         it open.
