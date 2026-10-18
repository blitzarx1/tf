# tf: task flow

This project keeps its tasks in one file, `.tf/tf.md`, worked by the agent one item at a time. The
file's format is defined in its `# info` section; read it, it is the source of truth.

## The file

- Sections: `# todo`, `# backlog`, `# done`, `# custom tags`, `# info`. Only `# todo` is work for
  the agent. `# backlog` waits for the owner to move items into `# todo`.
- **Header:** `- [ ] <title>`, then optional lines indented 2 spaces: a priority and comma-separated
  tags. Standard tags are in `# info`; the project's own tags are in `# custom tags`.
- **Body:** fields `D : ` (description) and `C : ` (comment), indented 2 spaces, separated from the
  header and from each other by a blank line. Continuation lines align under the text (6 spaces);
  list items (`*`, `1.`) keep their marker and wrap under their own text.
- **Between tasks** in a section: a blank line, 32 dashes (`--------------------------------`), a
  blank line.
- **Lines wrap strictly at 100 characters.** Spaces only, no tabs; no trailing whitespace.

## Working an item (`tf`)

1. **Always re-read `.tf/tf.md` from disk first**, even if you worked on it earlier in the session:
   the owner edits it between commands, so a remembered state is stale. Take the **first item under
   `# todo`** that is still `[ ]` and not blank (skip empty placeholders). Never pick from
   `# backlog`.
2. **Question** (tag `?`): investigate and answer in chat, without changing the project. Then record
   the answer without asking: add a `C : ` field with the short answer, mark the item `[v]` and move
   it to the **top** of `# done` (newest first).
3. **Task** or **bug** (tag `b`; find the root cause first): its `D : ` and `C : ` fields are the
   spec. Plan the implementation and ask about anything they leave open; implement only after the
   owner approves the plan. An **epic** gets a plan that splits it into tasks (marked with a new
   custom tag, added to `# custom tags`) instead of an implementation. When the work is finished
   and verified, mark the item `[v]`, add a short `C : ` summary (commit hash if any) and move it
   to the **top** of `# done`.
4. Touch only the item you worked on. Keep the owner's wording and the other items as they are;
   reflow only to stay within the format. Never mark an item `[x]` (cancelled) yourself.
5. If no open item is left in `# todo`, say so and stop.

## Adding an item (`tf new <title>`)

Add `- [ ] <title>` at the **top of `# backlog`**, followed by the separator if other items follow.
Nothing else: no tags, no body, unless the owner gives them.
