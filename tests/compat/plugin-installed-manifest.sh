#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-installed-manifest.sh
#
# An install keeps the plugin's PLUGIN file in its installed directory, and
# uninstall, enable, disable, an update and the check of what needs a
# plugin read that copy: a checkout of another version still removes what
# was installed, an update removes the command, manual page and task link
# the new version no longer has, and a plugin gone from the checkout is
# still uninstalled. An install from before the copy is managed by the
# checkout's PLUGIN file. A name in the copy that is not a plain file name
# is not acted on, nor a command that is not the one the install wrote.
#
# Run from copies of the checkout, in a scratch directory: v1 is the
# checkout as it is; v2 renames xymonapi-mcp's command and manual page,
# takes xymonapi-rag's task away and xymonapi-agent's need of xymonapi-mcp;
# v3 has no xymonapi-agent.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)

v1=$work/v1 v2=$work/v2 v3=$work/v3
for v in "$v1" "$v2" "$v3"; do
	mkdir -p "$v"
	cp -R "$ROOT/xymon-plugin" "$ROOT/LICENSE" "$ROOT/plugins" "$v/"
done
mcp=$v2/plugins/xymonapi-mcp
cp "$mcp/xymonapi-mcp.1" "$mcp/xymon-mcp.1"
sed -e 's|^command: xymonapi-mcp |command: xymon-mcp |' -e 's|^tools-manual: xymonapi-mcp.1|tools-manual: xymon-mcp.1|' \
	-e 's|^server-manual: xymonapi-mcp.1|server-manual: xymon-mcp.1|' "$v1/plugins/xymonapi-mcp/PLUGIN" > "$mcp/PLUGIN"
sed -e '/^task: /d' "$v1/plugins/xymonapi-rag/PLUGIN" > "$v2/plugins/xymonapi-rag/PLUGIN"
sed -e '/^server-needs: /d' "$v1/plugins/xymonapi-agent/PLUGIN" > "$v2/plugins/xymonapi-agent/PLUGIN"
rm -rf "$v3/plugins/xymonapi-agent"

# tools VERSION ACTION [PLUGIN...] -- that version's xymon-plugin, your own side.
prefix=$work/prefix
tools() { v=$1 a=$2; shift 2; [ "$a" = uninstall ] && a=remove; "$v/xymon-plugin" "$a" --tools "$@" PREFIX="$prefix" </dev/null >"$work/tools.log" 2>&1 \
	|| fail "$a-tools $* from ${v##*/} failed: $(tail -n 5 "$work/tools.log")"; }
lib=$prefix/libexec/xymon-plugins

tools "$v1" install xymonapi-mcp
assert_file_exists "$lib/xymonapi-mcp/PLUGIN"
cmp -s "$v1/plugins/xymonapi-mcp/PLUGIN" "$lib/xymonapi-mcp/PLUGIN" || fail "[S20] the installed PLUGIN file is not the one installed from"
assert_file_exists "$prefix/bin/xymonapi-mcp"
assert_file_exists "$prefix/share/man/man1/xymonapi-mcp.1"

# Uninstalled by a checkout of another version: what was installed goes.
tools "$v2" uninstall xymonapi-mcp
[ -e "$prefix/bin/xymonapi-mcp" ] && fail "[S20] uninstalling from another version left the installed command"
{ [ -e "$prefix/share/man/man1/xymonapi-mcp.1" ] || [ -L "$prefix/share/man/man1/xymonapi-mcp.1" ]; } && fail "[S20] uninstalling from another version left the installed manual page"
[ -e "$lib/xymonapi-mcp" ] && fail "[S20] uninstalling from another version left the plugin's directory"

# Updated to the other version: the old command and manual page go.
tools "$v1" install xymonapi-mcp
tools "$v2" update xymonapi-mcp
assert_file_exists "$prefix/bin/xymon-mcp"
assert_file_exists "$prefix/share/man/man1/xymon-mcp.1"
[ -e "$prefix/bin/xymonapi-mcp" ] && fail "[S20] an update left the command the old version installed"
{ [ -e "$prefix/share/man/man1/xymonapi-mcp.1" ] || [ -L "$prefix/share/man/man1/xymonapi-mcp.1" ]; } && fail "[S20] an update left the manual page the old version installed"

