#!/usr/bin/env bash
# Wires tf into a projects directory: the folder that holds .tf and the projects below it. Run it
# from the directory to use, right after cloning:
#   git clone https://github.com/blitzarx1/tf .tf && .tf/install.sh
# It asks to confirm or change the projects directory (default: where .tf was cloned; set
# TF_PROJECTS_DIR to answer in advance). Safe to run again: every step checks first.
set -euo pipefail

tf_dir="$(cd "$(dirname "$0")" && pwd)"
[ -f "$tf_dir/tasks.tfmd" ] || { echo "run it as .tf/install.sh, with tf cloned into .tf" >&2; exit 1; }

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

# The projects directory: the root of this .tf. If it is not where .tf is now, .tf moves there.
default_root="$(dirname "$tf_dir")"
root="${TF_PROJECTS_DIR:-}"
if [ -z "$root" ]; then
	root="$default_root"
	if [ -t 0 ]; then
		read -r -p "Projects directory [$default_root]: " answer
		root="${answer:-$default_root}"
	fi
fi
root="${root/#\~/$HOME}"
mkdir -p "$root"
root="$(cd "$root" && pwd)"
if [ "$root/.tf" != "$tf_dir" ]; then
	[ -e "$root/.tf" ] && { echo "$root/.tf already exists; remove it or pick another directory" >&2; exit 1; }
	mv "$tf_dir" "$root/.tf"
fi
cd "$root"
echo "projects directory: $root"

# A plain copy you edit in place, not a clone: updates go through .tf/update.sh. The version is
# read from git first, while .tf/.git is still there.
[ -d .tf/.git ] && write_version .tf .tf/VERSION
rm -rf .tf/.git

# .tf/skill holds SKILL.md at its root, so that folder is the skill. It is copied (not linked) to
# where the agents look for skills; an old symlink there is replaced by the copy.
for dir in .claude/skills .agents/skills; do
	mkdir -p "$dir"
	rm -rf "$dir/tf"
	cp -R .tf/skill "$dir/tf"
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

# clean up the
rm -f .tf/README.md .tf/install.sh
rm -rf .tf/emacs .tf/tree-sitter-tfmd
echo "tf $(show_version .tf/VERSION) installed in $root: tasks in .tf/tasks.tfmd; add tasks there yourself, use '/tf' command with claude or codex from $root to work with them."
