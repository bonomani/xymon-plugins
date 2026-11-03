#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# plugins/xymonapi/tests/xymonapi-tls.sh
#
# With a certificate and key -- xymond's own, $XYMONHOME/etc/tls/xymond.pem
# and .key as xymon-tls(7) places them, or the files XYMONAPI_TLS_CERT and
# XYMONAPI_TLS_KEY name -- the API speaks HTTPS on its port, and plain HTTP
# gets no answer. A key that others can read, or a certificate without its
# key, stops the API from starting. The MCP client against it is
# xymonapi-mcp-access's; xymonapi-connect against it, xymonapi-connect's.
#
# Skips where the API cannot run (tests/lib/xymonapi.sh) or openssl is not
# installed. Needs the xymon client of the Xymon tree in XYMON_SRC and curl.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../../../tests/lib/xymonapi.sh"

ROOT=$(find_root)

require_bin XYMONCLIENT "$XYMON_SRC/common/xymon"
command -v curl >/dev/null 2>&1 || skip "curl is not installed"
command -v openssl >/dev/null 2>&1 || skip "openssl is not installed"

work=$(mktempdir)
register_cleanup 'stop_process "$API_PID"'

# A self-signed certificate for 127.0.0.1, as xymon-tls(7) would make one.
mkdir -p "$work/home/etc/tls"
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=xymon-test" \
	-addext "subjectAltName=IP:127.0.0.1" \
	-keyout "$work/home/etc/tls/xymond.key" -out "$work/home/etc/tls/xymond.pem" > /dev/null 2>&1 \
	|| fail "openssl could not make a certificate"
chmod 600 "$work/home/etc/tls/xymond.key"

export XYMON="$XYMONCLIENT" XYMSRV="127.0.0.1:1"

# xymond's own files, found through XYMONHOME: nothing else set.
export XYMONHOME="$work/home" XYMONAPI_TLS_CERT="$work/home/etc/tls/xymond.pem"
start_api
assert_contains '"alive"' "$(api_get /health)" "the API answers over HTTPS with xymond's certificate"
assert_equal "000" "$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$API_PORT/xymon/api/v1/health" || true)" "and not over plain HTTP"


# Files named explicitly, elsewhere.
cp "$work/home/etc/tls/xymond.pem" "$work/other.pem"; cp "$work/home/etc/tls/xymond.key" "$work/other.key"
unset XYMONHOME
XYMONAPI_TLS_CERT="$work/other.pem" XYMONAPI_TLS_KEY="$work/other.key" start_api
assert_contains '"alive"' "$(XYMONAPI_TLS_CERT="$work/other.pem" api_get /health)" "named certificate and key files"
stop_process "$API_PID"; API_PID=""

# Refusals, each with its reason.
unset XYMONAPI_TLS_CERT
chmod 644 "$work/other.key"
rc=0
XYMONAPI_TLS_CERT="$work/other.pem" XYMONAPI_TLS_KEY="$work/other.key" "$ROOT/plugins/xymonapi/xymonapi.sh" > "$work/open.log" 2>&1 || rc=$?
assert_equal "1" "$rc" "a key others can read"
assert_contains 'readable by others' "$(cat "$work/open.log")" "and it says so"
rc=0
XYMONAPI_TLS_CERT="$work/other.pem" XYMONAPI_TLS_KEY="$work/no-such.key" "$ROOT/plugins/xymonapi/xymonapi.sh" > "$work/nokey.log" 2>&1 || rc=$?
assert_equal "1" "$rc" "a certificate without its key"
assert_contains 'cannot read the TLS key' "$(cat "$work/nokey.log")" "and it says which"
rm "$work/home/etc/tls/xymond.key"
rc=0
XYMONHOME="$work/home" "$ROOT/plugins/xymonapi/xymonapi.sh" > "$work/half.log" 2>&1 || rc=$?
assert_equal "1" "$rc" "xymond's certificate present but not its key"
assert_contains 'xymond.key' "$(cat "$work/half.log")" "and it names the file"

pass "with xymond's certificate, or named files, the API speaks HTTPS, and a bad key refuses to start"
