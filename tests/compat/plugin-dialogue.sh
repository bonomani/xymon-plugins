#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-dialogue.sh
#
# With no verb, on a terminal (S27): where things stand, then what applies,
# nothing the default; the command chosen printed, confirmed, and run, and
# nothing else; after an install, enabling offered as a second command,
# which Enter declines; then it stops. Off a terminal, S17's usage.
#
# A scratch server tree, which XYMON_PLUGINS_TREES points detection at;
# answer.py plays the person.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
py=${XYMONAPI_PYTHON:-python3}
export XDG_CONFIG_HOME="$work/cfg" XYMON_PLUGINS_TREES_ONLY=1 MANDIR="$work/man" PREFIX="$work/prefix"
s=$work/server; server_tree "$s"
export XYMON_PLUGINS_TREES="$s"

# dialogue PAIR... -- xymon-plugin with no verb on a terminal, PROMPT ANSWER
# pairs answered in order; its output in out, its status in rc.
dialogue() { rc=0; out=$("$py" "$ROOT/tests/lib/answer.py" "$@" -- "$ROOT/xymon-plugin" 2>&1) || rc=$?; }

# Enter at the menu: nothing done, nothing changed.
dialogue 'Use it? [Y/n] ' '' 'What do you want to do? [0] ' ''
[ "$rc" -eq 0 ] || fail "[S27] Enter at the menu failed: $out"
assert_contains "Xymon server: $s" "$out" "[S27] the dialogue says where things stand"
assert_contains "0) nothing" "$out" "[S27] nothing is offered, the default"
assert_contains "Nothing done." "$out" "[S27] and Enter does nothing"
[ -e "$s/ext/xymonapi" ] && fail "[S27] Enter at the menu installed something"
menu=$out
assert_match "[0-9]+\) install xymonapi on the server: the HTTP API" "$menu" "[S27] each plugin offered, said in a few words"
# Each plugin offered comes after every plugin it needs on the server.
pos() { printf '%s\n' "$menu" | sed -n "s/^  \\([0-9]*\\)) install $1 on the server.*/\\1/p"; }
for f in "$ROOT"/plugins/*/PLUGIN; do
	n=$(sed -n 's/^name: *//p' "$f"); k=$(pos "$n"); [ -n "$k" ] || continue
	for d in $(sed -n 's/^server-needs: *//p' "$f"); do
		dk=$(pos "${d%%:*}")
		[ -n "$dk" ] && [ "$dk" -lt "$k" ] || fail "[S27] the plugins others need come first: $n is $k, ${d%%:*}, which it needs, ${dk:-not offered}"
	done
done
assert_contains "Its client" "$menu" "[S27] the server's client has its section"
assert_contains "Your tools, $work/prefix:" "$menu" "[S27] and so have the person's tools"

# n at the proposal: no Xymon part, and the dialogue goes on with the
# person's tools.
dialogue 'Use it? [Y/n] ' n 'What do you want to do? [0] ' ''
[ "$rc" -eq 0 ] || fail "[S27] n at the proposal failed: $out"
assert_contains "No Xymon server chosen" "$out" "[S27] n at the proposal is said"
assert_contains "install xymonapi-mcp for you" "$out" "[S27] and the person's tools are still offered"
assert_not_contains "install xymonapi on the server" "$out" "[S27] and nothing of the server"

# The install of xymonapi chosen: the command printed and run, enabling
# then offered as a second command, which Enter declines.
k=$(printf '%s\n' "$menu" | sed -n 's/^  \([0-9]*\)) install xymonapi on the server.*/\1/p')
[ -n "$k" ] || fail "[S27] installing xymonapi is not offered: $menu"
dialogue 'Use it? [Y/n] ' '' 'What do you want to do? [0] ' "$k" 'Proceed? [Y/n] ' ''
[ "$rc" -eq 0 ] || fail "[S27] the dialogue's install failed: $out"
assert_contains "I will run:  $ROOT/xymon-plugin install --server --xymon-home $s xymonapi" "$out" "[S27] the command chosen is printed, the installation by --xymon-home"
assert_file_exists "$s/ext/xymonapi/VERSION"
assert_contains "Turn it on now?" "$out" "[S27] after the install, enabling is offered"
assert_contains "xymonapi stays off" "$out" "[S27] and Enter declines it"
[ -L "$s/etc/tasks.d/xymonapi-server.cfg" ] && fail "[S27] Enter at the enabling offer turned it on"

# Now installed: turning it on is offered, installing it no more.
dialogue 'Use it? [Y/n] ' '' 'What do you want to do? [0] ' ''
assert_contains "turn xymonapi on" "$out" "[S27] only what applies is offered: turning it on"
assert_not_contains "install xymonapi on the server" "$out" "[S27] not installing it again"
assert_contains "xymonapi $(sed -n 's/^version: //p' "$ROOT/plugins/xymonapi/PLUGIN")" "$out" "[S27] and the plugin installed is listed with its version"

# What verify finds, said beside each plugin, and what is left by a
# plugin gone; the menu offers the update that repairs it and the clean
# that takes the rest away.
v=install; [ -d "$s/ext/xymonapi" ] && v=update
"$ROOT/xymon-plugin" "$v" --server xymonapi XYMONHOME="$s" </dev/null >"$work/i.log" 2>&1 || fail "$v failed: $(tail -n 3 "$work/i.log")"
mkdir -p "$s/ext/xymon-plugins-dist/plugins/gone"
echo "# changed" >> "$s/ext/xymonapi/app.py"
dialogue 'Use it? [Y/n] ' '' 'What do you want to do? [0] ' ''
assert_contains "xymonapi $(sed -n 's/^version: //p' "$ROOT/plugins/xymonapi/PLUGIN")" "$out" "[S27] the plugin is listed"
assert_contains "-- broken: app.py changed" "$out" "[S27] with what verify finds broken in it"
assert_contains "left by gone, gone: the staged copy" "$out" "[S27] what a plugin gone left is said"
assert_contains "update the server's plugins, which repairs xymonapi" "$out" "[S27] the update that repairs it is offered"
assert_contains "take away what gone left on the server" "$out" "[S27] and the clean that takes the rest away"
# Chosen, it is confirmed once: the dialogue showed what is left, and its
# command is clean --yes.
c=$(printf '%s\n' "$out" | tr -d '\r' | sed -n 's/^ *\([0-9]*\)) take away what gone left on the server$/\1/p')
[ -n "$c" ] || fail "[S27] no choice to take away what gone left"
dialogue 'Use it? [Y/n] ' '' 'What do you want to do? [0] ' "$c" 'Proceed? [Y/n] ' ''
assert_contains "clean --server --xymon-home $s --yes gone" "$out" "[S27] the clean chosen is clean --yes"
assert_not_contains "Proceed? [y/N]" "$out" "[S27] asked once, not again by clean"
[ ! -e "$s/ext/xymon-plugins-dist/plugins/gone" ] || fail "[S27] the clean chosen took nothing away: $out"
"$ROOT/xymon-plugin" remove --server xymonapi XYMONHOME="$s" </dev/null >/dev/null 2>&1 || fail "remove failed"
rm -rf "$s/ext/xymon-plugins-dist"

# Off a terminal, no verb: the usage, nothing done (S17).
rc=0; "$ROOT/xymon-plugin" </dev/null >"$work/usage.log" 2>&1 || rc=$?
assert_equal "2" "$rc" "[S27] off a terminal, no verb is the usage"

pass "with no verb on a terminal, the dialogue says where things stand, offers what applies with nothing the default, prints and runs the command chosen, offers enabling after an install with Enter declining it, and stops"
