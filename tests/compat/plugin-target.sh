#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-target.sh
#
# The installation a run acts on (S25). Named by XYMONHOME or
# --xymon-home, which wins, said on the first line. Not named, on a
# terminal: the one server found is proposed, Enter for yes, n for no;
# several are listed, the one used last the default, said when it is gone,
# and the one chosen remembered. Off a terminal, not named, a verb that
# changes something is refused, the trees found listed; status lists every
# one, asking nothing. A XYMONHOME naming a server's own client tree is
# refused, naming that server. The current directory chooses nothing.
#
# Scratch trees, which XYMON_PLUGINS_TREES points detection at; answer.py
# plays the person at the terminal.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
py=${XYMONAPI_PYTHON:-python3}
export XDG_CONFIG_HOME="$work/cfg" XYMON_PLUGINS_TREES_ONLY=1
man=$work/man
a=$work/a/server; b=$work/b/server
server_tree "$a"; server_tree "$b"

# term PROMPT ANSWER ARG... -- xymon-plugin ARG... on a terminal, ANSWER
# typed at PROMPT; its output in out, its status in rc.
term() {
	p=$1 ans=$2; shift 2
	rc=0; out=$("$py" "$ROOT/tests/lib/answer.py" "$p" "$ans" "$ROOT/xymon-plugin" "$@" MANDIR="$man" 2>&1) || rc=$?
}

# One server found: proposed, n declines, Enter takes it, and the first
# line says what chose it.
export XYMON_PLUGINS_TREES="$a"
term 'Use it? [Y/n] ' n install --server xymonapi
[ "$rc" -ne 0 ] || fail "[S25] n at the proposal did not stop the run"
[ -e "$a/ext/xymonapi" ] && fail "[S25] n at the proposal installed anyway"
term 'Use it? [Y/n] ' '' install --server xymonapi
[ "$rc" -eq 0 ] || fail "[S25] Enter at the proposal failed: $out"
assert_contains "Xymon server: $a (detected)" "$out" "[S25] the one server found is proposed"
assert_contains "Target: $a (detected, confirmed), part: server" "$out" "[S25] and the first line says what chose it"
assert_file_exists "$a/ext/xymonapi/VERSION"

# Several: listed, the one used last -- a, taken above -- the default; the
# one chosen is remembered and the default next time; gone, it is said, and
# there is no default.
export XYMON_PLUGINS_TREES="$a:$b"
term 'Which one? [1] ' 2 install --server xymonapi-rag
[ "$rc" -eq 0 ] || fail "[S25] choosing 2 of several failed: $out"
assert_contains "1) $a" "$out" "[S25] several are listed"
assert_file_exists "$b/ext/xymonapi-rag/VERSION"
assert_equal "$b" "$(cat "$work/cfg/xymon-plugin/installation-used-last-server")" "[S25] the one chosen is remembered as the server used last"
term 'Which one? [2] ' '' update --server xymonapi-rag
[ "$rc" -eq 0 ] || fail "[S25] Enter on the one used last failed: $out"
assert_contains "Target: $b (detected, confirmed)" "$out" "[S25] the one used last is the default"
mv "$b" "$work/b/moved"
term 'Use it? [Y/n] ' n install --server xymonapi-mcp
assert_not_contains "is gone" "$out" "[S25] one server left is proposed, not listed"
server_tree "$work/c/server"
export XYMON_PLUGINS_TREES="$a:$work/c/server"
term 'Which one? [1-2] ' 1 install --server xymonapi-mcp
assert_contains "The one used last, $b, is gone." "$out" "[S25] the one used last, gone, is said, and there is no default"

# Off a terminal: refused, the trees listed; status lists every one.
rc=0; out=$("$ROOT/xymon-plugin" install --server xymonapi-agent MANDIR="$man" </dev/null 2>&1) || rc=$?
[ "$rc" -ne 0 ] || fail "[S25] off a terminal, a change with no installation named succeeded"
assert_contains "$a, a Xymon server" "$out" "[S25] and the refusal lists the trees found"
out=$("$ROOT/xymon-plugin" status </dev/null 2>&1) || fail "[S25] status with none named failed: $out"
assert_contains "Xymon server $a:" "$out" "[S25] status lists every installation found"
assert_contains "Xymon server $work/c/server:" "$out" "[S25] each of them"
assert_contains "xymonapi: " "$out" "[S25] with what each holds"

# Named: --xymon-home wins over XYMONHOME, and says so.
out=$(XYMONHOME="$work/c/server" "$ROOT/xymon-plugin" update --server xymonapi --xymon-home "$a" MANDIR="$man" </dev/null 2>&1) \
	|| fail "[S25] update with --xymon-home failed: $out"
assert_contains "Target: $a (named by --xymon-home, over XYMONHOME=$work/c/server)" "$out" "[S25] --xymon-home wins over XYMONHOME, said"

# A server's own client tree named: refused, naming the server.
s=$work/own/server; c=$work/own/client
server_tree "$s"; mkdir -p "$c/bin" "$c/etc"; : > "$c/bin/xymonclient.sh"; : > "$c/etc/xymonclient.cfg"
echo "XYMONCLIENTHOME=\"$c\"" >> "$s/etc/xymonserver.cfg"
rc=0; out=$(XYMONHOME="$c" "$ROOT/xymon-plugin" install --server xymonapi MANDIR="$man" </dev/null 2>&1) || rc=$?
[ "$rc" -ne 0 ] || fail "[S25] a server's own client tree named was taken"
assert_contains "is the client tree of the Xymon server $s:" "$out" "[S25] and the refusal names that server"

# The current directory chooses nothing: from inside a tree, the same.
rc=0; out=$(cd "$a" && "$ROOT/xymon-plugin" install --server xymonapi-agent MANDIR="$man" </dev/null 2>&1) || rc=$?
[ "$rc" -ne 0 ] || fail "[S25] from inside a tree, a change with no installation named succeeded"

pass "the installation is named, --xymon-home over XYMONHOME, or detected and confirmed on a terminal, the one used last the default; off a terminal a change is refused and status lists every one; a server's own client tree is refused, naming the server"
