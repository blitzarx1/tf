---
name: tf
description: Work the project's task file .tf/tasks.tfmd. Use when the owner types "tf" (take the first open item under "# todo" and work it; "-t <ref>" works the todo item with that id or description instead, "-j <ref>" runs the job from "# jobs" with that id or description), "tf <n>" (plan and work the first n open items together) or "tf migrate <path>" (import tasks from another tracker into .tf/tasks.tfmd).
---

# tf

Read `.tf/skill/base.md` and `.tf/tasks.tfmd` from disk before acting. Find the command the owner
typed in `## commands` of `base.md` (with their full definitions) and do what its definition
says.

Plans are made in plan mode (rule 3 of `base.md`), also in auto mode.
