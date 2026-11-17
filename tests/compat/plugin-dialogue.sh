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
assert_contains "1) install xymonapi on the server: the HTTP API" "$menu" "[S27] the plugins others need come first, each said in a few words"
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
[ -L "$s/etc/tasks.d/xymonapi.cfg" ] && fail "[S27] Enter at the enabling offer turned it on"

# Now installed: turning it on is offered, installing it no more.
dialogue 'Use it? [Y/n] ' '' 'What do you want to do? [0] ' ''
assert_contains "turn xymonapi on" "$out" "[S27] only what applies is offered: turning it on"
assert_not_contains "install xymonapi on the server" "$out" "[S27] not installing it again"
assert_contains "xymonapi $(sed -n 's/^version: //p' "$ROOT/plugins/xymonapi/PLUGIN")" "$out" "[S27] and the plugin installed is listed with its version"

# Off a terminal, no verb: the usage, nothing done (S17).
rc=0; "$ROOT/xymon-plugin" </dev/null >"$work/usage.log" 2>&1 || rc=$?
assert_equal "2" "$rc" "[S27] off a terminal, no verb is the usage"

pass "with no verb on a terminal, the dialogue says where things stand, offers what applies with nothing the default, prints and runs the command chosen, offers enabling after an install with Enter declining it, and stops"
