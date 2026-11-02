#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/xymonapi-setup.sh
#
# The setup script xymonapi's /client writes, run as a laptop runs it,
# installs xymonapi-mcp and xymonapi-rag at the API's version and registers
# the MCP server: it asks for the user and gets a password holding a space,
# a quote, a backslash and a glob character to the API as it is, keeps the
# token it gets for this machine's short hostname instead of the password,
# installs the release /health gives, says how far it is behind the
# newest, and registers the MCP server with that token file in Claude Code
# and Codex. A Ctrl-C at its password prompt ends it with echo back on;
# without make it says so before starting; a virtualenv a run before left
# half made is made again; a certificate it does not trust is said before
# anything is asked.
#
# Skips where the API cannot run (tests/lib/xymonapi.sh). Needs the xymon
# client of the Xymon tree in XYMON_SRC (for a free port), Apache's htpasswd,
# curl and openssl.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)

require_bin XYMONCLIENT "$XYMON_SRC/common/xymon"
command -v curl >/dev/null 2>&1 || skip "curl is not installed"
command -v htpasswd >/dev/null 2>&1 || skip "Apache's htpasswd is not installed"
command -v openssl >/dev/null 2>&1 || skip "openssl is not installed"

work=$(mktempdir)
register_cleanup 'stop_process "$API_PID"'
htpasswd -cbB "$work/htpasswd" alice secret 2>/dev/null

# The API as make install lays it out, with a release's VERSION beside it,
# so that /health has one to give and the script one to install.
"${MAKE:-make}" -C "$ROOT" install XYMONHOME="$work/inst" MANDIR="$work/man" >"$work/install.log" 2>&1 \
	|| fail "make install failed: $(tail -n 5 "$work/install.log")"
version=xymonapi/v9.9.9
printf '%s\n' "$version" > "$work/inst/ext/xymonapi/VERSION"
API_ROOT=$work/inst/ext/xymonapi

export XYMON="$XYMONCLIENT" XYMSRV="127.0.0.1:1" XYMONAPI_PASSWD="$work/htpasswd" \
	XYMONAPI_TOKENS="$work/tokens/tokens"
start_api

# The script's own password path: the user and password are read from the
# terminal -- here stdin -- and the password goes to curl in a config on its
# stdin, with " and \ escaped as curl wants, so one holding a space, a
# quote, a backslash and a glob character reaches the API as it is, and is
# on no command line. The script is run as a laptop would, up to its health
# check and registration: git, make, claude and codex are stubs on PATH
# (git, claude and codex record their arguments; git counts 3 commits
# between the server's and the newest) and the virtualenv is
# already there, so nothing is fetched or built.
hard='pa ss"wo\rd*'
htpasswd -bB "$work/htpasswd" carol "$hard" 2>/dev/null || fail "htpasswd could not add carol"
curl -s "http://127.0.0.1:$API_PORT/xymon/api/v1/client" > "$work/carol.sh"
lap=$work/lap
mkdir -p "$work/stub" "$lap/src/.git" "$lap/prefix/libexec/xymon-plugins/venv/bin" "$lap/cfg/xymon-api"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> "%s/git.args"\ncase " $* " in *" rev-list "*) echo 3 ;; esac\n' "$lap" > "$work/stub/git"
printf '#!/bin/sh\nexit 0\n' > "$work/stub/make"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> "%s/claude.args"\n' "$lap" > "$work/stub/claude"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> "%s/codex.args"\n' "$lap" > "$work/stub/codex"
printf '#!/bin/sh\nexit 0\n' > "$lap/prefix/libexec/xymon-plugins/venv/bin/python3"
chmod 755 "$work/stub/git" "$work/stub/make" "$work/stub/claude" "$work/stub/codex" "$lap/prefix/libexec/xymon-plugins/venv/bin/python3"
# A password file an earlier version of the script kept: it must go.
printf '%s\n' "$hard" > "$lap/cfg/xymon-api/xymon.password"
rc=0
# The user and password on stdin, as a person typing them gives them to read.
out=$(cd "$lap" && printf 'carol\n%s\n' "$hard" | HOME="$lap" XDG_CONFIG_HOME="$lap/cfg" XYMONAPI_SRC="$lap/src" PATH="$work/stub:$PATH" \
	sh "$work/carol.sh" "$lap/prefix" 2>&1) || rc=$?
