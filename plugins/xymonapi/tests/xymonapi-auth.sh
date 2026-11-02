#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# plugins/xymonapi/tests/xymonapi-auth.sh
#
# With XYMONAPI_PASSWD naming an htpasswd file, the API answers only a user
# and password that file holds, and 401 with a WWW-Authenticate challenge to
# anything else. Both formats Apache's htpasswd writes are accepted: $apr1$,
# its default and what Xymon's useradm and chpasswd create, and bcrypt. Every
# path is covered, /openapi.json and FastAPI's /docs included. A user
# name that looks like an option is refused, not passed to htpasswd as one.
# A password file the API cannot read stops it from starting. /client alone
# is open: it writes a setup script with the address asked and no user or
# version; /health gives the version, to a user, and only fields the spec
# lists. Running that script is tests/compat/xymonapi-setup.sh's.
#
# Skips where the API cannot run (tests/lib/xymonapi.sh). Needs the xymon
# client of the Xymon tree in XYMON_SRC (for a free port), Apache's htpasswd
# and curl.

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
htpasswd -bB "$work/htpasswd" bob s3cret 2>/dev/null
grep -q '^alice:\$apr1\$' "$work/htpasswd" || fail "htpasswd did not write alice in its \$apr1\$ format"
grep -q '^bob:\$2y\$' "$work/htpasswd" || fail "htpasswd did not write bob as bcrypt"

# The API as make install lays it out, with a release's VERSION beside it,
# so that /health has one to give and the script one to install.
"${MAKE:-make}" -C "$ROOT" install XYMONHOME="$work/inst" MANDIR="$work/man" >"$work/install.log" 2>&1 \
	|| fail "make install failed: $(tail -n 5 "$work/install.log")"
version=xymonapi/v9.9.9
printf '%s\n' "$version" > "$work/inst/ext/xymonapi/VERSION"
API_ROOT=$work/inst/ext/xymonapi

# The answers checked here need no xymond: /health says alive:false without
# one, and the password is checked first, on every path but /client.
export XYMON="$XYMONCLIENT" XYMSRV="127.0.0.1:1" XYMONAPI_PASSWD="$work/htpasswd" \
	XYMONAPI_TOKENS="$work/tokens/tokens"
start_api

url="http://127.0.0.1:$API_PORT/xymon/api/v1/health"
code() { curl -s -o /dev/null -w '%{http_code}' "$@" "$url"; }

rc=0
assert_equal "401" "$(code)" "[C3] no user and password"
# Header names are case-insensitive, and uvicorn sends them in lower case.
assert_contains 'www-authenticate: basic realm="xymon"' "$(curl -s -D - -o /dev/null "$url" | tr -d '\r' | tr 'A-Z' 'a-z')" "the 401 asks for Basic authentication"
assert_equal "200" "$(code -u alice:secret)" "alice, \$apr1\$, right password"
assert_equal "200" "$(code -H "Authorization: basic $(printf 'alice:secret' | base64)")" "the scheme spelt basic, in lower case"
assert_equal "401" "$(code -u alice:wrong)" "[C3] alice, wrong password"
assert_equal "200" "$(code -u bob:s3cret)" "bob, bcrypt, right password"
assert_equal "401" "$(code -u carol:secret)" "[C3] a user the file does not hold"
assert_equal "401" "$(code -u -b:secret)" "a user name that looks like an option"

# FastAPI serves these beside the API's own paths; a password covers them too.
for path in /openapi.json /docs; do
	assert_equal "401" "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$API_PORT$path")" "[C3] $path without a user"
	assert_equal "200" "$(curl -s -o /dev/null -w '%{http_code}' -u alice:secret "http://127.0.0.1:$API_PORT$path")" "$path with a user"
done

