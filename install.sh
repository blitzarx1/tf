#!/usr/bin/env bash
# Wires tf into the project. Run from the project root, right after cloning:
#   git clone https://github.com/blitzarx1/tf .tf && .tf/install.sh
# Safe to run again: every step checks first.
set -euo pipefail

[ -f .tf/tf.md ] || { echo "run from the project root, with tf cloned into .tf" >&2; exit 1; }

# A plain copy you edit in place, not a clone: updates go through .tf/update.sh.
rm -rf .tf/.git

# .tf holds SKILL.md at its root, so the folder itself is the skill.
for dir in .claude/skills .agents/skills; do
	mkdir -p "$dir"
	ln -sfn ../../.tf "$dir/tf"
done

# add_line FILE LINE: appends LINE to FILE (created if missing) unless it is already there.
add_line() {
	touch "$1"
	grep -qxF "$2" "$1" && return
	[ -s "$1" ] && [ -n "$(tail -c1 "$1")" ] && echo >> "$1"
	# Instructions files get a blank line first, so the line isn't glued to the last section.
	case "$1" in *.md) [ -s "$1" ] && echo >> "$1" ;; esac
	echo "$2" >> "$1"
	echo "  $1: added $2"
}
add_line CLAUDE.md "@.tf/AGENTS.md"                                   # Claude Code imports it
add_line AGENTS.md "Tasks: follow .tf/AGENTS.md (tf task flow)."      # Codex reads only the root AGENTS.md
for p in .tf/ .claude/skills/tf .agents/skills/tf; do
	add_line .gitignore "$p"
done

rm -f .tf/install.sh
echo "tf installed: tasks in .tf/tf.md; type \"tf\" to work the next one, \"tf new <title>\" to add one."