[ "$rc" -eq 0 ] || fail "the setup script failed with $rc: $out"
assert_not_contains 'refused the password' "$out" "the API took carol's password from the script's curl"
assert_contains "$(printf -- '--detach\n%s' "$version")" "$(cat "$lap/git.args")" "the script installs the release /health gave"
assert_contains "the API runs $version, 3 commit(s) behind the newest" "$out" "and says how far the server is behind the repository's newest, as git counts it"
assert_contains 'the API answers' "$out" "and the script read the answer (no xymond here, so alive is false)"
tok=$lap/cfg/xymon-api/xymon.token
assert_file_exists "$tok"
assert_match '^xat_' "$(cat "$tok")" "the script kept a token"
assert_equal "-rw-------" "$(ls -l "$tok" | cut -c1-10)" "readable by this user alone"
[ -e "$lap/cfg/xymon-api/xymon.password" ] && fail "the old password file was left on the laptop"
assert_not_contains "$hard" "$(cat "$tok")" "the token is not the password"
assert_contains "XYMONAPI_TOKEN_FILE=$tok" "$(cat "$lap/claude.args")" "the MCP registration names the token file"
assert_not_contains 'PASSWORD' "$(cat "$lap/claude.args")" "and no password setting"
assert_contains "XYMONAPI_TOKEN_FILE=$tok" "$(cat "$lap/codex.args")" "Codex is registered too, with the token file"
assert_contains "$lap/prefix/bin/xymonapi-mcp" "$(cat "$lap/codex.args")" "and the MCP server"
assert_not_contains 'PASSWORD' "$(cat "$lap/codex.args")" "and no password setting"
# Named by the short hostname, as the API lists it.
h=$(hostname 2>/dev/null || uname -n)
assert_contains "\"client\":\"${h%%.*}\"" "$(curl -s -u "carol:$hard" "http://127.0.0.1:$API_PORT/xymon/api/v1/tokens")" "the token is for this machine's short name"

# A Ctrl-C at the password prompt ends the script, with echo back on and
# nothing asked, in bash too: bash, out of POSIX mode, runs a trap and goes
# back to the read, which then shows the password as it is typed. On a
# terminal, which tests/lib/ctrl-c.py gives it; a new config directory, so
# the script asks; the user given in XYMONAPI_USER, so the password is the
# first thing asked; the token kept above shows that none was issued for
# this machine, since one would have replaced it.
mkdir -p "$lap/cfg2"
rc=0
out=$(cd "$lap" && HOME="$lap" XDG_CONFIG_HOME="$lap/cfg2" XYMONAPI_SRC="$lap/src" PATH="$work/stub:$PATH" \
	XYMONAPI_USER=carol "${XYMONAPI_PYTHON:-python3}" "$ROOT/tests/lib/ctrl-c.py" 'password for carol: ' bash "$work/carol.sh" "$lap/prefix" 2>&1) || rc=$?
assert_equal "130" "$rc" "Ctrl-C at the password prompt ends the script under bash ($out)"
assert_contains "echo on" "$out" "with echo back on"
[ -e "$lap/cfg2/xymon-api/xymon.token" ] && fail "a token was kept after Ctrl-C"
assert_equal "200" "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $(cat "$tok")" "http://127.0.0.1:$API_PORT/xymon/api/v1/health")" "and none issued: the earlier token still works"

# Without make, the script says so before it starts, rather than failing
# half way with the shell's "not found": a PATH of git, curl and the tools
# the script's first lines use, and no make.
mkdir -p "$work/nomake"
cp "$work/stub/git" "$work/nomake/git"
for t in curl hostname tr sed cut; do
	p=$(command -v "$t") || continue
	ln -s "$p" "$work/nomake/$t"
done
rc=0
sh_bin=$(command -v sh)
out=$(cd "$lap" && HOME="$lap" XDG_CONFIG_HOME="$lap/cfg" XYMONAPI_SRC="$lap/src" PATH="$work/nomake" \
	"$sh_bin" "$work/carol.sh" "$lap/prefix" 2>&1 < /dev/null) || rc=$?
