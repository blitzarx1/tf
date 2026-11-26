---
name: tf
description: Work the task file $HOME/.tf/tasks.tfmd. Use when the owner types "tf" (take the first open item under "# todo" and work it; "-t <ref>" works the todo item with that id or description instead, "-j <ref>" runs the job from "# jobs" with that id or description) or "tf <n>" (plan and work the first n open items together).
---

# tf

Read `$HOME/.tf/skill/base.md` and `$HOME/.tf/tasks.tfmd` (always that `.tf`, rule 1 of
`base.md`) from disk before acting. Find the command the owner
typed in `## commands` of `base.md` (with their full definitions) and do what its definition
says.

Plans are made in plan mode (rule 3 of `base.md`), also in auto mode.
