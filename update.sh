#!/usr/bin/env bash
# Updates tf in place: the .tf next to this script and every .tf below its home folder (the folder
# that holds it), so the whole subtree gets one version. Run it as .tf/update.sh from the home
# folder, or from any folder below it as ../.tf/update.sh.
# Replaces skill/ (AGENTS.md, SKILL.md, base.md), VERSION and update.sh with the latest versions,
# then refreshes the copies of skill/ in .claude/skills/tf and .agents/skills/tf of each home
# folder. A .tf above it (an ancestor) is only reported when its version differs.
# Never touches tasks.tfmd: your tasks stay as they are.
set -euo pipefail

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

repo="${TF_REPO:-https://github.com/blitzarx1/tf}"
root="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$root/.tf/tasks.tfmd" ] || { echo "no .tf/tasks.tfmd next to $0" >&2; exit 1; }
cd "$root"
echo "home folder: $root"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# No --depth: describe needs the tags and history (blobs of old versions are still skipped).
git clone -q --filter=blob:none "$repo" "$tmp/tf"
write_version "$tmp/tf" "$tmp/tf/VERSION"
new="$(show_version "$tmp/tf/VERSION")"

# find_tfs DIR: the home folders of the .tf folders in DIR and below (DIR first), skipping .git,
# .tf-worktrees and dependency folders, like the agent does.
find_tfs() {
	find "$1" \( -name .git -o -name .tf-worktrees -o -name node_modules -o -name vendor \) -prune \
		-o -type f -path '*/.tf/tasks.tfmd' -print | sed 's|/\.tf/tasks\.tfmd$||' | sort
}

# update_one HOME: updates the .tf in HOME and the copies of its skill.
update_one() {
	local home="$1" f dir status old
	old="$(show_version "$home/.tf/VERSION")"
	mkdir -p "$home/.tf/skill"
	# Each file is replaced by a rename, never rewritten in place: bash may be reading it.
	for f in skill/base.md skill/AGENTS.md skill/SKILL.md VERSION update.sh; do
		if cmp -s "$tmp/tf/$f" "$home/.tf/$f"; then
			echo "    $f: unchanged"
		else
			cp "$tmp/tf/$f" "$home/.tf/$f.new" && mv "$home/.tf/$f.new" "$home/.tf/$f"
			echo "    $f: updated"
		fi
	done
	chmod +x "$home/.tf/update.sh"
	# Refresh the copies of the skill (an old symlink there is replaced by the copy).
	for dir in .claude/skills .agents/skills; do
		mkdir -p "$home/$dir"
		if [ -L "$home/$dir/tf" ]; then
			status="symlink replaced by a copy"
		elif [ ! -e "$home/$dir/tf" ]; then
			status="created"
		elif diff -rq "$home/.tf/skill" "$home/$dir/tf" > /dev/null; then
			echo "    $dir/tf: unchanged"
			continue
		else
			status="updated"
		fi
		rm -rf "$home/$dir/tf"
		cp -R "$home/.tf/skill" "$home/$dir/tf"
		echo "    $dir/tf: $status"
	done
	if [ "$old" = "$new" ]; then
		echo "  $home/.tf: $new (already up to date)"
	else
		echo "  $home/.tf: updated $old -> $new"
	fi
}

while IFS= read -r home; do
	echo "$home/.tf:"
	update_one "$home"
done < <(find_tfs "$root")

# Ancestors are not touched, only reported when their version differs.
dir="$root"
while [ "$dir" != "/" ]; do
	dir="$(dirname "$dir")"
	if [ -f "$dir/.tf/tasks.tfmd" ] && [ "$(show_version "$dir/.tf/VERSION")" != "$new" ]; then
		echo "note: $dir/.tf is at $(show_version "$dir/.tf/VERSION"); run $dir/.tf/update.sh"
	fi
done
echo "tf $new in $root and the .tf folders below it."
