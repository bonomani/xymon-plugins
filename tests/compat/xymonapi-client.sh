#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/xymonapi-client.sh
#
# What make install stages on a server is what /client gives, and a machine
# installs from it: the archive holds each plugin installed there, laid out
# as the repository is but for the tests, with build/plugin.mk and the top
# Makefile; make install-client in its plugins/xymonapi-mcp installs the MCP
# server, xymonapi's client and xymonapi-connect, at the server's versions.
# A plugin uninstalled from the server leaves the archive, and xymonapi is
# not uninstalled while one staged there needs it.
#
# Skips where the API cannot run (tests/lib/xymonapi.sh). Needs the xymon
# client of the Xymon tree in XYMON_SRC (for a free port), curl and tar.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)

require_bin XYMONCLIENT "$XYMON_SRC/common/xymon"
command -v curl >/dev/null 2>&1 || skip "curl is not installed"

work=$(mktempdir)
register_cleanup 'stop_process "$API_PID"'
make=${MAKE:-make}

# Every server-side plugin, as an admin installs them.
"$make" -C "$ROOT" install XYMONHOME="$work/inst" MANDIR="$work/man" >"$work/install.log" 2>&1 \
	|| fail "make install failed: $(tail -n 5 "$work/install.log")"
[ -e "$work/inst/ext/xymonapi-mcp" ] && fail "make install put the MCP server in ext/, where nothing runs it"
API_ROOT=$work/inst/ext/xymonapi
export XYMON="$XYMONCLIENT" XYMSRV="127.0.0.1:1" XYMONAPI_PASSWD=""
start_api
client=http://127.0.0.1:$API_PORT/xymon/api/v1/client

curl -s -o "$work/client.tgz" "$client"
tar -tzf "$work/client.tgz" > "$work/list" || fail "/client's answer is not a gzipped tar"
for f in Makefile LICENSE build/plugin.mk plugins/xymonapi/PLUGIN plugins/xymonapi-mcp/PLUGIN plugins/xymonapi-rag/PLUGIN \
         plugins/xymonapi/xymonapi_client.py plugins/xymonapi-mcp/server.py; do
	grep -qx "xymon-plugins/$f" "$work/list" || fail "the archive has no $f: $(head -n 20 "$work/list")"
done
grep -q '/tests/' "$work/list" && fail "the archive holds tests: $(grep '/tests/' "$work/list" | head -n 3)"
grep -q '__pycache__' "$work/list" && fail "the archive holds __pycache__"

# A machine installs the MCP server from it, as its README says.
mkdir -p "$work/laptop"
tar -xzf "$work/client.tgz" -C "$work/laptop"
[ -L "$work/laptop/xymon-plugins/plugins/xymonapi-mcp/xymonapi_client.py" ] || fail "the MCP server's link to the client did not come through as a link"
"$make" -C "$work/laptop/xymon-plugins/plugins/xymonapi-mcp" install-client PREFIX="$work/prefix" >"$work/client.log" 2>&1 \
	|| fail "make install-client from the archive failed: $(tail -n 5 "$work/client.log")"
for c in xymonapi-mcp xymonapi-connect; do
	[ -x "$work/prefix/bin/$c" ] || fail "installing from the archive gave no $c"
done
assert_equal "$(cat "$work/inst/ext/xymonapi/VERSION")" "$(cat "$work/prefix/libexec/xymon-plugins/xymonapi/VERSION")" \
	"the client installed from the archive is the server's version"
assert_equal "$(sed -n 's/^version: *//p' "$ROOT/plugins/xymonapi-mcp/PLUGIN")" "$(cat "$work/prefix/libexec/xymon-plugins/xymonapi-mcp/VERSION")" \
	"and so is the MCP server"

# Uninstalled from the server, a plugin leaves the archive; xymonapi stays
# while one staged needs it.
"$make" -C "$ROOT/plugins/xymonapi-rag" uninstall XYMONHOME="$work/inst" MANDIR="$work/man" >"$work/un.log" 2>&1 \
	|| fail "make uninstall of xymonapi-rag failed: $(tail -n 5 "$work/un.log")"
tar -tzf <(curl -s "$client") > "$work/list2"
grep -q '^xymon-plugins/plugins/xymonapi-rag/' "$work/list2" && fail "an uninstalled plugin stayed in the archive"
grep -q '^xymon-plugins/plugins/xymonapi-mcp/PLUGIN$' "$work/list2" || fail "and took the others with it"
rc=0
"$make" -C "$ROOT/plugins/xymonapi" uninstall XYMONHOME="$work/inst" MANDIR="$work/man" >"$work/un2.log" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "xymonapi was uninstalled while the staged MCP server needs it"
assert_contains "needed by xymonapi-mcp" "$(cat "$work/un2.log")" "and the refusal names it"

pass "/client gives the plugins installed on the server, without their tests, and a machine installs the MCP server from it at the server's versions; an uninstalled plugin leaves it"
