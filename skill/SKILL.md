---
name: tf
description: Work the project's task file .tf/tasks.tfmd. Use when the owner types "tf" (take the first open item under "# todo" and work it), "tf <n>" (plan and work the first n open items together) or "tf migrate <path>" (import tasks from another tracker into .tf/tasks.tfmd).
---

# tf

Read `.tf/skill/base.md` and `.tf/tasks.tfmd` from disk before acting. Find the command the owner
typed in `## commands` of `base.md` (with their full definitions) and do what its definition
says.
