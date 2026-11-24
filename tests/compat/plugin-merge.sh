#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-merge.sh
#
# An update meets the administrator's files -- the task file and the web
# server snippets -- with this version's and with the version they started
# from (S7). v1 is the checkout; v2 a copy whose xymonapi changes its
# apache snippet's first line and its task file's last. Edited elsewhere,
# off a terminal, a file is kept and v2's written beside it as NAME.new;
# on one, both changes are shown and y merges them, the file before kept
# as NAME.old; N keeps it, as off one. Edited on the same line, it is a
# conflict: kept, NAME.new beside it. Holding v2's change already, it is
# left, nothing said. Unedited, it takes v2's. A version
# that changes nothing leaves an edited file alone, with nothing beside
# it. verify says a .new or .old left, untidy.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
home=$work/server
server_tree "$home"
export HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" PREFIX="$work/home/.local" MANDIR="$work/man"
export XYMON_PLUGINS_TREES_ONLY=1 XYMON_PLUGINS_TREES="$home"
mkdir -p "$HOME"
py=${XYMONAPI_PYTHON:-python3}
ext=$home/ext/xymonapi
conf=$ext/xymonapi-apache.conf

# v2: its snippet's first line and its task file's last changed.
v2=$work/v2
mkdir -p "$v2"
cp -R "$ROOT/xymon-plugin" "$ROOT/LICENSE" "$ROOT/plugins" "$v2/"
t=$(sed -n 's/^server-task: //p' "$ROOT/plugins/xymonapi/PLUGIN")
{ echo "# v2's first line"; cat "$ROOT/plugins/xymonapi/xymonapi-apache.conf"; } > "$v2/plugins/xymonapi/xymonapi-apache.conf"
{ cat "$ROOT/plugins/xymonapi/$t"; echo "# v2's last line"; } > "$v2/plugins/xymonapi/$t"

# fresh -- xymonapi v1 installed anew.
fresh() {
	"$ROOT/xymon-plugin" remove --server xymonapi XYMONHOME="$home" </dev/null >/dev/null 2>&1 || :
	"$ROOT/xymon-plugin" install --server xymonapi XYMONHOME="$home" </dev/null >"$work/x.log" 2>&1 || fail "install: $(tail -n 3 "$work/x.log")"
}
up() { rc=0; out=$("$v2/xymon-plugin" update --server xymonapi XYMONHOME="$home" </dev/null 2>&1) || rc=$?; [ "$rc" -eq 0 ] || fail "update: $out"; }

# Edited elsewhere, off a terminal: kept, v2's beside it.
fresh
echo "# mine" >> "$conf"; echo "# mine" >> "$ext/tasks.cfg"
up
assert_contains "xymonapi-apache.conf is kept as yours; this version's, which merges with it without conflict, is beside it: diff $conf $conf.new" "$out" "[S7] off a terminal, an edited snippet that merges is kept, this version's beside it"
assert_contains "# mine" "$(cat "$conf")" "[S7] yours unchanged"
assert_not_contains "# v2's first line" "$(cat "$conf")" "[S7] nothing merged unattended"
assert_contains "# v2's first line" "$(cat "$conf.new")" "[S7] this version's in NAME.new"
assert_contains "tasks.cfg is kept as yours" "$out" "[S7] the task file too"
assert_contains "# v2's last line" "$(cat "$ext/tasks.cfg.new")" "[S7] its NAME.new"
rc=0; v=$("$v2/xymon-plugin" verify --server XYMONHOME="$home" </dev/null 2>&1) || rc=$?
assert_equal 4 "$rc" "[S7] verify: a .new left is untidy, exit 4"
assert_contains "untidy: xymonapi: xymonapi-apache.conf.new, this version's beside yours: compare, then remove it" "$v" "[S7] with a line of its own"