# A command in its place that the install did not write is not removed.
tools "$v1" update xymonapi-mcp
printf '#!/bin/sh\necho mine\n' > "$prefix/bin/xymon-mcp"
tools "$v2" uninstall xymonapi-mcp
tools "$v1" install xymonapi-mcp
printf '#!/bin/sh\necho mine\n' > "$prefix/bin/xymonapi-mcp"
tools "$v2" update xymonapi-mcp
assert_equal "mine" "$(sh "$prefix/bin/xymonapi-mcp")" "[S20] an update removed a command it did not write"
tools "$v2" uninstall xymonapi-mcp
rm -f "$prefix/bin/xymonapi-mcp"

# An install from before the copy: the checkout's PLUGIN file manages it.
tools "$v1" install xymonapi-mcp
rm "$lib/xymonapi-mcp/PLUGIN"
tools "$v1" uninstall xymonapi-mcp
[ -e "$prefix/bin/xymonapi-mcp" ] && fail "[S20] an install without the copy was not uninstalled by the checkout's PLUGIN file"

# The server side.
home=$work/server
server_tree "$home"
# enable refuses a plugin whose Python lacks its modules: a stand-in that
# has every one, as nothing here runs the plugin.
printf '#!/bin/sh\nexit 0\n' > "$work/haspy"; chmod 755 "$work/haspy"
export XYMONAPI_PYTHON="$work/haspy"
server() { v=$1 a=$2; shift 2; [ "$a" = uninstall ] && a=remove; "$v/xymon-plugin" "$a" --server "$@" XYMONHOME="$home" MANDIR="$work/man" </dev/null >"$work/server.log" 2>&1; }

server "$v1" install xymonapi-rag || fail "install-server xymonapi-rag failed: $(tail -n 5 "$work/server.log")"
assert_file_exists "$home/ext/xymonapi-rag/PLUGIN"
server "$v1" enable xymonapi-rag || fail "enable-server xymonapi-rag failed: $(tail -n 5 "$work/server.log")"
[ -L "$home/etc/tasks.d/xymonapi-rag.cfg" ] || fail "enable-server made no link"
server "$v2" update xymonapi-rag || fail "install-server xymonapi-rag from v2 failed: $(tail -n 5 "$work/server.log")"
[ -e "$home/etc/tasks.d/xymonapi-rag.cfg" ] || [ -L "$home/etc/tasks.d/xymonapi-rag.cfg" ] \
	&& fail "[S20] an update to a version with no task left the task link"
for f in "$home"/ext/.xymon-plugin.*; do [ ! -e "$f" ] || fail "[S20] an update to a version with no task left its task file aside: $f"; done
[ ! -e "$home/ext/xymonapi-rag/tasks.cfg.old" ] || fail "[S7] an update to a version with no task kept the unedited task file as .old"

# What needs a plugin is read from the copies: xymonapi-agent, installed
# from v1, needs xymonapi-mcp, though v2's xymonapi-agent no longer says so.
server "$v1" install xymonapi-agent || fail "install-server xymonapi-agent failed: $(tail -n 5 "$work/server.log")"
rc=0; server "$v2" uninstall xymonapi-mcp || rc=$?
[ "$rc" -ne 0 ] || fail "[S20] uninstalling a plugin an installed one needs, by its copy, succeeded"
assert_contains "needed by xymonapi-agent" "$(cat "$work/server.log")" "[S20] and names the one that needs it"

# A plugin gone from the checkout is uninstalled by its copy.
m=$work/man/man1/xymonapi-agent.1
assert_file_exists "$m"
server "$v3" uninstall xymonapi-agent || fail "[S20] uninstalling a plugin gone from the checkout failed: $(tail -n 5 "$work/server.log")"
[ -e "$home/ext/xymonapi-agent" ] && fail "[S20] uninstalling a plugin gone from the checkout left its directory"
{ [ -e "$m" ] || [ -L "$m" ]; } && fail "[S20] uninstalling a plugin gone from the checkout left its manual page"

