#!/usr/bin/env bash
# Updates tf in place. Run from the project root: .tf/update.sh
# Replaces AGENTS.md, SKILL.md, base.md and this script with the latest versions. Never touches
# tf.md: your tasks stay as they are.
set -euo pipefail

repo="${TF_REPO:-https://github.com/blitzarx1/tf}"
[ -f .tf/tf.md ] || { echo "run from the project root (no .tf/tf.md here)" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git clone -q --depth 1 "$repo" "$tmp/tf"

# Each file is replaced by a rename, never rewritten in place: bash is still reading this script.
for f in base.md AGENTS.md SKILL.md update.sh; do
	if cmp -s "$tmp/tf/$f" ".tf/$f"; then
		echo "  $f: unchanged"
	else
		cp "$tmp/tf/$f" ".tf/$f.new" && mv ".tf/$f.new" ".tf/$f"
		echo "  $f: updated"
	fi
done
chmod +x .tf/update.sh
echo "tf updated."
