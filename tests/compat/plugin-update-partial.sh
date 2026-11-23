#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-update-partial.sh
#
# A release's archive holds its own plugin alone: unpacked by itself, its
# checkout has xymon-plugin and nothing else. `update` with none named, run
# from it on a server or a person's tools where other plugins are installed,
# met the first of those the checkout lacks halfway -- "xymonapi has nothing
# to install on the server", exit 1, after xymon-plugin was already replaced
# and before its MANIFEST was written. Each plugin the checkout lacks is now
# passed over, said, before anything changes; the others are updated (S20).

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
export HOME="$work/home" XDG_CONFIG_HOME="$work/cfg"
mkdir -p "$HOME"

# The archive's checkout: the installer's plugin alone, as
# build/release-archive.sh lays it out.
a=$work/arch/xymon-plugins
mkdir -p "$a/plugins"
cp -R "$ROOT/plugins/xymon-plugin" "$a/plugins/"
cp "$ROOT/LICENSE" "$a/"
ln -s plugins/xymon-plugin/xymon-plugin "$a/xymon-plugin"

# snapshot DIR -- every path under DIR with its cksum, for "left as it is".
snapshot() { (cd "$1" && find . -type f -exec cksum {} + | sort); }

# The server: xymon-plugin and xymonapi installed from the whole checkout.
s=$work/server
server_tree "$s"
"$ROOT/xymon-plugin" install --server xymon-plugin xymonapi XYMONHOME="$s" MANDIR="$work/man" </dev/null >"$work/i.log" 2>&1 \
	|| fail "the install from the whole checkout failed: $(tail -n 5 "$work/i.log")"
before=$(snapshot "$s/ext/xymonapi")
rm -f "$s/ext/xymon-plugin/MANIFEST"
rc=0; out=$("$a/xymon-plugin" update --server XYMONHOME="$s" MANDIR="$work/man" </dev/null 2>&1) || rc=$?
[ "$rc" -eq 0 ] || fail "[S20] update --server from an archive holding xymon-plugin alone failed ($rc): $out"
assert_contains "xymonapi is not in this checkout: left as it is" "$out" "[S20] a plugin the checkout lacks is passed over, said"
assert_contains "Updated xymon-plugin" "$out" "[S20] the plugin the checkout has is updated"
assert_file_exists "$s/ext/xymon-plugin/MANIFEST"
assert_equal "$before" "$(snapshot "$s/ext/xymonapi")" "[S20] the plugin passed over is left as it is"

# None of those installed in the checkout: said, nothing changed.
mv "$s/ext/xymon-plugin" "$work/xp.kept"
rc=0; out=$("$a/xymon-plugin" update --server XYMONHOME="$s" MANDIR="$work/man" </dev/null 2>&1) || rc=$?
[ "$rc" -ne 0 ] || fail "[S20] update with no plugin of the checkout installed was taken: $out"
assert_contains "is in this checkout: nothing to update" "$out" "[S20] and says why"
mv "$work/xp.kept" "$s/ext/xymon-plugin"

# The tools part alike.
p=$work/prefix
"$ROOT/xymon-plugin" install --tools xymonapi-agent PREFIX="$p" </dev/null >"$work/t.log" 2>&1 \
	|| fail "the tools install from the whole checkout failed: $(tail -n 5 "$work/t.log")"
tbefore=$(snapshot "$p/libexec/xymon-plugins/xymonapi-agent")
rc=0; out=$("$a/xymon-plugin" update --tools PREFIX="$p" </dev/null 2>&1) || rc=$?
assert_contains "xymonapi-agent is not in this checkout: left as it is" "$out" "[S20] a tools plugin the checkout lacks is passed over, said"
assert_equal "$tbefore" "$(snapshot "$p/libexec/xymon-plugins/xymonapi-agent")" "[S20] and left as it is"

pass "update with none named, from a checkout holding some plugins alone, passes over the others, said, before anything changes"
