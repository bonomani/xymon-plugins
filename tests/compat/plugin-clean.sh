#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-clean.sh
#
# clean takes away what no installed plugin owns (S31). In a scratch Xymon
# tree and home, a plugin "gone" left, as when its directory is deleted by
# hand (S9), its task link, its manual page's link, its staged copy and its
# command; beside them, what is not provably a plugin's. clean needs a name
# or --all, refuses an installed plugin's name, says the target and lists
# what it will remove; off a terminal it removes nothing without --yes and
# exits 4; on one, N removes nothing, y removes it. It takes only what is
# provably a plugin's, leaving and saying the rest, and the exit code says
# the state after it: 0 nothing left, 4 something left. --all takes the
# stage and the virtualenv once no plugin is installed. The person's data
# stays.

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
py=${XYMONAPI_PYTHON:-python3}

x() { "$ROOT/xymon-plugin" "$@" </dev/null >"$work/x.log" 2>&1 || fail "xymon-plugin $* failed: $(tail -n 5 "$work/x.log")"; }
# c WANT ARGS... -- clean ARGS off a terminal, its exit code WANT; its output in $out.
c() {
	want=$1; shift
	rc=0; out=$("$ROOT/xymon-plugin" clean "$@" </dev/null 2>&1) || rc=$?
	[ "$rc" -eq "$want" ] || fail "[S31] clean $* exited $rc, not $want: $out"
}
print() { (cd "$work" && find server home man | sort); }

x install --server xymonapi XYMONHOME="$home"
x install --tools xymonapi-mcp
mkdir -p "$XDG_CONFIG_HOME/xymonapi"; echo "mine" > "$XDG_CONFIG_HOME/xymonapi/xymon.url"

# What "gone" left on the server.
leave() {
	mkdir -p "$home/ext/xymon-plugins-dist/plugins/gone" "$MANDIR/man8"
	: > "$home/ext/xymon-plugins-dist/plugins/gone/PLUGIN"
	ln -sf "$home/ext/gone/tasks.cfg" "$home/etc/tasks.d/gone.cfg"
	ln -sf "$home/ext/gone/gone.8" "$MANDIR/man8/gone.8"
}
leave
# Not a plugin's: a link to elsewhere, and a regular file.
ln -s /etc/hostname "$home/etc/tasks.d/admin.cfg"
echo "the admin's" > "$home/etc/tasks.d/gone-notes.cfg"

# A name, or --all; never an installed plugin's.
rc=0; out=$("$ROOT/xymon-plugin" clean --server XYMONHOME="$home" </dev/null 2>&1) || rc=$?
[ "$rc" -ne 0 ] || fail "clean with no name was taken"
assert_contains "name the plugins to clean, or --all" "$out" "[S31] clean needs a name or --all"
rc=0; out=$("$ROOT/xymon-plugin" clean --server xymonapi XYMONHOME="$home" </dev/null 2>&1) || rc=$?
[ "$rc" -ne 0 ] || fail "clean of an installed plugin was taken"
assert_contains "xymonapi is installed: ./xymon-plugin remove --server xymonapi" "$out" "[S31] an installed plugin's name is refused, naming remove"

# Off a terminal, without --yes: listed, nothing removed, 4.
before=$(print)
c 4 --server gone XYMONHOME="$home"
assert_contains "Target: $home" "$out" "[S31] it says the target"
assert_contains "$home/etc/tasks.d/gone.cfg, the task link of gone" "$out" "[S31] and lists the task link"
assert_contains "$MANDIR/man8/gone.8, a manual page's link of gone" "$out" "[S31] the manual page's link"
assert_contains "the staged copy of gone" "$out" "[S31] the staged copy"
assert_contains "Nothing removed: off a terminal, --yes removes it." "$out" "[S31] and off a terminal removes nothing without --yes"
[ "$before" = "$(print)" ] || fail "[S31] clean without --yes changed something"

# On a terminal: N removes nothing, 4; y removes it, 0.
rc=0; out=$("$py" "$ROOT/tests/lib/answer.py" 'Proceed? [y/N] ' n -- "$ROOT/xymon-plugin" clean --server gone XYMONHOME="$home" 2>&1) || rc=$?
[ "$rc" -eq 4 ] || fail "[S31] N exited $rc, not 4: $out"
assert_contains "Nothing removed." "$out" "[S31] N removes nothing, exit 4"
[ "$before" = "$(print)" ] || fail "[S31] N changed something"
rc=0; out=$("$py" "$ROOT/tests/lib/answer.py" 'Proceed? [y/N] ' y -- "$ROOT/xymon-plugin" clean --server gone XYMONHOME="$home" 2>&1) || rc=$?
[ "$rc" -eq 0 ] || fail "[S31] y exited $rc, not 0: $out"
assert_contains "Removed $home/etc/tasks.d/gone.cfg" "$out" "[S31] y removes it, saying each, exit 0"
for p in "$home/etc/tasks.d/gone.cfg" "$MANDIR/man8/gone.8" "$home/ext/xymon-plugins-dist/plugins/gone"; do
	[ ! -e "$p" ] && [ ! -L "$p" ] || fail "[S31] $p is still there"
