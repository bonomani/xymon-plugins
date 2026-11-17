#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# plugins/xymonapi/tests/xymonapi-connect.sh
#
# xymonapi-connect, as ./xymon-plugin install --tools lays it out, connects a machine to
# the API: it reads a user and a password holding a space, a quote, a
# backslash and a glob character, gets the API to take them as they are, and
# keeps the token it gets for this machine's short hostname -- mode 600, not
# the password -- and prints the settings a client needs. Run again, it keeps
# a token that works and replaces a revoked one; a wrong password is said; a
# Ctrl-C at its password prompt ends it with echo back on and no token; it
# says when the API and the client run different versions, and who can act;
# and a certificate it does not trust is said before anything is asked.
#
# Skips where the API cannot run (tests/lib/xymonapi.sh). Needs the xymon
# client of the Xymon tree in XYMON_SRC (for a free port), Apache's htpasswd,
# curl and openssl.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../../../tests/lib/xymonapi.sh"

ROOT=$(find_root)

require_bin XYMONCLIENT "$XYMON_SRC/common/xymon"
command -v curl >/dev/null 2>&1 || skip "curl is not installed"
command -v htpasswd >/dev/null 2>&1 || skip "Apache's htpasswd is not installed"
command -v openssl >/dev/null 2>&1 || skip "openssl is not installed"

work=$(mktempdir)
server_tree "$work/inst"
register_cleanup 'stop_process "$API_PID"'

# The API as ./xymon-plugin install --server lays it out, its VERSION the client's, and the
# client as ./xymon-plugin install --tools does.
"$ROOT/xymon-plugin" install --server xymonapi XYMONHOME="$work/inst" MANDIR="$work/man" >"$work/install.log" 2>&1 \
	|| fail "xymon-plugin install --server failed: $(tail -n 5 "$work/install.log")"
"$ROOT/xymon-plugin" install --tools xymonapi PREFIX="$work/client" >"$work/client.log" 2>&1 \
	|| fail "xymon-plugin install --tools failed: $(tail -n 5 "$work/client.log")"
connect=$work/client/bin/xymonapi-connect
assert_file_exists "$connect"
mine=$(cat "$work/client/libexec/xymon-plugins/xymonapi/VERSION")
apiver=$work/inst/ext/xymonapi/VERSION
printf '%s\n' "$mine" > "$apiver"
API_ROOT=$work/inst/ext/xymonapi

hard='pa ss"wo\rd*'
htpasswd -cbB "$work/htpasswd" carol "$hard" 2>/dev/null || fail "htpasswd could not add carol"
export XYMON="$XYMONCLIENT" XYMSRV="127.0.0.1:1" XYMONAPI_PASSWD="$work/htpasswd" \
	XYMONAPI_TOKENS="$work/tokens/tokens"
start_api
url=http://127.0.0.1:$API_PORT
cfg=$work/cfg
tok=$cfg/xymonapi/xymon.token

# run [ARG...] -- xymonapi-connect URL with this test's configuration
# directory; stdout in $work/out, stderr in $work/err, its status in rc.
# Its input is redirected from a file, never piped: a pipeline would run it
# in a subshell, and rc would not come back.
run() {
	rc=0
	XDG_CONFIG_HOME="$cfg" HOME="$work" "$connect" "$url" "$@" > "$work/out" 2> "$work/err" || rc=$?
}

# A password file an earlier setup kept: it goes.
mkdir -p "$cfg/xymonapi"
printf '%s\n' "$hard" > "$cfg/xymonapi/xymon.password"
printf 'carol\n%s\n' "$hard" > "$work/in"; run < "$work/in"
[ "$rc" -eq 0 ] || fail "xymonapi-connect failed with $rc: $(cat "$work/err")"
assert_file_exists "$tok"
assert_match '^xat_' "$(cat "$tok")" "it keeps a token, the API having taken carol's password as it is"
assert_equal "-rw-------" "$(ls -l "$tok" | cut -c1-10)" "readable by this user alone"
assert_not_contains "$hard" "$(cat "$tok")" "the token is not the password"
[ -e "$cfg/xymonapi/xymon.password" ] && fail "the old password file was left"
assert_contains "XYMONAPI_URL=$url" "$(cat "$work/out")" "it prints the API's address"
assert_contains "XYMONAPI_TOKEN_FILE=$tok" "$(cat "$work/out")" "and the token file"
assert_not_contains "XYMONAPI_CA" "$(cat "$work/out")" "and no certificate, over http"
assert_equal "$url" "$(cat "$cfg/xymonapi/xymon.url")" "it keeps the URL beside the token"
# A client given no setting reads the URL kept, and sends the token beside it.
assert_contains '"version"' "$(XDG_CONFIG_HOME="$cfg" HOME="$work" env -u XYMONAPI_URL -u XYMONAPI_TOKEN_FILE -u XYMONAPI_TOKEN -u XYMONAPI_CA -u XYMONAPI_SOCKET -u XYMONRUNDIR -u XYMONSERVERLOGS \
	"${XYMONAPI_PYTHON:-python3}" -c 'import sys, json; sys.path.insert(0, sys.argv[1]); import xymonapi_client as c; print(json.dumps({"health": c.api("/health")}))' \
	"$work/client/libexec/xymon-plugins/xymonapi" 2>&1)" "a client with no XYMONAPI_URL reaches the API connected to, with its token"
