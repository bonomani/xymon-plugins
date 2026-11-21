#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/release-archive.sh
#
# build/release-archive.sh makes one release's archive from its tag,
# NAME/vX.Y.Z:
#
# - a plugin's holds its directory and LICENSE, the installer's xymon-plugin
#   and LICENSE, all under xymon-plugins/, and nothing else;
# - the same tag gives the same bytes;
# - a tag whose version is not the plugin's, or the installer's, at that
#   commit, or that names no plugin, is refused;
# - the installer and the plugins wanted, unpacked side by side, install as
#   a checkout does.
#
# Runs on a scratch clone of this repository, with the working tree's
# installer and script committed and tagged there. Needs git, tar and gzip.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
command -v git >/dev/null 2>&1 || skip "git is not installed"
work=$(mktempdir)

# This repository's files as they are now, committed in a scratch one.
repo=$work/repo
mkdir -p "$repo"
cp -R "$ROOT/xymon-plugin" "$ROOT/LICENSE" "$ROOT/plugins" "$ROOT/build" "$repo/"
g() { git -C "$repo" -c user.name=t -c user.email=t@example.com "$@"; }
g init -q -b main
g add -A
g commit -q -m release
api=$(sed -n 's/^version: *//p' "$repo/plugins/xymonapi/PLUGIN")
mcp=$(sed -n 's/^version: *//p' "$repo/plugins/xymonapi-mcp/PLUGIN")
inst=$(sed -n 's/^version: *//p' "$repo/plugins/xymon-plugin/PLUGIN")
g tag "xymonapi/v$api"
g tag "xymonapi-mcp/v$mcp"
g tag "xymon-plugin/v$inst"
g tag "xymonapi/v9.9.9"
g tag "nosuch/v1.0.0"
build() { (cd "$repo" && build/release-archive.sh "$@"); }

a=$(build "xymonapi/v$api" "$work/out")
assert_equal "$work/out/xymonapi-$api.tar.gz" "$a" "a plugin's archive is NAME-X.Y.Z.tar.gz"
list=$(tar tzf "$a")
assert_contains "xymon-plugins/plugins/xymonapi/PLUGIN" "$list" "it holds the plugin's directory"
assert_contains "xymon-plugins/LICENSE" "$list" "and LICENSE"
assert_not_contains "xymonapi-mcp" "$list" "and no other plugin"
assert_not_contains "xymon-plugins/xymon-plugin" "$list" "nor the installer"
assert_equal "" "$(printf '%s\n' "$list" | grep -v '^xymon-plugins/' || true)" "everything under xymon-plugins/"

# The installer is a plugin too, plugins/xymon-plugin: its archive holds
# that directory, LICENSE, and ./xymon-plugin, the link at the top that
# leads into it -- and nothing else (S2: its version is its PLUGIN file's).
i=$(build "xymon-plugin/v$inst" "$work/out")
ilist=$(tar tzf "$i")
assert_contains "xymon-plugins/plugins/xymon-plugin/PLUGIN" "$ilist" "[S2] the installer's archive holds its plugin directory"
assert_contains "xymon-plugins/plugins/xymon-plugin/xymon-plugin" "$ilist" "with the installer in it"
assert_equal "" "$(printf '%s\n' "$ilist" | grep -vE '^xymon-plugins/($|LICENSE$|xymon-plugin$|plugins/$|plugins/xymon-plugin/)' || true)" \
	"and only that directory, LICENSE and ./xymon-plugin"
ilong=$(tar tvzf "$i")
grep -q '^l.* xymon-plugins/xymon-plugin -> plugins/xymon-plugin/xymon-plugin$' <<<"$ilong" \
	|| fail "./xymon-plugin in the installer's archive is not the link into plugins/xymon-plugin: $ilong"

first=$(cksum < "$a")
sleep 1
rm "$a"
build "xymonapi/v$api" "$work/out" >/dev/null
assert_equal "$first" "$(cksum < "$a")" "the same tag gives the same bytes"

rc=0; out=$(build "xymonapi/v9.9.9" "$work/out" 2>&1) || rc=$?
assert_equal "1" "$rc" "a tag whose version is not the plugin's is refused"
assert_contains "is version $api at that commit, not 9.9.9" "$out" "saying both"
rc=0; out=$(build "nosuch/v1.0.0" "$work/out" 2>&1) || rc=$?
assert_equal "1" "$rc" "a tag that names no plugin is refused"
rc=0; out=$(build "xymonapi/v1.0" "$work/out" 2>&1) || rc=$?
assert_equal "1" "$rc" "a version that is not X.Y.Z is refused"

# Unpacked side by side, they install as a checkout does.
m=$(build "xymonapi-mcp/v$mcp" "$work/out")
mkdir -p "$work/unpacked"
for f in "$i" "$a" "$m"; do tar xzf "$f" -C "$work/unpacked"; done
assert_equal "xymon-plugin $inst" "$("$work/unpacked/xymon-plugins/xymon-plugin" --version)" "the installer says its version"
PREFIX="$work/prefix" XDG_CONFIG_HOME="$work/cfg" HOME="$work" \
	"$work/unpacked/xymon-plugins/xymon-plugin" install --tools xymonapi-mcp </dev/null >"$work/install.log" 2>&1 \
	|| fail "install --tools from the unpacked archives failed: $(tail -n 5 "$work/install.log")"
assert_file_exists "$work/prefix/libexec/xymon-plugins/xymonapi-mcp/VERSION"
assert_file_exists "$work/prefix/libexec/xymon-plugins/xymonapi/xymonapi_client.py"
assert_equal "$mcp" "$(cat "$work/prefix/libexec/xymon-plugins/xymonapi-mcp/VERSION")" "the plugin installed records its version"
# And from the scratch checkout itself, at the release tags: the same X.Y.Z,
# not the tag (S2).
PREFIX="$work/prefix2" XDG_CONFIG_HOME="$work/cfg2" HOME="$work" \
	"$repo/xymon-plugin" install --tools xymonapi-mcp </dev/null >"$work/install2.log" 2>&1 \
	|| fail "install --tools from the tagged checkout failed: $(tail -n 5 "$work/install2.log")"
assert_equal "$mcp" "$(cat "$work/prefix2/libexec/xymon-plugins/xymonapi-mcp/VERSION")" \
	"[S2] from a checkout at a release tag, VERSION is the same X.Y.Z as from its archive"

pass "a release's archive holds one plugin, the installer's with its link at the top, under xymon-plugins/, the same bytes for the same tag, refused when its version is not the tag's, and installs unpacked beside the others"
