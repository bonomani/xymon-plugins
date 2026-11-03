#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# plugins/xymonapi-mcp/tests/xymonapi-mcp-access.sh
#
# The MCP server's client reaches an API that asks for a user: it sends the
# token from XYMONAPI_TOKEN_FILE and is let in; it sends nothing else -- a
# user and password left in its environment, as an older setup wrote them,
# are not sent, and the refusal says to set the token file. Over HTTPS, a
# certificate the system does not trust is refused, naming XYMONAPI_CA, and
# with XYMONAPI_CA naming it the client is let in.
#
# Skips where the API or the MCP server cannot run (tests/lib/xymonapi.sh).
# Needs the xymon client of the Xymon tree in XYMON_SRC (for a free port),
# curl, Apache's htpasswd and openssl.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../../../tests/lib/xymonapi.sh"

ROOT=$(find_root)

require_bin XYMONCLIENT "$XYMON_SRC/common/xymon"
command -v curl >/dev/null 2>&1 || skip "curl is not installed"
command -v htpasswd >/dev/null 2>&1 || skip "Apache's htpasswd is not installed"
command -v openssl >/dev/null 2>&1 || skip "openssl is not installed"

work=$(mktempdir)
register_cleanup 'stop_process "$API_PID"'

htpasswd -cbB "$work/htpasswd" alice secret 2>/dev/null
export XYMON="$XYMONCLIENT" XYMSRV="127.0.0.1:1"
XYMONAPI_PASSWD="$work/htpasswd" XYMONAPI_TOKENS="$work/var/tokens" start_api
health='{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"health","arguments":{}}}'

# With the token in XYMONAPI_TOKEN_FILE.
curl -s -u alice:secret -X POST -H 'Content-Type: application/json' -d '{"client":"laptop"}' \
	"http://127.0.0.1:$API_PORT/xymon/api/v1/tokens" \
	| sed -n 's/.*"token": *"\(xat_[A-Za-z0-9_-]*\)".*/\1/p' > "$work/alice.token"
[ -s "$work/alice.token" ] || fail "the API gave alice no token"
rc=0
XYMONAPI_TOKEN_FILE="$work/alice.token" mcp "http://127.0.0.1:$API_PORT" "$health" || rc=$?
[ "$rc" -eq 77 ] && skip "$(cat "$work/mcp.err")"
answer=$(grep '"id":3' "$work/mcp.out") || fail "no answer from the MCP server: $(tail -n 5 "$work/mcp.err")"
assert_not_contains '"isError":true' "$answer" "the MCP client is let in with the token file"

# A token and nothing else: a user and password in its environment are not
# sent.
printf 'secret\n' > "$work/password"
XYMONAPI_USER=alice XYMONAPI_PASSWORD=secret XYMONAPI_PASSWORD_FILE="$work/password" \
	mcp "http://127.0.0.1:$API_PORT" "$health" || true
answer=$(grep '"id":3' "$work/mcp.out") || fail "no answer to the health call: $(tail -n 5 "$work/mcp.err")"
assert_contains 'answered 401' "$answer" "the MCP client sends no password, even one in its environment"
assert_contains 'XYMONAPI_TOKEN_FILE' "$answer" "and says to set the token file"
stop_process "$API_PID"; API_PID=""

# Over HTTPS, with a self-signed certificate for 127.0.0.1, as xymon-tls(7)
# would make one: refused without the CA, let in with it.
mkdir -p "$work/tls"
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=xymon-test" \
	-addext "subjectAltName=IP:127.0.0.1" \
	-keyout "$work/tls/xymond.key" -out "$work/tls/xymond.pem" > /dev/null 2>&1 \
	|| fail "openssl could not make a certificate"
chmod 600 "$work/tls/xymond.key"
XYMONAPI_PASSWD="" XYMONAPI_TLS_CERT="$work/tls/xymond.pem" XYMONAPI_TLS_KEY="$work/tls/xymond.key" start_api
mcp "https://127.0.0.1:$API_PORT" "$health" || true
answer=$(grep '"id":3' "$work/mcp.out") || fail "no answer to the health call: $(tail -n 5 "$work/mcp.err")"
assert_contains 'certificate this machine does not trust' "$answer" "the MCP client refuses a certificate it does not know"
assert_contains 'XYMONAPI_CA' "$answer" "and names the setting"
XYMONAPI_CA="$work/tls/xymond.pem" mcp "https://127.0.0.1:$API_PORT" "$health" || true
answer=$(grep '"id":3' "$work/mcp.out")
assert_contains 'alive' "$answer" "with XYMONAPI_CA it is let in"
assert_not_contains '"isError":true' "$answer" "and not refused"

pass "the MCP client sends its token file and no password, and trusts the certificate XYMONAPI_CA names"
