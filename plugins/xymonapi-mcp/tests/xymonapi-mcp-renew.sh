#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# plugins/xymonapi-mcp/tests/xymonapi-mcp-renew.sh
#
# An MCP server already running needs no reconnecting. Installed in a
# scratch PREFIX and started as an AI tool starts it, with XYMONAPI_NAME and
# no XYMONAPI_URL, on one connection kept open:
#
# - it reads the URL kept for its connection at each call: kept wrong, a
#   call fails; kept right, the next call reaches the API;
# - an update of its code, between two requests, is run in its place, the
#   same process and connection, the request read meanwhile answered by the
#   new code;
# - an update whose code does not start leaves it on the code it runs, each
#   answer saying so.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../../../tests/lib/xymonapi.sh"

ROOT=$(find_root)
require_bin XYMONCLIENT "$XYMON_SRC/common/xymon"
command -v curl >/dev/null 2>&1 || skip "curl is not installed"
command -v mkfifo >/dev/null 2>&1 || skip "mkfifo is not here"

work=$(mktempdir)
SPID="" API_PID=""
register_cleanup 'exec 3>&- 2>/dev/null || :; stop_process "$SPID" "$API_PID"'

# The API, no xymond behind it: /health answers all the same.
export XYMON="$XYMONCLIENT" XYMSRV="127.0.0.1:1"
export XYMONAPI_PASSWD=""
start_api

# Three checkouts: v1 as it is; v2 a newer version; v3 one whose server
# does not start.
for v in v1 v2 v3; do
	mkdir -p "$work/$v"
	cp -R "$ROOT/xymon-plugin" "$ROOT/LICENSE" "$ROOT/plugins" "$work/$v/"
done
sed 's/^version: .*/version: 9.9.9/' "$ROOT/plugins/xymonapi-mcp/PLUGIN" > "$work/v2/plugins/xymonapi-mcp/PLUGIN"
sed 's/^version: .*/version: 9.9.10/' "$ROOT/plugins/xymonapi-mcp/PLUGIN" > "$work/v3/plugins/xymonapi-mcp/PLUGIN"
echo "def broken(:" >> "$work/v3/plugins/xymonapi-mcp/server.py"

export PREFIX="$work/prefix" XDG_CONFIG_HOME="$work/cfg" HOME="$work"
"$work/v1/xymon-plugin" install --tools xymonapi-mcp </dev/null >"$work/x.log" 2>&1 \
	|| fail "install --tools xymonapi-mcp failed: $(tail -n 3 "$work/x.log")"
mkdir -p "$work/cfg/xymonapi"
echo "http://127.0.0.1:1" > "$work/cfg/xymonapi/xymon.url"

# The server, as an AI tool starts it, on a connection kept open.
mkfifo "$work/in"
( unset XYMONAPI_URL; XYMONAPI_NAME=xymon exec "$PREFIX/libexec/xymon-plugins/xymonapi-mcp/xymonapi-mcp.sh" ) \
	< "$work/in" > "$work/out" 2> "$work/err" &
SPID=$!
exec 3> "$work/in"
send() { printf '%s\n' "$1" >&3; }
# reply ID -- the server's answer to request ID, waited for.
reply() {
	for _ in $(seq 300); do
		l=$(grep "\"id\":$1[,}]" "$work/out" | tail -n 1 || :)
		[ -n "$l" ] && { printf '%s' "$l"; return 0; }
		sleep 0.1
	done
	fail "no answer to request $1: $(tail -n 5 "$work/err")"
}
health() { send "{\"jsonrpc\":\"2.0\",\"id\":$1,\"method\":\"tools/call\",\"params\":{\"name\":\"health\",\"arguments\":{}}}"; reply "$1"; }

send '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}'
assert_contains '"serverInfo"' "$(reply 1)" "the server starts"
send '{"jsonrpc":"2.0","method":"notifications/initialized"}'

# The URL kept, read at each call.
r=$(health 2)
assert_contains 'cannot reach xymonapi at http://127.0.0.1:1' "$r" "the URL kept wrong: the call fails"
assert_not_contains 'keeps the XYMONAPI_URL' "$r" "and, no XYMONAPI_URL given, asks no reconnecting"
echo "http://127.0.0.1:$API_PORT" > "$work/cfg/xymonapi/xymon.url"
r=$(health 3)
assert_contains '\"api\"' "$r" "the URL kept right: the next call reaches the API, no reconnecting"
assert_not_contains '"isError":true' "$r" "and is no error"

# An update of its code, between two requests: run in its place.
"$work/v2/xymon-plugin" update --tools xymonapi-mcp </dev/null >"$work/x.log" 2>&1 \
	|| fail "update to v2 failed: $(tail -n 3 "$work/x.log")"
send '{"jsonrpc":"2.0","id":4,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}'
assert_contains '"version":"9.9.9"' "$(reply 4)" "the request read after an update is answered by the new code"
kill -0 "$SPID" 2>/dev/null || fail "the server's process is gone"
assert_not_contains '"isError":true' "$(health 5)" "and the same connection goes on"

# An update whose code does not start: the code it runs stays, and says so.
"$work/v3/xymon-plugin" update --tools xymonapi-mcp </dev/null >"$work/x.log" 2>&1 \
	|| fail "update to v3 failed: $(tail -n 3 "$work/x.log")"
r=$(health 6)
assert_contains 'the code installed since does not start' "$r" "new code that does not start: the answer says so"
assert_contains '/mcp in Claude Code reconnects it' "$r" "naming /mcp"
send '{"jsonrpc":"2.0","id":7,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}'
assert_contains '"version":"9.9.9"' "$(reply 7)" "and the code it runs is the one that started"

pass "an MCP server already running reads the URL kept at each call, runs an update's code in its place on the same connection, and stays, saying so, on code that does not start"