# A name in the copy that leaves its directory is not acted on.
echo "keep" > "$work/victim.1"
sed -e 's|^server-manual: .*|server-manual: ../../victim.1|' "$home/ext/xymonapi-mcp/PLUGIN" > "$work/p" && cp "$work/p" "$home/ext/xymonapi-mcp/PLUGIN"
server "$v1" uninstall xymonapi-mcp || fail "uninstall-server xymonapi-mcp failed: $(tail -n 5 "$work/server.log")"
assert_equal "keep" "$(cat "$work/victim.1")" "[S20] a name in the copy that leaves its directory was removed"

# A manual page is a link into the plugin's directory, and a removal acts
# only on such a link: a record naming another package's page, a plain
# name, leaves it alone.
server "$v1" install xymonapi-mcp || fail "install-server xymonapi-mcp failed: $(tail -n 5 "$work/server.log")"
[ -L "$work/man/man1/xymonapi-mcp.1" ] || fail "[S20] the manual page is not a link"
assert_equal "$home/ext/xymonapi-mcp/xymonapi-mcp.1" "$(readlink "$work/man/man1/xymonapi-mcp.1")" "[S20] into the plugin's directory"
echo "theirs" > "$work/man/man1/other.1"
sed -e 's|^server-manual: .*|server-manual: other.1|' "$home/ext/xymonapi-mcp/PLUGIN" > "$work/p" && cp "$work/p" "$home/ext/xymonapi-mcp/PLUGIN"
server "$v1" uninstall xymonapi-mcp || fail "uninstall-server xymonapi-mcp failed: $(tail -n 5 "$work/server.log")"
assert_equal "theirs" "$(cat "$work/man/man1/other.1")" "[S20] a record naming another package's manual page removed it"

# A wrapper of the admin's own that runs the plugin is not the command the
# install wrote, and stays.
tools "$v1" install xymonapi-mcp
printf '#!/bin/sh\n# mine\nexec "%s/xymonapi-mcp/xymonapi-mcp.sh" --verbose "$@"\n' "$lib" > "$prefix/bin/xymonapi-mcp"
tools "$v1" uninstall xymonapi-mcp
assert_file_exists "$prefix/bin/xymonapi-mcp"
rm -f "$prefix/bin/xymonapi-mcp"

# A task file in the link's place -- an older install's copy, or the one an
# editor left -- goes with the plugin.
server "$v1" update xymonapi-rag || fail "install-server xymonapi-rag failed: $(tail -n 5 "$work/server.log")"
rm -f "$home/etc/tasks.d/xymonapi-rag.cfg"
mkdir -p "$home/etc/tasks.d"
cp "$home/ext/xymonapi-rag/tasks.cfg" "$home/etc/tasks.d/xymonapi-rag.cfg"
server "$v1" uninstall xymonapi-rag || fail "uninstall-server xymonapi-rag failed: $(tail -n 5 "$work/server.log")"
[ -e "$home/etc/tasks.d/xymonapi-rag.cfg" ] && fail "[S20] a task file in the link's place stayed after uninstall"

# Several plugins named go in the order the installed records say: v2's
# xymonapi-agent no longer needs xymonapi-mcp, the installed one does.
server "$v1" install xymonapi-agent || fail "install-server xymonapi-agent failed: $(tail -n 5 "$work/server.log")"
server "$v2" uninstall xymonapi-mcp xymonapi-agent \
	|| fail "[S20] uninstalling both, from a checkout whose needs: differ, failed: $(tail -n 5 "$work/server.log")"

