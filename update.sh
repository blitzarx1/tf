#!/usr/bin/env bash
# Updates tf in place. Run from the project root: .tf/update.sh
# Replaces AGENTS.md, SKILL.md, this script and the "# info" section of tf.md with the latest
# versions. Everything in tf.md above "# info" (todo, backlog, done, custom tags) stays as it is.
set -euo pipefail

repo="${TF_REPO:-https://github.com/blitzarx1/tf}"
[ -f .tf/tf.md ] || { echo "run from the project root (no .tf/tf.md here)" >&2; exit 1; }
grep -qx '# info' .tf/tf.md || { echo ".tf/tf.md has no \"# info\" heading; not touching it" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git clone -q --depth 1 "$repo" "$tmp/tf"
grep -qx '# info' "$tmp/tf/tf.md" || { echo "the new tf.md has no \"# info\" heading" >&2; exit 1; }

cp .tf/tf.md .tf/tf.md.bak
{
	sed '/^# info$/,$d' .tf/tf.md
	sed -n '/^# info$/,$p' "$tmp/tf/tf.md"
} > "$tmp/tf.md"

# Each file is replaced by a rename, never rewritten in place: bash is still reading this script.
for f in tf.md AGENTS.md SKILL.md update.sh; do
	src="$tmp/tf/$f"
	[ "$f" = tf.md ] && src="$tmp/tf.md"
	if cmp -s "$src" ".tf/$f"; then
		echo "  $f: unchanged"
	else
		cp "$src" ".tf/$f.new" && mv ".tf/$f.new" ".tf/$f"
		echo "  $f: updated"
	fi
done
chmod +x .tf/update.sh
echo "tf updated (previous task file in .tf/tf.md.bak)."
