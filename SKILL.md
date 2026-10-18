---
name: tf
description: Work the project's task file .tf/tf.md. Use when the owner types "tf" (take the first open item under "# todo" and work it) or "tf new <title>" (add a task to the top of "# backlog").
---

# tf

The rules are in `.tf/AGENTS.md`; read it before acting. The task file is `.tf/tf.md` and its
format is defined in its own `# info` section.

- `tf`: re-read `.tf/tf.md` from disk, take the first open item under `# todo` and work it as
  `.tf/AGENTS.md` describes (question, task, bug or epic). If `# todo` has no open item, say so.
- `tf new <title>`: add `- [ ] <title>` at the top of `# backlog`, with the 32-dash separator
  between it and the next item. Change nothing else.
