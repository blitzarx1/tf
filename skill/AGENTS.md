# tf: task flow

This project keeps its tasks in `.tf/tasks.tfmd`, worked by the agent on the owner's commands.

Before acting, read `.tf/skill/base.md` (the format, the built-in tags, and the built-in commands
with their full definitions) and `.tf/tasks.tfmd` (the tasks). They are the source of truth.
When the owner types `tf ...`, find the command in `## commands` of `base.md` and do what its
definition says.