assert_not_contains "differ" "$(cat "$work/err")" "the same version on both sides is not remarked on"
assert_not_contains "runs xymonapi" "$(cat "$work/err")" "nor said at all"
h=$(hostname)
assert_contains "\"client\":\"${h%%.*}\"" "$(curl -s -u "carol:$hard" "$url/xymon/api/v1/tokens")" "the token is for this machine's short name"

# Again: the token works, so it is kept and nothing is asked.
first=$(cat "$tok")
run < /dev/null
[ "$rc" -eq 0 ] || fail "a second run failed with $rc: $(cat "$work/err")"
assert_equal "$first" "$(cat "$tok")" "a token that works is kept"
assert_not_contains "password for" "$(cat "$work/err")" "and no password asked"

# Revoked on the server: a new one, with the password asked again.
curl -s -o /dev/null -u "carol:$hard" -X DELETE "$url/xymon/api/v1/tokens/${h%%.*}"
printf 'carol\n%s\n' "$hard" > "$work/in"; run < "$work/in"
[ "$rc" -eq 0 ] || fail "a run after revoking failed with $rc: $(cat "$work/err")"
[ "$first" != "$(cat "$tok")" ] || fail "a revoked token was kept"
assert_match '^xat_' "$(cat "$tok")" "a revoked token is replaced"

# Kept for another server under the same name: the token is not sent here,
# though it would work; the password is asked, and the URL kept is this one.
echo "http://another.example:1986" > "$cfg/xymonapi/xymon.url"
printf 'carol\n%s\n' "$hard" > "$work/in"; run < "$work/in"
[ "$rc" -eq 0 ] || fail "a run after another server's failed with $rc: $(cat "$work/err")"
assert_contains "password for" "$(cat "$work/err")" "a token kept for another URL is not sent: the password is asked"
assert_equal "$url" "$(cat "$cfg/xymonapi/xymon.url")" "and the URL kept is this one"

# A wrong password: said, and nothing written.
curl -s -o /dev/null -u "carol:$hard" -X DELETE "$url/xymon/api/v1/tokens/${h%%.*}"
second=$(cat "$tok")
printf 'carol\nwrong\n' > "$work/in"; run < "$work/in"
assert_equal "1" "$rc" "a wrong password fails"
assert_contains "refused the password for carol" "$(cat "$work/err")" "and says so"
assert_equal "$second" "$(cat "$tok")" "and writes no token"

# The versions: an older API is the server admin's to update, an older
# client this machine's. The token above is revoked: a fresh one first.
# The API reads its version when it starts: each is a restart with another
# VERSION beside it, and the tokens file, with the token, stays.
api_at() {
	printf '%s\n' "$1" > "$apiver"
	stop_process "$API_PID"; API_PID=""
	start_api
	url=http://127.0.0.1:$API_PORT
}
printf 'carol\n%s\n' "$hard" > "$work/in"; run < "$work/in"
# Each restart is on another port, so another URL: the token kept is not
# sent there, and the password is asked.
api_at 0.0.1
run < "$work/in"
assert_contains "the API runs xymonapi 0.0.1, this machine's client $mine: the server's admin" "$(cat "$work/err")" "an older API: the server's admin updates it"
api_at 99.0.0
run < "$work/in"
assert_contains "the API runs xymonapi 99.0.0, this machine's client $mine: update here" "$(cat "$work/err")" "an older client: this machine updates"
api_at "$mine"

# A Ctrl-C at the password prompt, on a terminal: echo back on, no token.
# No virtualenv and no XYMONAPI_PYTHON: the python3 on PATH runs it, and the
# password is the first thing asked -- no question about a virtualenv.
mkdir -p "$work/cfg2"
rc=0
out=$(XDG_CONFIG_HOME="$work/cfg2" HOME="$work" XYMONAPI_USER=carol XYMONAPI_PYTHON="" \
	"${XYMONAPI_PYTHON:-python3}" "$ROOT/tests/lib/ctrl-c.py" 'password for carol: ' "$connect" "$url" 2>&1) || rc=$?
assert_equal "130" "$rc" "Ctrl-C at the password prompt ends it ($out)"
assert_contains "echo on" "$out" "with echo back on"
assert_not_contains "Traceback" "$out" "and no traceback on the terminal"
[ -e "$work/cfg2/xymonapi/xymon.token" ] && fail "a token was kept after Ctrl-C"
stop_process "$API_PID"; API_PID=""

# A certificate this machine does not trust: said first, with where to copy
# it, before a user or password is asked; copied there, it is used.
mkdir -p "$work/tls"
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=xymon-test" \
	-addext "subjectAltName=IP:127.0.0.1" \
	-keyout "$work/tls/xymond.key" -out "$work/tls/xymond.pem" > /dev/null 2>&1 \
	|| fail "openssl could not make a certificate"
