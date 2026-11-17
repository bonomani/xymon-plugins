#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-verify.sh
#
# verify says what differs from what was installed (S30), one line each,
# and changes nothing. In a scratch Xymon tree and home, xymonapi's server
# part and xymonapi-mcp's tools are installed; then each case is made, one
# at a time, verify run, its line and exit code checked, and an update puts
# it right: a file changed, missing, or added that runs, a __pycache__ (the
# launchers write no bytecode), a file added that does not run, a file
# added to the copy /plugins serves, the manual page's link and the task
# link pointing elsewhere, no MANIFEST, a Python module older than its
# requirements.txt asks; the administrator's task file edited, said and
# counted for nothing; and what no plugin installed owns, untidy. It exits
# 0, 3 when something is broken, 4 when something is untidy and nothing
# broken.

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
ext=$home/ext/xymonapi
dist=$home/ext/xymon-plugins-dist/plugins/xymonapi

x() { "$ROOT/xymon-plugin" "$@" </dev/null >"$work/x.log" 2>&1 || fail "xymon-plugin $* failed: $(tail -n 5 "$work/x.log")"; }
# v WANT ARGS... -- verify ARGS, its exit code WANT; its output in $out.
v() {
	want=$1; shift
	rc=0; out=$("$ROOT/xymon-plugin" verify "$@" </dev/null 2>&1) || rc=$?
	[ "$rc" -eq "$want" ] || fail "[S30] verify $* exited $rc, not $want: $out"
}
fix() { x update --server xymonapi XYMONHOME="$home"; v 0 --server XYMONHOME="$home"; }

x install --server xymonapi XYMONHOME="$home"
x enable --server xymonapi XYMONHOME="$home"
x install --tools xymonapi-mcp

v 0 --server XYMONHOME="$home"
assert_contains "ok: xymonapi" "$out" "[S30] a plugin as installed is ok, exit 0"
v 0 --tools
assert_contains "ok: xymonapi-mcp" "$out" "[S30] and the tools too"
v 0
assert_contains "Xymon server: $home" "$out" "[S30] with no part named, every installation found"
assert_contains "Your tools: $PREFIX" "$out" "[S30] and the tools"

# Broken: exit 3, with the command that puts it right.
echo "# changed" >> "$ext/app.py"
v 3 --server XYMONHOME="$home"
assert_contains "broken: xymonapi: app.py changed: ./xymon-plugin update --server xymonapi" "$out" "[S30] a file changed is broken, naming update"
fix
rm "$ext/xymon.py"
v 3 --server XYMONHOME="$home"
assert_contains "broken: xymonapi: xymon.py missing" "$out" "[S30] a file missing is broken"
fix
echo 'print(1)' > "$ext/sitecustomize.py"
v 3 --server XYMONHOME="$home"
assert_contains "broken: xymonapi: sitecustomize.py, which can run, is not what was installed" "$out" "[S30] a file added that can be imported is broken"
fix
mkdir "$ext/__pycache__"; : > "$ext/__pycache__/tokens.cpython-312.pyc"
v 3 --server XYMONHOME="$home"
assert_contains "broken: xymonapi: __pycache__, bytecode no install wrote" "$out" "[S30] a __pycache__ is broken"
fix
: > "$dist/notes.txt"
v 3 --server XYMONHOME="$home"
assert_contains "notes.txt, served at /plugins, is not what was staged" "$out" "[S30] any file added to the copy /plugins serves is broken"
fix
ln -sf /nowhere "$MANDIR/man8/xymonapi.8"
v 3 --server XYMONHOME="$home"
assert_contains "broken: xymonapi: the link $MANDIR/man8/xymonapi.8 points to /nowhere" "$out" "[S30] a link outside pointing elsewhere is broken"
fix
ln -sf /nowhere "$home/etc/tasks.d/xymonapi.cfg"
v 3 --server XYMONHOME="$home"
assert_contains "broken: xymonapi: its task link xymonapi.cfg points to /nowhere" "$out" "[S30] the task link pointing elsewhere is broken"
rm "$home/etc/tasks.d/xymonapi.cfg"; x enable --server xymonapi XYMONHOME="$home"
v 0 --server XYMONHOME="$home"
# A module older than requirements.txt asks: a distribution of an old
# version found first on the path.
mkdir -p "$work/old/fastapi-0.1.dist-info"
printf 'Metadata-Version: 2.1\nName: fastapi\nVersion: 0.1\n' > "$work/old/fastapi-0.1.dist-info/METADATA"
PYTHONPATH="$work/old" v 3 --server XYMONHOME="$home"
assert_contains "older Python modules than it is tested with, fastapi>=" "$out" "[S30] a module older than requirements.txt asks is broken"
assert_contains "./xymon-plugin update --server --venv xymonapi" "$out" "[S30] naming update --venv"