# On a terminal: y merges both, the file before kept as NAME.old; a
# NAME.old an earlier update kept is carried over, the older, as NAME.1.old.
fresh
echo "# mine" >> "$conf"
echo "# an earlier .old" > "$conf.old"
rc=0; out=$("$py" "$ROOT/tests/lib/answer.py" 'Apply both? [y/N] ' y -- "$v2/xymon-plugin" update --server xymonapi XYMONHOME="$home" 2>&1) || rc=$?
[ "$rc" -eq 0 ] || fail "update on a terminal: $out"
assert_contains "Your change:" "$out" "[S7] on a terminal, your change is shown"
assert_contains "This version's change:" "$out" "[S7] and this version's"
assert_contains "# v2's first line" "$(cat "$conf")" "[S7] y merges this version's change"
assert_contains "# mine" "$(cat "$conf")" "[S7] and keeps yours"
assert_not_contains "# v2's first line" "$(cat "$conf.old")" "[S7] the file before kept as NAME.old"
[ ! -e "$conf.new" ] || fail "[S7] a NAME.new was left after a merge"
assert_equal "# an earlier .old" "$(cat "$conf.1.old")" "[S7] the .old there before is carried over as NAME.1.old"
rc=0; v=$("$v2/xymon-plugin" verify --server XYMONHOME="$home" </dev/null 2>&1) || rc=$?
assert_contains "untidy: xymonapi: xymonapi-apache.conf.old, yours before the merge: compare, then remove it" "$v" "[S7] verify says a .old left"

# On a terminal: N keeps it, as off one.
fresh
echo "# mine" >> "$conf"
rc=0; out=$("$py" "$ROOT/tests/lib/answer.py" 'Apply both? [y/N] ' n -- "$v2/xymon-plugin" update --server xymonapi XYMONHOME="$home" 2>&1) || rc=$?
assert_not_contains "# v2's first line" "$(cat "$conf")" "[S7] N merges nothing"
assert_contains "# v2's first line" "$(cat "$conf.new")" "[S7] and writes this version's beside it"

# The same line edited: a conflict, kept, NAME.new beside it.
fresh
{ echo "# my first line"; cat "$conf"; } > "$work/c" && cat "$work/c" > "$conf"
up
assert_contains "xymonapi-apache.conf is kept as yours; this version's changes the same lines" "$out" "[S7] a conflict keeps yours, said"
assert_contains "# my first line" "$(cat "$conf")" "[S7] unchanged"
assert_contains "# v2's first line" "$(cat "$conf.new")" "[S7] this version's beside it"

# Yours has v2's change already, and one of your own: nothing asked,
# nothing beside it; v2's is then the version it starts from.
fresh
{ echo "# v2's first line"; cat "$conf"; echo "# mine"; } > "$work/c" && cat "$work/c" > "$conf"
up
assert_not_contains "xymonapi-apache.conf is kept" "$out" "[S7] yours with this version's change already: nothing said"
[ ! -e "$conf.new" ] || fail "[S7] a NAME.new beside a file that has this version's change already"
cmp -s "$work/c" "$conf" || fail "[S7] a file with this version's change already was changed"
cmp -s "$ext/.shipped/xymonapi-apache.conf" "$work/c" && fail "[S7] .shipped/ took yours, not this version's"
grep -q "# v2's first line" "$ext/.shipped/xymonapi-apache.conf" || fail "[S7] this version's is not the one it now starts from"

# Unedited: v2's taken, the task file too.
fresh
up
assert_contains "# v2's first line" "$(cat "$conf")" "[S7] an unedited snippet takes this version's"
assert_contains "# v2's last line" "$(cat "$ext/tasks.cfg")" "[S7] an unedited task file too"
[ ! -e "$conf.new" ] && [ ! -e "$ext/tasks.cfg.new" ] || fail "[S7] a NAME.new beside an unedited file"

# A version that changes nothing: an edited file left alone, nothing beside it.
fresh
echo "# mine" >> "$conf"
"$ROOT/xymon-plugin" update --server xymonapi XYMONHOME="$home" </dev/null >"$work/x.log" 2>&1 || fail "update v1: $(tail -n 3 "$work/x.log")"
assert_contains "# mine" "$(cat "$conf")" "[S7] an edited file stays when this version changes it not"
[ ! -e "$conf.new" ] || fail "[S7] a NAME.new when this version changes nothing"
rc=0; v=$("$ROOT/xymon-plugin" verify --server XYMONHOME="$home" </dev/null 2>&1) || rc=$?
assert_equal 0 "$rc" "[S7] and verify is content: $v"

pass "an update meets the administrator's edited files with this version's: merged on y on a terminal, the file before as .old; otherwise kept, this version's beside it as .new; a conflict kept; unedited replaced; verify says a .new or .old left"
