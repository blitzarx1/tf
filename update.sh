#!/usr/bin/env bash
# Updates tf in place. Run from the project root: .tf/update.sh
# Replaces AGENTS.md, SKILL.md, base.md, VERSION and this script with the latest versions. Never
# touches tf.md: your tasks stay as they are.
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
[ -f .tf/tf.md ] || { echo "run from the project root (no .tf/tf.md here)" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# No --depth: describe needs the tags and history (blobs of old versions are still skipped).
git clone -q --filter=blob:none "$repo" "$tmp/tf"
write_version "$tmp/tf" "$tmp/tf/VERSION"
old="$(show_version .tf/VERSION)"
new="$(show_version "$tmp/tf/VERSION")"

# Each file is replaced by a rename, never rewritten in place: bash is still reading this script.
for f in base.md AGENTS.md SKILL.md VERSION update.sh; do
	if cmp -s "$tmp/tf/$f" ".tf/$f"; then
		echo "  $f: unchanged"
	else
		cp "$tmp/tf/$f" ".tf/$f.new" && mv ".tf/$f.new" ".tf/$f"
		echo "  $f: updated"
	fi
done
chmod +x .tf/update.sh
if [ "$old" = "$new" ]; then
	echo "tf $new (already up to date)."
else
	echo "tf updated: $old -> $new."
fi