# A plugin gone from the checkout is told of by status, and goes with an
# uninstall given no names.
server "$v1" install xymonapi-agent || fail "install-server xymonapi-agent failed: $(tail -n 5 "$work/server.log")"
out=$("$v3/xymon-plugin" status --server XYMONHOME="$home" 2>&1)
assert_contains "xymonapi-agent: " "$out" "[S20] status tells of a plugin gone from the checkout"
assert_contains "not in this copy" "$out" "[S20] and says it is gone from it"
server "$v3" uninstall --all || fail "[S20] uninstall with no names, a plugin gone from the checkout installed, failed: $(tail -n 5 "$work/server.log")"
[ -e "$home/ext/xymonapi-agent" ] && fail "[S20] uninstall with no names left a plugin gone from the checkout"

# status reads the installed copy: v1's xymonapi-rag, on, told of as on by
# v2, whose xymonapi-rag has no task.
server "$v1" install xymonapi-rag || fail "install-server xymonapi-rag failed: $(tail -n 5 "$work/server.log")"
server "$v1" enable xymonapi-rag || fail "enable-server xymonapi-rag failed: $(tail -n 5 "$work/server.log")"
assert_contains "xymonapi-rag: " "$("$v2/xymon-plugin" status --server xymonapi-rag XYMONHOME="$home" 2>&1)" "status from another version tells of the plugin"
assert_contains ", on;" "$("$v2/xymon-plugin" status --server xymonapi-rag XYMONHOME="$home" 2>&1)" "[S20] status reads the task from the installed copy"
server "$v1" uninstall xymonapi-rag || fail "uninstall-server xymonapi-rag failed: $(tail -n 5 "$work/server.log")"

# The command is compared byte for byte: one differing by its last
# newlines only is not the install's.
tools "$v1" install xymonapi-mcp
printf '%s\n\n' "$(cat "$prefix/bin/xymonapi-mcp")" > "$work/w" && cp "$work/w" "$prefix/bin/xymonapi-mcp"
tools "$v1" uninstall xymonapi-mcp
assert_file_exists "$prefix/bin/xymonapi-mcp"
rm -f "$prefix/bin/xymonapi-mcp"

# An install from before the copy, its manual page copied: uninstalled by
# the checkout's PLUGIN file, the page with it.
tools "$v1" install xymonapi-mcp
rm "$lib/xymonapi-mcp/PLUGIN" "$prefix/share/man/man1/xymonapi-mcp.1"
cp "$v1/plugins/xymonapi-mcp/xymonapi-mcp.1" "$prefix/share/man/man1/xymonapi-mcp.1"
tools "$v1" uninstall xymonapi-mcp
{ [ -e "$prefix/share/man/man1/xymonapi-mcp.1" ] || [ -L "$prefix/share/man/man1/xymonapi-mcp.1" ]; } \
	&& fail "[S20] an install from before the copy kept its copied manual page"

# Under DESTDIR, the manual page links to the directory as installed.
"$v1/xymon-plugin" install --server xymonapi-mcp XYMONHOME=/usr/lib/xymon/server DESTDIR="$work/stage" MANDIR=/usr/share/man \
	</dev/null >"$work/stage.log" 2>&1 || fail "install-server under DESTDIR failed: $(tail -n 5 "$work/stage.log")"
assert_equal "/usr/lib/xymon/server/ext/xymonapi-mcp/xymonapi-mcp.1" "$(readlink "$work/stage/usr/share/man/man1/xymonapi-mcp.1")" \
	"[S20] under DESTDIR the manual page links to the directory as installed"

# A name a shell would expand is no plugin name, on the command line or
# in a record's needs:.
rc=0; "$v1/xymon-plugin" remove --server 'xymonapi*' XYMONHOME="$home" </dev/null >"$work/glob.log" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "[S20] a plugin name with a * was taken"
assert_contains "not a plugin name" "$(cat "$work/glob.log")" "[S20] and refused as one"

pass "an installed plugin keeps its PLUGIN file and is managed by it: another version's checkout uninstalls it, an update removes what the old version put in place and the new does not, a plugin gone from the checkout is told of and uninstalled, needs and their order are read from the copies, task files in the link's place go, and a manual page not linked into the plugin, a name leaving its directory or a command not written are left alone"
