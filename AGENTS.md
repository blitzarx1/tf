# tf: task flow

This project keeps its tasks in `.tf/tf.md`, worked by the agent on the owner's commands.

Before acting, read `.tf/base.md` (the format, the built-in tags, and the built-in commands with
their full definitions) and `.tf/tf.md` (the tasks, the project's own tags and commands). They are
the source of truth. When the owner types `tf ...`, find the command in `## commands` of `base.md`
or `# commands` of `tf.md` and do what its definition says.

Tasks: follow .tf/AGENTS.md (tf task flow).