done
[ -L "$home/etc/tasks.d/admin.cfg" ] && [ -f "$home/etc/tasks.d/gone-notes.cfg" ] || fail "[S31] what is no plugin's was taken"
[ -L "$home/etc/tasks.d/xymonapi.cfg" ] || [ ! -e "$home/etc/tasks.d/xymonapi.cfg" ] || fail "an installed plugin was touched"
[ -f "$home/ext/xymonapi/MANIFEST" ] || fail "[S31] an installed plugin's directory was touched"
c 0 --server gone XYMONHOME="$home"
assert_contains "Nothing is left that no plugin installed owns." "$out" "[S31] with nothing left, it says so, exit 0"

# --yes, off a terminal.
leave
c 0 --server gone --yes XYMONHOME="$home"
[ ! -L "$home/etc/tasks.d/gone.cfg" ] || fail "[S31] --yes removed nothing"

# Your tools: a command an install writes, byte for byte, goes; one that
# differs is left, said, and the exit says something is left.
wr() { printf '#!/bin/sh\nexec "%s/libexec/xymon-plugins/%s/gone.sh" "$@"\n' "$PREFIX" "$1"; }
wr gone > "$PREFIX/bin/gone"
{ wr gone2; echo "# mine"; } > "$PREFIX/bin/gone-mine"
c 4 --tools gone gone2 --yes
assert_contains "Target: your tools, $PREFIX" "$out" "[S31] for the tools, the target is said"
assert_contains "Removed $PREFIX/bin/gone" "$out" "[S31] a command byte for byte an install's is removed"
assert_contains "Left: $PREFIX/bin/gone-mine, the command of gone2: not, byte for byte, what an install writes" "$out" "[S31] one that differs is left and said, exit 4"
[ ! -e "$PREFIX/bin/gone" ] && [ -f "$PREFIX/bin/gone-mine" ] || fail "[S31] the wrong command went"
rm "$PREFIX/bin/gone-mine"

# --all: once the directories are deleted by hand, every plugin's leftover,
# the stage and the virtualenv.
mkdir -p "$home/ext/venv/bin"
rm -rf "$home/ext/xymonapi"
c 0 --server --all --yes XYMONHOME="$home"
assert_contains "the stage /plugins serves, with no plugin installed" "$out" "[S31] --all takes the stage with no plugin installed"
assert_contains "the virtualenv, with no plugin installed" "$out" "[S31] and the virtualenv"
[ ! -e "$home/ext/xymon-plugins-dist" ] && [ ! -e "$home/ext/venv" ] && [ ! -e "$MANDIR/man8/xymonapi.8" ] \
	|| fail "[S31] --all left something: $(ls -a "$home/ext" "$MANDIR/man8")"
rc=0; v=$("$ROOT/xymon-plugin" verify --server XYMONHOME="$home" </dev/null 2>&1) || rc=$?
[ "$rc" -eq 0 ] || fail "[S31] verify after clean --all exited $rc: $v"

# S8: the removal of the last plugin of a part takes the virtualenv too;
# one plugin removed of two leaves it. xymonapi-mcp, and xymonapi it
# needs, are the tools installed.
mkdir -p "$PREFIX/libexec/xymon-plugins/venv/bin"
x remove --tools xymonapi-mcp
[ -d "$PREFIX/libexec/xymon-plugins/venv" ] || fail "[S8] the virtualenv went while a plugin is still installed"
x remove --tools xymonapi
[ ! -e "$PREFIX/libexec/xymon-plugins/venv" ] || fail "[S8] the removal of the last plugin left the virtualenv"
assert_contains "Removed the virtualenv, which no plugin uses now." "$(cat "$work/x.log")" "[S8] and says so"
x install --server xymonapi XYMONHOME="$home"
mkdir -p "$home/ext/venv/bin"
x remove --server xymonapi XYMONHOME="$home"
assert_contains "Removed the stage /plugins serves, which no plugin uses now." "$(cat "$work/x.log")" "[S8] the stage's going is said too"
[ ! -e "$home/ext/venv" ] && [ ! -e "$home/ext/xymon-plugins-dist" ] || fail "[S8] the server's last removal left the virtualenv or the stage"

# The person's data stays.
assert_equal "mine" "$(cat "$XDG_CONFIG_HOME/xymonapi/xymon.url")" "[S31] a data: directory is never cleaned"

pass "clean takes away, listed and confirmed, only what is provably a plugin's that is gone -- its task link, manual page's link, staged copy and command, and with --all the stage and virtualenv no plugin uses -- exiting 0 when nothing is left, 4 when something is"