[ "$rc" -ne 0 ] || fail "the setup script went on without make: $out"
assert_contains "make is needed" "$out" "the setup script says make is missing"

# A virtualenv a run before left half made -- its python3 there, without
# mcp -- is made again, not taken as it is: the Python here makes a venv
# whose pip records that it ran.
printf '#!/bin/sh\nexit 1\n' > "$lap/prefix/libexec/xymon-plugins/venv/bin/python3"
cat > "$work/stub/python-venv" <<STUB
#!/bin/sh
if [ "\$1" = -m ]; then
	mkdir -p "\$3/bin"
	printf '#!/bin/sh\\nexit 0\\n' > "\$3/bin/python3"
	printf '#!/bin/sh\\necho pip >> "$lap/pip.log"\\n' > "\$3/bin/pip"
	chmod 755 "\$3/bin/python3" "\$3/bin/pip"
fi
exit 0
STUB
chmod 755 "$work/stub/python-venv"
rc=0
out=$(cd "$lap" && HOME="$lap" XDG_CONFIG_HOME="$lap/cfg" XYMONAPI_SRC="$lap/src" PATH="$work/stub:$PATH" \
	XYMONAPI_PYTHON="$work/stub/python-venv" sh "$work/carol.sh" "$lap/prefix" 2>&1 < /dev/null) || rc=$?
[ "$rc" -eq 0 ] || fail "the setup script failed with $rc over a half-made venv: $out"
assert_file_exists "$lap/pip.log"
assert_contains "pip" "$(cat "$lap/pip.log")" "a half-made venv is made again, and mcp installed in it"
stop_process "$API_PID"; API_PID=""

# A self-signed certificate for 127.0.0.1, as xymon-tls(7) would make one.
mkdir -p "$work/home/etc/tls"
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=xymon-test" \
	-addext "subjectAltName=IP:127.0.0.1" \
	-keyout "$work/home/etc/tls/xymond.key" -out "$work/home/etc/tls/xymond.pem" > /dev/null 2>&1 \
	|| fail "openssl could not make a certificate"
chmod 600 "$work/home/etc/tls/xymond.key"
# The setup script, with no certificate to trust: it says what to do --
# copy the certificate to CAFILE -- and stops, asking nothing. Its first
# request is to /health, and only a 401 there makes it ask for a user and
# password, so a certificate it does not trust is said first; this API asks
# for no password, and the test pins the message. git and make are stubs,
# and the virtualenv is there, so nothing is fetched or built.
XYMONHOME="$work/home" XYMONAPI_PASSWD="" XYMONAPI_TLS_CERT="$work/home/etc/tls/xymond.pem" start_api
lap=$work/lap-tls
mkdir -p "$lap/src/.git" "$lap/prefix/libexec/xymon-plugins/venv/bin" "$lap/cfg"
printf '#!/bin/sh\nexit 0\n' > "$lap/prefix/libexec/xymon-plugins/venv/bin/python3"
chmod 755 "$lap/prefix/libexec/xymon-plugins/venv/bin/python3"
XYMONAPI_TLS_CERT="$work/home/etc/tls/xymond.pem" api_get /client > "$work/setup.sh"
rc=0
out=$(cd "$lap" && printf 'secret\n' | HOME="$lap" XDG_CONFIG_HOME="$lap/cfg" XYMONAPI_SRC="$lap/src" PATH="$work/stub:$PATH" \
	sh "$work/setup.sh" "$lap/prefix" 2>&1) || rc=$?
[ "$rc" -ne 0 ] || fail "the setup script went on with a certificate it does not trust: $out"
assert_contains "copy the server's certificate" "$out" "the setup script says what to do with an unknown certificate"
assert_not_contains "password" "$out" "before it asks for a password"
assert_not_contains "user:" "$out" "or a user"

pass "the setup script installs the client side at the API's version with a token, not a password, registers it in Claude Code and Codex, and stops cleanly on Ctrl-C, without make, and on an unknown certificate"