# Untidy alone: exit 4.
: > "$ext/notes.txt"
v 4 --server XYMONHOME="$home"
assert_contains "untidy: xymonapi: notes.txt is not what was installed" "$out" "[S30] a file added that does not run is untidy, exit 4"
fix
mv "$ext/MANIFEST" "$work/MANIFEST.kept"
v 4 --server XYMONHOME="$home"
assert_contains "untidy: xymonapi: no MANIFEST, installed before it was kept: ./xymon-plugin update --server xymonapi" "$out" "[S30] a plugin with no MANIFEST is untidy"
fix

# The administrator's file, edited: said, and counted for nothing.
echo "# mine" >> "$ext/tasks.cfg"
v 0 --server XYMONHOME="$home"
assert_contains "edited: xymonapi: tasks.cfg, the administrator's" "$out" "[S30] the task file edited is said, exit 0"

# What no plugin installed owns: untidy, naming clean; not with a plugin named.
mkdir -p "$home/ext/xymon-plugins-dist/plugins/gone"
ln -s "$home/ext/gone/tasks.cfg" "$home/etc/tasks.d/gone.cfg"
ln -s "$home/ext/gone/gone.8" "$MANDIR/man8/gone.8"
v 4 --server XYMONHOME="$home"
assert_contains "untidy: $home/etc/tasks.d/gone.cfg, the task link of gone, which is gone: ./xymon-plugin clean --server gone" "$out" "[S30] a task link of a plugin gone is untidy"
assert_contains "untidy: $MANDIR/man8/gone.8, a manual page's link of gone" "$out" "[S30] and a manual page's link"
assert_contains "the staged copy of gone" "$out" "[S30] and a staged copy"
v 0 --server xymonapi XYMONHOME="$home"
printf '#!/bin/sh\nexec "%s/libexec/xymon-plugins/gone/gone.sh" "$@"\n' "$PREFIX" > "$PREFIX/bin/gone"
v 4 --tools
assert_contains "untidy: $PREFIX/bin/gone, the command of gone, which is gone: ./xymon-plugin clean --tools gone" "$out" "[S30] a command of a plugin gone is untidy"
rm -rf "$home/ext/xymon-plugins-dist/plugins/gone" "$home/etc/tasks.d/gone.cfg" "$MANDIR/man8/gone.8" "$PREFIX/bin/gone"

# Broken and untidy both: 3; and verify changes nothing, every path and
# its content the same after as before.
echo "# changed" >> "$ext/app.py"; : > "$ext/notes.txt"
print() { (cd "$work" && find server home man | sort && find server home man -type f -exec cksum {} + | sort); }
before=$(print)
v 3
after=$(print)
[ "$before" = "$after" ] || fail "[S30] verify changed something: $(diff <(echo "$before") <(echo "$after"))"
fix

# The launchers write no bytecode.
# The MCP server reads requests on its input: an empty one, and it stops
# once it has imported its modules.
"$PREFIX/bin/xymonapi-mcp" </dev/null >/dev/null 2>&1 || :
[ ! -d "$PREFIX/libexec/xymon-plugins/xymonapi-mcp/__pycache__" ] && [ ! -d "$PREFIX/libexec/xymon-plugins/xymonapi/__pycache__" ] \
	|| fail "[S30] a launcher wrote a __pycache__"
v 0 --tools

# A part with both selectors is refused.
rc=0; out=$("$ROOT/xymon-plugin" verify --server --tools </dev/null 2>&1) || rc=$?
[ "$rc" -ne 0 ] || fail "verify --server --tools was taken"
assert_contains "with neither, covers both" "$out" "[S30] --server --tools is refused, saying verify covers both"

pass "verify says, one line each, what differs from what was installed -- broken (exit 3), untidy (exit 4), the administrator's edited and ok (exit 0) -- naming update or clean; the launchers write no bytecode"
