# tf: task flow

This machine keeps its tasks in `$HOME/.tf/tasks.tfmd`, worked by the agent on the owner's commands.
The `.tf` is always `$HOME/.tf`, wherever the agent was started; it serves every project below
`$HOME` (the task's `/ :` line says which).

Before acting, read `$HOME/.tf/skill/base.md` (the format, the built-in tags, and the built-in
commands with their full definitions) and `$HOME/.tf/tasks.tfmd` (the tasks). They are the source
of truth. When the owner types `tf ...`, find the command in `## commands` of `base.md` and do what
its definition says.