# /client: open, a password set or not, since its script holds nothing
# secret -- the address the request came through, the proxy's when its
# headers say so, and no user or version. The version is /health's, behind
# the password.
assert_equal "200" "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$API_PORT/xymon/api/v1/client")" "[C4] /client without a user"
script=$(curl -s "http://127.0.0.1:$API_PORT/xymon/api/v1/client")
assert_contains "URL=http://127.0.0.1:$API_PORT" "$script" "/client writes the address the request came to"
assert_contains "NAME=xymon" "$script" "and the default name"
printf '%s\n' "$script" | grep -q '^USER=' && fail "[C4] /client wrote a USER= line"
assert_not_contains "$version" "$script" "[C4] and not the version"
assert_contains "\"version\":\"$version\"" "$(curl -s -u alice:secret "$url")" "/health gives the version to a user"
assert_not_contains "$version" "$(curl -s "$url")" "and not to a stranger"
# Every field /health gives is one the spec lists for it: a field renamed in
# the code and not in openapi.yaml is a contract the API does not keep.
spec_fields=$(sed -n '/^    Health:/,/^    [A-Z]/p' "$ROOT/plugins/xymonapi/openapi.yaml" | sed -n 's/^        \([a-z_]*\):.*/\1/p')
for f in $(curl -s -u alice:secret "$url" | "${XYMONAPI_PYTHON:-python3}" -c 'import json, sys; print(" ".join(json.load(sys.stdin)))'); do
	printf '%s\n' "$spec_fields" | grep -qx "$f" || fail "/health gives \"$f\", which openapi.yaml's Health does not list ($(echo $spec_fields))"
done
printf '%s\n' "$script" > "$work/setup.sh"
sh -n "$work/setup.sh" || fail "/client's script does not parse: $(sh -n "$work/setup.sh" 2>&1)"
assert_contains 'text/x-shellscript' "$(curl -s -D - -o /dev/null "http://127.0.0.1:$API_PORT/xymon/api/v1/client" | tr 'A-Z' 'a-z')" "served as a shell script"
proxied=$(curl -s -H 'X-Forwarded-Host: xymon.example.ch' -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$API_PORT/xymon/api/v1/client?name=xymon-lab")
assert_contains "URL=https://xymon.example.ch" "$proxied" "behind a proxy, the proxy's address and scheme"
assert_contains "NAME=xymon-lab" "$proxied" "and the name asked for"
assert_contains 'xymon-api/$NAME.password' "$proxied" "which names the password file too"
assert_equal "400" "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$API_PORT/xymon/api/v1/client?name=bad%20name")" "a name with a space"
assert_equal "400" "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$API_PORT/xymon/api/v1/client?format=exe")" "a format that is neither"
env=$(curl -s "http://127.0.0.1:$API_PORT/xymon/api/v1/client?format=env")
assert_contains "XYMONAPI_URL=http://127.0.0.1:$API_PORT" "$env" "format=env gives the settings"
assert_contains 'XYMONAPI_TOKEN_FILE=${XDG_CONFIG_HOME:-$HOME/.config}/xymon-api/xymon.token' "$env" "with the token file where the script keeps it"
assert_not_contains "git clone" "$env" "and no script"

# Xymon's own password file is the default: with XYMONHOME set and
# etc/xymonpasswd there, nothing else need be set, and the API asks for
# what the web pages ask for. The empty string turns it off.
stop_process "$API_PID"
API_PID=""
mkdir -p "$work/home/etc"; cp "$work/htpasswd" "$work/home/etc/xymonpasswd"
unset XYMONAPI_PASSWD
XYMONHOME="$work/home" start_api
url="http://127.0.0.1:$API_PORT/xymon/api/v1/health"
assert_equal "401" "$(code)" "with XYMONHOME's etc/xymonpasswd and no setting, a password is asked"
assert_equal "200" "$(code -u alice:secret)" "the web pages' user is let in"
stop_process "$API_PID"
API_PID=""
XYMONHOME="$work/home" XYMONAPI_PASSWD="" start_api
url="http://127.0.0.1:$API_PORT/xymon/api/v1/health"
assert_equal "200" "$(code)" "XYMONAPI_PASSWD set empty: no password asked"
stop_process "$API_PID"
API_PID=""
rc=0
XYMONAPI_PASSWD="$work/no-such-file" "$ROOT/plugins/xymonapi/xymonapi.sh" > "$work/nofile.log" 2>&1 || rc=$?
assert_equal "1" "$rc" "the API with a password file it cannot read"
assert_contains "cannot read XYMONAPI_PASSWD" "$(cat "$work/nofile.log")" "and it says why"

pass "XYMONAPI_PASSWD lets in only the users and passwords of its htpasswd file, in either format"
