#!/usr/bin/env bash
# Wires tf into the project. Run from the project root, right after cloning:
#   git clone https://github.com/blitzarx1/tf .tf && .tf/install.sh
# Safe to run again: every step checks first.
set -euo pipefail

[ -f .tf/tf.md ] || { echo "run from the project root, with tf cloned into .tf" >&2; exit 1; }

# write_version REPO OUT: writes the tf version of the clone REPO to OUT. Line 1 is the release
# tag of the commit (no leading "v"), or the nearest earlier tag plus "-dev", or empty if there are
# no tags; line 2 is the commit hash.
write_version() {
	local tag
	tag="$(git -C "$1" describe --tags --exact-match 2>/dev/null)" \
		|| { tag="$(git -C "$1" describe --tags --abbrev=0 2>/dev/null)" && tag="$tag-dev"; } \
		|| tag=""
	printf '%s\n%s\n' "${tag#v}" "$(git -C "$1" rev-parse HEAD)" > "$2"
}

# show_version FILE: "0.1.0 (a4ac87d)" from a VERSION file, "unknown" if there is none.
show_version() {
	[ -f "$1" ] || { echo unknown; return; }
	local tag hash
	{ read -r tag; read -r hash; } < "$1"
	echo "${tag:+$tag }(${hash:0:7})"
}

# A plain copy you edit in place, not a clone: updates go through .tf/update.sh. The version is
# read from git first, while .tf/.git is still there.
[ -d .tf/.git ] && write_version .tf .tf/VERSION
rm -rf .tf/.git

# .tf/skill holds SKILL.md at its root, so that folder is the skill.
for dir in .claude/skills .agents/skills; do
	mkdir -p "$dir"
	ln -sfn ../../.tf/skill "$dir/tf"
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
add_line CLAUDE.md "@.tf/skill/AGENTS.md"                             # Claude Code imports it
add_line AGENTS.md "Tasks: follow .tf/skill/AGENTS.md (tf task flow)." # Codex reads only the root AGENTS.md
for p in .tf/ .claude/skills/tf .agents/skills/tf; do
	add_line .gitignore "$p"
done

# The README is for the repo page; install.sh runs once.
rm -f .tf/README.md .tf/install.sh
echo "tf $(show_version .tf/VERSION) installed: tasks in .tf/tf.md; add tasks there yourself, type \"tf\" to work the next one."
