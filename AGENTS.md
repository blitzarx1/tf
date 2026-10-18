# tf: task flow

This project keeps its tasks in one file, `.tf/tf.md`, worked by the agent one item at a time. The
file's format is defined in `.tf/base.md`; read it, it is the source of truth.

## The file

- Sections: `# todo`, `# backlog`, `# done`, `# tags`, `# commands`, all the owner's
  (`.tf/base.md` is tf's and is replaced by updates). Only `# todo` is work for the agent.
  `# backlog` waits for the owner to move items into `# todo`.
- **Header:** `- [ ] <title>`, then optional lines indented 2 spaces: a priority and comma-separated
  tags. Standard tags are in `.tf/base.md`; the project's own tags are in `# tags`.
- **Body:** fields `D : ` (description) and `C : ` (comment), indented 2 spaces, separated from the
  header and from each other by a blank line. Continuation lines align under the text (6 spaces);
  list items (`*`, `1.`) keep their marker and wrap under their own text.
- **Between tasks** in a section: a blank line, 32 dashes (`--------------------------------`), a
  blank line.
- **Lines wrap strictly at 100 characters.** Spaces only, no tabs; no trailing whitespace.

## Working an item (`tf`)

1. **Always re-read `.tf/tf.md` from disk first**, even if you worked on it earlier in the session:
   the owner edits it between commands, so a remembered state is stale. Take the **first item under
   `# todo`** that is still `[ ]` (not done, not struck through) and not blank (skip empty
   placeholders). Never pick from `# backlog`.
2. **Question** (tag `?`): investigate and answer in chat, without changing the project. Then record
   the answer without asking: add a `C : ` field with the short answer, mark the item `[x]` and move
   it to the **top** of `# done` (newest first).
3. **Task** or **bug** (tag `b`; find the root cause first): its `D : ` and `C : ` fields are the
   spec. Switch to plan mode if your agent has one (Claude Code: `EnterPlanMode`), plan the
   implementation and ask about anything they leave open; implement only after the owner approves
   the plan. An **epic** gets a plan that splits it into tasks (marked with a new custom tag, added
   to `# tags`) instead of an implementation. When the work is finished and verified,
   mark the item `[x]`, add a short `C : ` summary (commit hash if any) and move it to the
   **top** of `# done`.
4. Touch only the item you worked on. Keep the owner's wording and the other items as they are;
   reflow only to stay within the format. Never cancel an item (`~~…~~`) yourself.
5. If no open item is left in `# todo`, say so and stop.

## Working several items (`tf <n>`)

`tf <n>` is `tf` for the first `<n>` open items of `# todo` (`tf` is `tf 1`). Pick them as step 1
of "Working an item" does; if fewer are open, take those and say so. Steps 4 and 5 still apply.

1. **Questions** among them: answer in the same reply and close them as step 2 does.
2. **Tasks, bugs and epics:** one plan for all of them, in plan mode if your agent has one: a
   section per item in `# todo` order, plus what they share (common files, an order forced by
   dependencies, conflicts between their specs). Ask all open questions at once. Epics get their
   split into tasks, as step 3 describes.
3. After the owner approves the plan once, implement the items one by one. Close each (`[x]`, its
   own `C : ` summary, top of `# done`) as soon as it is finished and verified.
4. If an item gets blocked midway, stop there and report it; leave it and the items after it open.

## Migrating a tracker (`tf migrate <path>`)

1. `<path>` is a file or a directory. For a directory, go through every file recursively, skipping
   `.git`, `.tf`, dependency and build folders, and binaries. Infer each file's format (Markdown
   checklists, `TODO`/`todo.txt`, org-mode, JSON or CSV issue exports, plain notes, ...); ignore
   files with no tasks.
2. Map each task:
   * title to the header `- [ ] <title>`, description to `D : `, notes and comments to `C : `,
     keeping the source wording and reflowing it to the format;
   * priority to the priority line; bug, question and epic to `b`, `?` and `epic`; other labels to
     custom tags, each added to `# tags` as `- <tag> <meaning>` unless already there;
   * open tasks marked as current, next, in progress or otherwise scoped go to `# todo`, other
     open tasks to `# backlog`. If the source has no such distinction and it can't be inferred,
     all open tasks go to `# backlog`;
   * done tasks to `# done` as `[x]`; cancelled or won't-do tasks to `# done` as
     `~~[ ] <title>~~`.
3. **Preview before writing:** the files read and the format inferred for each, the number of
   tasks per section (todo, backlog, done, cancelled), the new custom tags, and every task whose
   mapping was a guess. Write only after the owner approves.
4. Append the migrated tasks below the existing items of each section, with the usual separators.
   Never change or delete the source files.

## Custom commands (`tf <name>`)

When the owner types `tf <something>` that isn't a built-in, re-read `.tf/tf.md`, find the matching
entry in `# commands` and do what its `D : ` says, with the arguments filled in. If it changes the
project and the description doesn't say how to handle approval, plan and get the owner's approval
as for a task; otherwise just run it. If nothing matches, say so and list the commands in
`# commands`.

Tasks: follow .tf/AGENTS.md (tf task flow).
