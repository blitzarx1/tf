---
name: tf
description: Work the project's task file .tf/tf.md. Use when the owner types "tf" (take the first open item under "# todo" and work it), "tf <n>" (plan and work the first n open items together) or "tf migrate <path>" (import tasks from another tracker into .tf/tf.md), or any other "tf <name>" listed under "# commands" in .tf/tf.md.
---

# tf

The rules are in `.tf/AGENTS.md`; read it before acting. The task file is `.tf/tf.md` and its
format is defined in `.tf/base.md`.

On `tf`: re-read `.tf/tf.md` from disk, take the first open item under `# todo` and work it as
`.tf/AGENTS.md` describes (question, task, bug or epic). If `# todo` has no open item, say so.

On `tf <n>`: work the first `<n>` open items under `# todo` with one combined plan, as the
"Working several items" section of `.tf/AGENTS.md` describes.

On `tf migrate <path>`: import the tasks found at `<path>` as the "Migrating a tracker"
section of `.tf/AGENTS.md` describes, showing a preview before writing anything.

On any other `tf <name>`: run the matching entry of `# commands` in `.tf/tf.md`, as the
"Custom commands" section of `.tf/AGENTS.md` describes.
