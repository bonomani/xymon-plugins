#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-generic.sh
#
# A plugin no code knows -- a directory and its PLUGIN file, in a copy of
# the checkout beside only the installer, itself a plugin -- is found by
# --all, installed, reported and removed as any other: the command reads
# each plugin from its PLUGIN file, with no list and no branch for a name.
#
# Run from a copy of the checkout, in a scratch directory.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
repo=$work/repo
mkdir -p "$repo/plugins/zz-demo"
mkdir -p "$repo/plugins/xymon-plugin"
cp -R "$ROOT/xymon-plugin" "$ROOT/LICENSE" "$repo/"
cp -R "$ROOT/plugins/xymon-plugin/." "$repo/plugins/xymon-plugin/"
grep -qw zz-demo "$repo/xymon-plugin" && fail "[S1] the installer names zz-demo: pick another name for this test"
d=$repo/plugins/zz-demo
printf '%s\n' 'name: zz-demo' 'version: 1.2.3' 'summary: a plugin no code knows' \
	'server-short: a demonstration' 'server-files: demo.sh' 'server-manual: zz-demo.8' \
	'executable: demo.sh' > "$d/PLUGIN"
printf '#!/bin/sh\n' > "$d/demo.sh"
printf '.TH ZZ-DEMO 8\n' > "$d/zz-demo.8"
printf '# zz-demo\n' > "$d/README.md"

home=$work/server
man=$work/man
server_tree "$home"
"$repo/xymon-plugin" install --server --all XYMONHOME="$home" MANDIR="$man" >"$work/install.log" 2>&1 \
	|| fail "[S1] install --all failed: $(tail -n 5 "$work/install.log")"
assert_file_exists "$home/ext/zz-demo/demo.sh"
assert_file_exists "$man/man8/zz-demo.8"
assert_equal "1.2.3" "$(cat "$home/ext/zz-demo/VERSION")" "[S1] its version is read from its PLUGIN file"
st=$("$repo/xymon-plugin" status --server XYMONHOME="$home" 2>&1) || fail "[S1] status failed: $st"
assert_contains "zz-demo: 1.2.3 installed" "$st" "[S1] status reports it"
"$repo/xymon-plugin" remove --server --all --yes XYMONHOME="$home" MANDIR="$man" >"$work/remove.log" 2>&1 \
	|| fail "[S1] remove --all failed: $(tail -n 5 "$work/remove.log")"
for f in "$home/ext/zz-demo" "$man/man8/zz-demo.8"; do
	if [ -e "$f" ] || [ -L "$f" ]; then fail "[S1] $f is still there after remove --all"; fi
done
# An install that does not end -- here its manual page has nowhere to go,
# MANDIR being a file -- leaves the plugin's PLUGIN file and no VERSION:
# VERSION is written last, so that an unfinished install is told.
: > "$work/notadir"
rc=0
"$repo/xymon-plugin" install --server zz-demo XYMONHOME="$home" MANDIR="$work/notadir" >"$work/broken.log" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "an install whose manual page had nowhere to go succeeded"
assert_file_exists "$home/ext/zz-demo/PLUGIN"
[ -e "$home/ext/zz-demo/VERSION" ] && fail "an install that did not end wrote VERSION, which says it did"
rm -rf "$home/ext/zz-demo"

# An update that stops while staging for /plugins -- here a README.md it
# cannot read, which is staged and not installed -- leaves the copy
# staged before: what /plugins serves is never half gone. Not as root,
# who reads anything.
if [ "$(id -u)" -ne 0 ]; then
	"$repo/xymon-plugin" install --server zz-demo XYMONHOME="$home" MANDIR="$man" >"$work/again.log" 2>&1 \
		|| fail "installing zz-demo again failed: $(tail -n 5 "$work/again.log")"
	chmod a-r "$d/README.md"
	rc=0
	"$repo/xymon-plugin" update --server zz-demo XYMONHOME="$home" MANDIR="$man" >"$work/stage.log" 2>&1 || rc=$?
	chmod u+r,go+r "$d/README.md"
	[ "$rc" -ne 0 ] || fail "an update that could not stage README.md succeeded"
	assert_file_exists "$home/ext/xymon-plugins-dist/plugins/zz-demo/demo.sh"
	assert_file_exists "$home/ext/xymon-plugins-dist/plugins/zz-demo/README.md"
	"$repo/xymon-plugin" remove --server zz-demo --yes XYMONHOME="$home" MANDIR="$man" >/dev/null 2>&1 || :
fi

pass "a plugin no code knows is found by --all, installed, reported and removed"
