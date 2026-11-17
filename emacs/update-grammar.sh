#!/usr/bin/env bash
# Builds the tfmd tree-sitter grammar and installs it for Emacs, so it matches tf-ts-mode.
# Needs a C compiler (cc). Run it after every package-vc-upgrade of tf-ts-mode; `C-c C-u` in a
# .tfmd buffer runs it after .tf/update.sh.
# The grammar is taken from tree-sitter-tfmd/ next to this script's folder when it is there (a
# clone or the package-vc checkout), otherwise from a fresh clone of $TF_REPO.
# The library goes to $TF_TS_DIR (default ~/.emacs.d/tree-sitter). Emacs keeps a loaded library:
# restart it afterwards.
set -euo pipefail

repo="${TF_REPO:-https://github.com/blitzarx1/tf}"
dest="${TF_TS_DIR:-$HOME/.emacs.d/tree-sitter}"
case "$(uname)" in
	Darwin) ext=dylib ;;
	MINGW*|MSYS*|CYGWIN*) ext=dll ;;
	*) ext=so ;;
esac

here="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$here/../tree-sitter-tfmd/src/parser.c" ]; then
	src="$here/../tree-sitter-tfmd"
else
	tmp="$(mktemp -d)"
	trap 'rm -rf "$tmp"' EXIT
	git clone -q --depth 1 "$repo" "$tmp/tf"
	src="$tmp/tf/tree-sitter-tfmd"
fi
echo "grammar source: $src"

files=("$src/src/parser.c")
[ -f "$src/src/scanner.c" ] && files+=("$src/src/scanner.c")
mkdir -p "$dest"
out="$dest/libtree-sitter-tfmd.$ext"
# Replaced by a rename, never rewritten in place: a running Emacs may have it mapped.
cc -shared -fPIC -O2 -I "$src/src" "${files[@]}" -o "$out.new"
if [ -f "$out" ] && cmp -s "$out.new" "$out"; then
	rm "$out.new"
	echo "$out: unchanged"
else
	status=created
	[ -f "$out" ] && status=updated
	mv "$out.new" "$out"
	echo "$out: $status"
fi
echo "Restart Emacs to load the grammar."
