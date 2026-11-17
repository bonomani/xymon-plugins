#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-locations.sh
#
# A plugin writes only where S28 says. In a scratch Xymon tree and a
# scratch home, every plugin of each part is installed, updated and
# removed; after each, every path in the whole scratch area is compared
# with before, and a new one is taken only where S28 lists it: the
# plugin's directory, its task link, its manual page's link, its command,
# the stage /plugins serves, the virtualenv beside the plugins, and the
# installation used last. Nothing there before is gone. A data: line
# outside the four roots, or in the name of a plugin it does not need,
# and a writes: line that is not a file and its command, are refused
# before anything is written.
#
# What a plugin writes while it runs -- its data: and writes: -- is
# declared, not run here: the plugins' own tests run them with a scratch
# home.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
home=$work/server
server_tree "$home"
person=$work/home
mkdir -p "$person"
export HOME="$person" XDG_CONFIG_HOME="$person/.config" PREFIX="$person/.local" MANDIR="$work/man"
export XYMON_PLUGINS_TREES_ONLY=1 XYMON_PLUGINS_TREES="$home"
plugins=$(cd "$ROOT/plugins" && ls)

# snap FILE -- every path under the scratch area, but the snapshots.
snap() { find "$work" -mindepth 1 -path "$work/snap*" -prune -o -print | sort > "$work/$1"; }

# allowed PATH -- true when S28 lists PATH, or a directory one lies in.
allowed() {
	p=$1
	for a in "$home/ext" "$home/etc" "$home/etc/tasks.d" "$work/man" "$person/.config" "$person/.config/xymon-plugin" \
		"$PREFIX" "$PREFIX/bin" "$PREFIX/libexec" "$PREFIX/share" "$PREFIX/share/man" "$PREFIX/share/man/man1"; do
		[ "$p" = "$a" ] && return 0
	done
	case $p in
		"$work/man/man"[1-8]|"$work/man/man"[1-8]/*) return 0 ;;
		"$home/ext/venv"|"$home/ext/venv/"*|"$home/ext/xymon-plugins-dist"|"$home/ext/xymon-plugins-dist/"*) return 0 ;;
		"$PREFIX/libexec/xymon-plugins"|"$PREFIX/libexec/xymon-plugins/"*) return 0 ;;
		"$person/.config/xymon-plugin/installation-used-last") return 0 ;;
	esac
	for n in $plugins; do
		case $p in
			"$home/ext/$n"|"$home/ext/$n/"*|"$home/etc/tasks.d/$n.cfg") return 0 ;;
			"$PREFIX/bin/"*) return 0 ;;
			"$PREFIX/share/man/man1/"*) return 0 ;;
		esac
	done
	return 1
}

# check STEP -- what STEP left beside the "before" snapshot: nothing gone,
# nothing new outside the places S28 lists.
check() {
	snap "snap-$1"
	gone=$(comm -23 "$work/snap-before" "$work/snap-$1")
	[ -z "$gone" ] || fail "[S28] $1 removed what was there before: $gone"
	comm -13 "$work/snap-before" "$work/snap-$1" | while IFS= read -r p; do
		allowed "$p" || fail "[S28] $1 wrote $p, which S28 does not list"
	done
}

x() { "$ROOT/xymon-plugin" "$@" XYMONHOME="$home" </dev/null >"$work/snaplog-x" 2>&1 || fail "xymon-plugin $* failed: $(tail -n 5 "$work/snaplog-x")"; }

snap snap-before
x install --server --all;  check "install --server"
x update --server;         check "update --server"
x install --tools --all;   check "install --tools"
x update --tools;          check "update --tools"
x remove --tools --all;    check "remove --tools"
x remove --server --all;   check "remove --server"
# After the removals, only directories and the installation used last stay.
comm -13 "$work/snap-before" "$work/snap-remove --server" | while IFS= read -r p; do
	[ -d "$p" ] || [ "$p" = "$person/.config/xymon-plugin/installation-used-last" ] \
		|| fail "[S28] a removal left $p"
done

# Lines S28 does not allow are refused before anything is written. A copy
# of the checkout plays each.
bad() { # LOG LINE -- xymonapi-rag's PLUGIN given LINE, then installed
	r=$work/bad-$1; rm -rf "$r"; mkdir -p "$r"
	cp -R "$ROOT/xymon-plugin" "$ROOT/LICENSE" "$ROOT/plugins" "$r/"
	printf '%s\n' "$2" >> "$r/plugins/xymonapi-rag/PLUGIN"
	snap snap-bad
	rc=0; "$r/xymon-plugin" install --tools xymonapi-rag </dev/null >"$work/snaplog-bad-$1" 2>&1 || rc=$?
	[ "$rc" -ne 0 ] || fail "[S28] $2 was taken"
	snap snap-bad-after
	diff -q "$work/snap-bad" "$work/snap-bad-after" >/dev/null || fail "[S28] $2 was refused, but something was written first"
}
bad root 'data: /var/tmp/xymonapi-rag/'
assert_contains "no directory S28 allows" "$(cat "$work/snaplog-bad-root")" "[S28] a data: line outside the four roots is refused, saying why"
bad other 'data: $XDG_STATE_HOME/xymonapi-agent/'
assert_contains "neither xymonapi-rag nor a plugin it needs" "$(cat "$work/snaplog-bad-other")" "[S28] a data: line in the name of a plugin it does not need is refused"
bad nocmd 'writes: ~/.bashrc'
assert_contains "the command that changes it" "$(cat "$work/snaplog-bad-nocmd")" "[S28] a writes: line without its command is refused"
bad dir 'writes: ~/.config/ (xymonapi-rag search)'
assert_contains "names no single file" "$(cat "$work/snaplog-bad-dir")" "[S28] a writes: line naming a directory is refused"
# A plugin it needs may lend its name: xymonapi-rag needs xymonapi.
bad2=$work/good; rm -rf "$bad2"; mkdir -p "$bad2"
cp -R "$ROOT/xymon-plugin" "$ROOT/LICENSE" "$ROOT/plugins" "$bad2/"
printf 'data: $XDG_CONFIG_HOME/xymonapi/\n' >> "$bad2/plugins/xymonapi-rag/PLUGIN"
"$bad2/xymon-plugin" install --tools xymonapi-rag </dev/null >"$work/snaplog-good" 2>&1 \
	|| fail "[S28] a data: line in the name of a plugin it needs was refused: $(tail -n 3 "$work/snaplog-good")"

# The command keeps no file of its own anywhere else, not even for a moment
# in TMPDIR: a success, a refusal, a die.
mkdir -p "$work/snaptmp"
for args in "status" "verify --tools" "install --tools nosuchplugin" "install --server xymonapi XYMONHOME=$work/nowhere"; do
	# shellcheck disable=SC2086
	TMPDIR="$work/snaptmp" "$ROOT/xymon-plugin" $args </dev/null >/dev/null 2>&1 || :
done
TMPDIR="$work/snaptmp" "$work/bad-root/xymon-plugin" install --tools xymonapi-rag </dev/null >/dev/null 2>&1 || :
left=$(ls -A "$work/snaptmp")
[ -z "$left" ] || fail "[S28] a run left in TMPDIR: $left"

pass "a plugin writes only where S28 lists, at install, update and removal of each part, a removal leaving only directories and the installation used last; data: and writes: lines S28 does not allow are refused before anything is written"
