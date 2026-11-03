#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# plugins/xymonapi/tests/xymonapi-socket.sh
#
# Beside its port the API listens on a Unix socket, XYMONAPI_SOCKET or
# $XYMONVAR/xymonapi/api.sock, mode 660 in a directory of 750, for this
# machine's own clients: a request there needs no password, since the
# socket's permissions already decided who connects, while the same request
# on the port is still refused without one. The token operations are the
# exception, refused through the socket, because they say who the caller is.
# The socket is removed when the API stops, and not made when the setting is
# empty. The client takes unix:PATH as its URL, and that socket by default
# when XYMONVAR says where it is: xymonapi-connect over it asks nothing and
# keeps no token, and the MCP server reads the API through it.
#
# Skips where the API cannot run (tests/lib/xymonapi.sh). Needs the xymon
# client of the Xymon tree in XYMON_SRC (for a free port), Apache's htpasswd
# and a curl with --unix-socket.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../../../tests/lib/xymonapi.sh"

ROOT=$(find_root)

require_bin XYMONCLIENT "$XYMON_SRC/common/xymon"
command -v curl >/dev/null 2>&1 || skip "curl is not installed"
command -v htpasswd >/dev/null 2>&1 || skip "Apache's htpasswd is not installed"

work=$(mktempdir)
register_cleanup 'stop_process "$API_PID"'

htpasswd -cb "$work/htpasswd" alice secret 2>/dev/null

# Every answer checked here needs no xymond: /health says alive:false
# without one, and the password is checked first.
export XYMON="$XYMONCLIENT" XYMSRV="127.0.0.1:1" XYMONAPI_PASSWD="$work/htpasswd" \
	XYMONAPI_TOKENS="$work/var/xymonapi/tokens" XYMONVAR="$work/var"
sock=$work/var/xymonapi/api.sock
start_api

# over PATH -- the status, and the body, of PATH asked through the socket.
over() { curl -s --unix-socket "$sock" -o /dev/null -w '%{http_code}' --max-time 30 "http://localhost$1"; }

assert_equal "srw-rw----" "$(ls -ld "$sock" | cut -c1-10)" "the socket, mode 660, where XYMONVAR says"
assert_equal "drwxr-x---" "$(ls -ld "$work/var/xymonapi" | cut -c1-10)" "in a directory of mode 750"
assert_contains "listening on the socket $sock" "$(cat "$work/api.log")" "the log says so"
assert_equal "401" "$(api_code /health)" "[C3] the port, without a user: refused as before"
assert_equal "200" "$(over /xymon/api/v1/health)" "the socket, without a user: answered"
assert_equal "200" "$(over /openapi.json)" "and FastAPI's own paths with it"
assert_equal "502" "$(over /xymon/api/v1/states)" "a board asked through it reaches xymond (none here: 502, not 401)"
assert_equal "401" "$(over /xymon/api/v1/tokens)" "the token operations take the password, not the socket"
assert_contains "not through the socket" "$(curl -s --unix-socket "$sock" "http://localhost/xymon/api/v1/tokens")" "and say so"
assert_equal "401" "$(curl -s --unix-socket "$sock" -o /dev/null -w '%{http_code}' -X POST -d '{"client":"here"}' -H 'Content-Type: application/json' "http://localhost/xymon/api/v1/tokens")" "a new token neither"

# The client over the socket: xymonapi-connect, with no terminal and nothing
# on stdin, asks nothing, keeps nothing, and prints the URL alone.
rc=0
XDG_CONFIG_HOME="$work/cfg" "$ROOT/plugins/xymonapi/xymonapi-connect.sh" "unix:$sock" </dev/null >"$work/connect.out" 2>"$work/connect.err" || rc=$?
assert_equal "0" "$rc" "xymonapi-connect over the socket: connected ($(cat "$work/connect.err"))"
assert_equal "XYMONAPI_URL=unix:$sock" "$(cat "$work/connect.out")" "its settings: the URL, no token file, no CA"
assert_contains "asks no credential" "$(cat "$work/connect.err")" "and it says why there is no token"
[ -e "$work/cfg/xymon-api/xymon.token" ] && fail "a token file was written for a socket that asks none"

# The MCP server reads the API through it.
mcp "unix:$sock" '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"health","arguments":{}}}' \
	|| fail "the MCP server exited with $?: $(cat "$work/mcp.err")"
assert_contains 'alive\": false' "$(cat "$work/mcp.out")" "the MCP server's health tool, through the socket"
assert_not_contains "isError\":true" "$(cat "$work/mcp.out")" "with no error"

# With no XYMONAPI_URL, a client on the server takes the socket XYMONVAR
# leads to.
mcp "" '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"health","arguments":{}}}' \
	|| fail "the MCP server with no URL exited with $?: $(cat "$work/mcp.err")"
assert_contains 'alive\": false' "$(cat "$work/mcp.out")" "the MCP server with no XYMONAPI_URL finds the socket through XYMONVAR"

stop_process "$API_PID"
API_PID=""
[ -e "$sock" ] && fail "the socket $sock is still there after the API stopped"

# XYMONAPI_SOCKET names another; set empty, there is none.
XYMONAPI_SOCKET="$work/other.sock" start_api
assert_equal "200" "$(sock=$work/other.sock; over /xymon/api/v1/health)" "XYMONAPI_SOCKET names the socket"
[ -e "$sock" ] && fail "the default socket was made beside the one XYMONAPI_SOCKET names"
stop_process "$API_PID"
API_PID=""
XYMONAPI_SOCKET="" start_api
[ -e "$sock" ] && fail "XYMONAPI_SOCKET set empty, and a socket was made"
assert_not_contains "listening on the socket" "$(cat "$work/api.log")" "and the log does not say so"
stop_process "$API_PID"
API_PID=""

pass "the API answers its Unix socket without a password, its port not; the token operations take the password through either; the client takes unix:PATH, and the socket by default on the server"
