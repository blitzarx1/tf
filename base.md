# tf base

Belongs to tf: `.tf/update.sh` replaces it. The format of `tf.md` and the built-in tags and
commands. Your own tags and commands go in the `# tags` and `# commands` sections of `tf.md`.

## format

* `tf.md` has five sections: `# todo`, `# backlog`, `# done`, `# tags`, `# commands`.
* Tasks separated from each other with 32 dashes: `--------------------------------`.
* The tf.md file should have 100 line strict word wrapping rule.
* No tabs should be used, only whitespaces

## tags

Standard set of tags for marking tasks:

- ?    Question which requires only answer without any changes to be made.
- b    Bug
- epic Potentially huge task which requires decomposition and creation of custom tags to mark
       connected tasks

## task header

Task header identifies the task and its main properties.

- [ ] <title>
  <priority>
  <tag1,tag2>

## task state

- [ ] not done
- [x] done
- ~~[ ] <title>~~ cancelled

A cancelled task's title is struck through: `~~` goes before `[ ]` and after the last word
of the title, even when the title wraps.

## task body

Task body provides more context, cocreate examples and task updates.
Task body fields should be separated with newline from task header.
There can be multiple task fields separated with newline from each other.

  D : <description>
  C : <comment>

## commands

A command is typed by the owner and run by the agent. One entry per command, entries separated by
a blank line; the `D : ` field wraps like a task body. Names start with `tf ` and can't reuse a
built-in.

- tf <name> <args>

  D : <what the agent does; <args> are filled in from what the owner typed>

Built-in commands (the rules are in `.tf/AGENTS.md`):

- tf

  D : Work the first open item of `# todo` ("Working an item").

- tf <n>

  D : Work the first `<n>` open items of `# todo` with one plan and one approval ("Working
      several items").

- tf migrate <path>

  D : Import the tasks of another tracker, a file or a folder, into `tf.md`, with a preview
      before writing ("Migrating a tracker").