chmod 600 "$work/tls/xymond.key"
XYMONAPI_PASSWD="" XYMONAPI_TLS_CERT="$work/tls/xymond.pem" XYMONAPI_TLS_KEY="$work/tls/xymond.key" start_api
url=https://127.0.0.1:$API_PORT
cfg=$work/cfg3
mkdir -p "$cfg/xymonapi"
printf 'carol\n%s\n' "$hard" > "$work/in"; run < "$work/in"
assert_equal "1" "$rc" "an untrusted certificate stops it"
assert_contains "copy the server's certificate, or the CA that signed it, to $cfg/xymonapi/xymon-ca.pem" "$(cat "$work/err")" "saying where to copy it"
assert_not_contains "password" "$(cat "$work/err")" "before a password is asked"
assert_not_contains "user:" "$(cat "$work/err")" "or a user"
cp "$work/tls/xymond.pem" "$cfg/xymonapi/xymon-ca.pem"
# A token kept for another server under the same name: this API asks none,
# so it goes, and is said to, rather than be sent here by a client later.
printf 'xat_issuedbyanother\n' > "$cfg/xymonapi/xymon.token"
echo "https://another.example:8443" > "$cfg/xymonapi/xymon.url"
run < /dev/null
[ "$rc" -eq 0 ] || fail "with the certificate copied, it failed with $rc: $(cat "$work/err")"
assert_contains "XYMONAPI_CA=$cfg/xymonapi/xymon-ca.pem" "$(cat "$work/out")" "the copied certificate is used, and printed"
assert_not_contains "XYMONAPI_TOKEN_FILE" "$(cat "$work/out")" "an API that asks no password needs no token"
[ -e "$cfg/xymonapi/xymon.token" ] && fail "a token kept for another URL was left beside this one's"
assert_contains "the token kept for https://another.example:8443" "$(cat "$work/err")" "and its removal is said"
assert_equal "$url" "$(cat "$cfg/xymonapi/xymon.url")" "the URL kept is this one"
stop_process "$API_PID"; API_PID=""

# An API that issues a token, then fails the /health that follows: the
# token stays beside its own URL, never the one kept before. A stand-in
# of the test's own: 401 without a token, a token for a password, 500
# with it.
cat > "$work/issuer.py" <<'PY'
import http.server, json, sys
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _r(self, code, body):
        b = json.dumps(body).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        self._r(500 if self.headers.get("Authorization", "").startswith("Bearer") else 401, {"error": "x"})
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        self._r(201, {"token": "xat_issuedbyF"})
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
fport=$(free_port)
"${XYMONAPI_PYTHON:-python3}" "$work/issuer.py" "$fport" & API_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do curl -s -o /dev/null "http://127.0.0.1:$fport/" && break; sleep 0.3; done
cfg=$work/cfg4; mkdir -p "$cfg/xymonapi"
printf 'xat_issuedbyA\n' > "$cfg/xymonapi/xymon.token"
echo "https://a.example:8443" > "$cfg/xymonapi/xymon.url"
url=http://127.0.0.1:$fport
printf 'carol\n%s\n' "$hard" > "$work/in"; run < "$work/in"
assert_equal "1" "$rc" "a /health that fails after the token is issued fails the run"
assert_equal "$url" "$(cat "$cfg/xymonapi/xymon.url")" "the URL kept is the one that issued the token"
assert_equal "xat_issuedbyF" "$(cat "$cfg/xymonapi/xymon.token")" "beside its token"

# Where the URL cannot be kept -- a directory in its place, which no
# rename replaces, as root too -- the run fails, said so with no
# traceback, and no token is left for a client to send anywhere.
printf 'xat_issuedbyA\n' > "$cfg/xymonapi/xymon.token"
rm -f "$cfg/xymonapi/xymon.url"; mkdir "$cfg/xymonapi/xymon.url"
printf 'carol\n%s\n' "$hard" > "$work/in"; run < "$work/in"
assert_equal "1" "$rc" "a token whose URL cannot be kept fails the run"
assert_contains "cannot keep the token" "$(cat "$work/err")" "and says so"
assert_not_contains "Traceback" "$(cat "$work/err")" "with no traceback"
[ -e "$cfg/xymonapi/xymon.token" ] && fail "a token was left with no URL kept beside it"
assert_equal "" "$(ls -A "$cfg/xymonapi" | grep '^\.')" "and nothing written aside is left"
stop_process "$API_PID"; API_PID=""

# A command just typed reads the address anew: an API it cannot reach asks
# no restart, only what to check.
rc=0
XDG_CONFIG_HOME="$work/cfg-none" HOME="$work" "$connect" http://127.0.0.1:1 </dev/null >"$work/out" 2>"$work/err" || rc=$?
[ "$rc" -ne 0 ] || fail "connect to an API not there succeeded"
assert_contains "is the API running, and XYMONAPI_URL right" "$(cat "$work/err")" "an API not reached says what to check"
assert_not_contains "restart" "$(cat "$work/err")" "and asks no restart of a command just typed"

pass "xymonapi-connect gets this machine a token with a password typed once, keeps it while it works, says a wrong password, a version difference and an untrusted certificate, and stops cleanly on Ctrl-C"
