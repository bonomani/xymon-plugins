#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# plugins/xymon-plugin/tests/xymon-plugin.sh
#
# The installer is a plugin of its own: install --server xymon-plugin puts
# it in ext/xymon-plugin/ with its PLUGIN, VERSION and MANIFEST, its manual
# page linked, no task turned on; verify finds it as installed; the copy
# installed gives its version; status and outdated report it as any
# plugin; remove takes it away. The installer /plugins serves knows its
# version too, where only another plugin is installed, and installs from
# that stage. The network is never reached: gh is a stand-in first on PATH.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../../../tests/lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
home=$work/server
server_tree "$home"
want=$(sed -n 's/^version: *//p' "$ROOT/plugins/xymon-plugin/PLUGIN")
assert_equal "xymon-plugin $want" "$("$ROOT/xymon-plugin" --version)" "[S2] --version is its PLUGIN file's version"

"$ROOT/xymon-plugin" install --server xymon-plugin XYMONHOME="$home" MANDIR="$work/man" >"$work/install.log" 2>&1 \
	|| fail "install --server xymon-plugin failed: $(tail -n 5 "$work/install.log")"
ext=$home/ext/xymon-plugin
[ -x "$ext/xymon-plugin" ] || fail "the installer installed is not executable"
assert_equal "$want" "$(cat "$ext/VERSION")" "[S2] its VERSION is its PLUGIN file's"
assert_file_exists "$ext/PLUGIN"
sum=$(cksum < "$ext/xymon-plugin" | awk '{ print $1, $2 }')
assert_contains "file	$sum	xymon-plugin" "$(cat "$ext/MANIFEST")" "[S29] its MANIFEST records it, its cksum and size"
assert_equal "$ext/xymon-plugin.8" "$(readlink "$work/man/man8/xymon-plugin.8")" "[S20] its manual page is linked in MANDIR"
"$ROOT/xymon-plugin" verify --server xymon-plugin XYMONHOME="$home" >"$work/verify.log" 2>&1 \
	|| fail "[S30] verify finds it otherwise than installed: $(cat "$work/verify.log")"
assert_contains "ok: xymon-plugin" "$(cat "$work/verify.log")" "[S30] verify finds it as installed"
if [ -e "$home/etc/tasks.d/xymon-plugin.cfg" ] || [ -L "$home/etc/tasks.d/xymon-plugin.cfg" ]; then
	fail "[S5] installing it turned a task on"
fi
assert_equal "xymon-plugin $want" "$("$ext/xymon-plugin" --version)" "the copy installed gives the same version"
assert_contains "xymon-plugin: $want installed; not in this copy" "$("$ext/xymon-plugin" status --server XYMONHOME="$home" 2>&1)" \
	"the copy installed holds no plugin, and does not take itself for a checkout"
assert_contains "xymon-plugin: $want installed" "$("$ROOT/xymon-plugin" status --server XYMONHOME="$home" 2>&1)" "[S15] status reports it"

# outdated compares it with its releases, as any plugin's.
bin=$work/bin; mkdir -p "$bin"
printf '#!/bin/sh\ncat "%s/tags"\n' "$work" > "$bin/gh"
chmod 755 "$bin/gh"
printf 'xymon-plugin/v99.0.0\nxymonapi/v1.0.0\n' > "$work/tags"
rc=0
PATH="$bin:$PATH" "$ROOT/xymon-plugin" outdated --server XYMONHOME="$home" >"$work/out" 2>&1 || rc=$?
assert_equal "6" "$rc" "[S32] outdated ends with 6 when a newer installer is released"
assert_contains "xymon-plugin: $want installed; 99.0.0 released" "$(cat "$work/out")" "[S32] and names it"

"$ROOT/xymon-plugin" remove --server xymon-plugin --yes XYMONHOME="$home" MANDIR="$work/man" >"$work/remove.log" 2>&1 \
	|| fail "remove --server xymon-plugin failed: $(tail -n 5 "$work/remove.log")"
[ -e "$ext" ] && fail "ext/xymon-plugin is still there after remove"
if [ -e "$work/man/man8/xymon-plugin.8" ] || [ -L "$work/man/man8/xymon-plugin.8" ]; then
	fail "[S20] its manual page's link is still there after remove"
fi
# Only xymonapi installed elsewhere: the installer /plugins serves, staged
# beside it, still knows its version.
home2=$work/server2
server_tree "$home2"
"$ROOT/xymon-plugin" install --server xymonapi XYMONHOME="$home2" MANDIR="$work/man2" >"$work/install2.log" 2>&1 \
	|| fail "install --server xymonapi failed: $(tail -n 5 "$work/install2.log")"
[ -e "$home2/ext/xymon-plugin" ] && fail "installing xymonapi installed the installer too"
assert_equal "xymon-plugin $want" "$("$home2/ext/xymon-plugins-dist/xymon-plugin" --version 2>&1)" \
	"[S19] the installer /plugins serves gives its version, staged as a plugin or not"
assert_not_contains "xymon-plugins-dist" "$("$ROOT/xymon-plugin" status --server XYMONHOME="$home2" 2>&1)" \
	"[S19] and the stage is not taken for a plugin installed"
# That stage fetched elsewhere, its installer installs and stages from
# it: the script and its PLUGIN file taken from beside it.
cp -R "$home2/ext/xymon-plugins-dist" "$work/fetched"
home4=$work/server4
server_tree "$home4"
"$work/fetched/xymon-plugin" install --server xymonapi XYMONHOME="$home4" MANDIR="$work/man4" >"$work/install4.log" 2>&1 \
	|| fail "[S19] the installer /plugins serves could not install from its stage: $(tail -n 5 "$work/install4.log")"
assert_file_exists "$home4/ext/xymonapi/MANIFEST"
assert_equal "xymon-plugin $want" "$("$home4/ext/xymon-plugins-dist/xymon-plugin" --version 2>&1)" \
	"[S19] and the stage it makes serves an installer that knows its version"
# A stage left without the installer's PLUGIN file: the install goes on,
# and says the installer it stages will not know its version.
cp -R "$home2/ext/xymon-plugins-dist" "$work/fetched2"
rm "$work/fetched2/xymon-plugin.PLUGIN"
home5=$work/server5
server_tree "$home5"
"$work/fetched2/xymon-plugin" install --server xymonapi XYMONHOME="$home5" MANDIR="$work/man5" >"$work/install5.log" 2>&1 \
	|| fail "an install from a stage without xymon-plugin.PLUGIN failed: $(tail -n 5 "$work/install5.log")"
assert_contains "the installer /plugins serves will not know its version" "$(cat "$work/install5.log")" \
	"[S19] a stage without the installer's PLUGIN file is said"

pass "the installer installs itself as a plugin, gives its version installed, is reported by status and outdated, and is removed"
