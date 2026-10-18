---
name: tf
description: Work the project's task file .tf/tf.md. Use when the owner types "tf" (take the first open item under "# todo" and work it), "tf <n>" (plan and work the first n open items together) or "tf migrate <path>" (import tasks from another tracker into .tf/tf.md), or any other "tf <name>" listed under "# commands" in .tf/tf.md.
---

# tf

Read `.tf/base.md` and `.tf/tf.md` from disk before acting. Find the command the owner typed in
`## commands` of `base.md` (built-ins, with their full definitions) or `# commands` of `tf.md`
(the project's own) and do what its definition says.
