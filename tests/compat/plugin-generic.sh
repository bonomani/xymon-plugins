#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-generic.sh
#
# A plugin no code knows -- a directory and its PLUGIN file, alone in a copy
# of the checkout -- is found by --all, installed, reported and removed as
# any other: the command reads each plugin from its PLUGIN file, with no
# list and no branch for a name.
#
# Run from a copy of the checkout, in a scratch directory.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
repo=$work/repo
mkdir -p "$repo/plugins/zz-demo"
cp -R "$ROOT/xymon-plugin" "$ROOT/LICENSE" "$repo/"
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
pass "a plugin no code knows is found by --all, installed, reported and removed"
