#!/usr/bin/env bash
# Installs tf into $HOME/.tf, the only place tf lives: tasks, skill, worktrees. Run it right after
# cloning:
#   git clone https://github.com/blitzarx1/tf ~/.tf && ~/.tf/install.sh
# From a clone elsewhere it moves the clone to $HOME/.tf (refusing if that exists). Asks nothing.
# It deletes itself when done; later updates go through update.sh.
set -euo pipefail

target="$HOME/.tf"
tf_dir="$(cd "$(dirname "$0")" && pwd)"
[ -f "$tf_dir/tasks.tfmd" ] || { echo "run it from the tf clone: git clone ... ~/.tf && ~/.tf/install.sh" >&2; exit 1; }
if [ "$tf_dir" != "$target" ]; then
	[ -e "$target" ] && { echo "$target already exists; remove it or run $target/update.sh" >&2; exit 1; }
	mv "$tf_dir" "$target"
fi
cd "$HOME"

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

# A plain folder you edit in place, not a clone: updates go through .tf/update.sh. The version is
# read from git first, while .tf/.git is still there.
[ -d .tf/.git ] && write_version .tf .tf/VERSION
rm -rf .tf/.git

# link_skill DIR: DIR/tf is a symlink to .tf/skill (an old copy or link there is replaced).
link_skill() {
	mkdir -p "$1"
	rm -rf "$1/tf"
	ln -s "$HOME/.tf/skill" "$1/tf"
	echo "  $1/tf -> $HOME/.tf/skill"
}
link_skill .claude/skills
link_skill .agents/skills

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

# Only tasks.tfmd, skill/, update.sh and VERSION stay.
rm -f .tf/README.md .tf/install.sh
rm -rf .tf/emacs .tf/tree-sitter-tfmd .tf/.agents .tf/.claude .tf/CLAUDE.md .tf/AGENTS.md .tf/.gitignore
echo "tf $(show_version .tf/VERSION) installed in $HOME/.tf: tasks in .tf/tasks.tfmd; use '/tf' with claude or codex from any folder."
