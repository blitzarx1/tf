# todo

# backlog

# done

# custom tags

Your own tags, which mark tasks with additional context (for example, the tasks an epic was split
into). One per line: `- <tag> <meaning>`. This section is yours: updates never touch it.

# info

This section belongs to tf: `.tf/update.sh` replaces it with the latest version. Keep it last.

## format

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
- [v] done
- [x] cancelled

## task body

Task body provides more context, cocreate examples and task updates.
Task body fields should be separated with newline from task header.
There can be multiple task fields separated with newline from each other.

  D : <description>
  C : <comment>
