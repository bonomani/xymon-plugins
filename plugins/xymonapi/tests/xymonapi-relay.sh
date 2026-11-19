#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# plugins/xymonapi/tests/xymonapi-relay.sh
#
# The relay socket for the web server: with XYMONAPI_RELAY_SOCKET, the API
# also answers on that Unix socket -- by default in Xymon's runtime
# directory, XYMONRUNDIR or XYMONSERVERLOGS (S22) -- in plain HTTP, whether its port speaks
# HTTPS or not, so that the web server's snippets need not follow the
# certificates. There, as on the port, a password is asked when
# XYMONAPI_PASSWD is set (C3); the socket for this machine's programs keeps
# asking none. The socket's directory is the API's own, 755 whatever the
# umask, and every directory on the way to it -- each step of the path as
# written, and where its links lead -- is root's or the API's user's and
# changed by no one else, unless a group named in
# XYMONAPI_RELAY_TRUSTED_GROUPS: where that does not hold -- a directory
# others write, another's socket listening there, a directory above others
# write, the directory a link, a file at the path, a group not trusted --
# a link leading nowhere --
# there is no relay, the API runs on with its port and other socket, says
# why in its log, and /health says "relay": "refused"; it removes nothing
# it did not make. /health says "listening" or "disabled" otherwise. No
# path redirects to another: a trailing slash is not_found (C2), as a
# redirect would send a client behind a web server back to http://.
#
# Skips where the API cannot run (tests/lib/xymonapi.sh) or openssl is not
# installed; the part with a password skips without Apache's htpasswd.
# Needs the xymon client of the Xymon tree in XYMON_SRC and curl.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../../../tests/lib/xymonapi.sh"

ROOT=$(find_root)

require_bin XYMONCLIENT "$XYMON_SRC/common/xymon"
command -v curl >/dev/null 2>&1 || skip "curl is not installed"
command -v openssl >/dev/null 2>&1 || skip "openssl is not installed"

work=$(mktempdir)
register_cleanup 'stop_process "$API_PID"'

mkdir -p "$work/home/etc/tls"
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=xymon-test" \
	-addext "subjectAltName=IP:127.0.0.1" \
	-keyout "$work/home/etc/tls/xymond.key" -out "$work/home/etc/tls/xymond.pem" > /dev/null 2>&1 \
	|| fail "openssl could not make a certificate"
chmod 600 "$work/home/etc/tls/xymond.key"

export XYMON="$XYMONCLIENT" XYMSRV="127.0.0.1:1"
export XYMONHOME="$work/home" XYMONAPI_TLS_CERT="$work/home/etc/tls/xymond.pem"
export XYMONAPI_SOCKET="$work/api.sock"
relay=$work/relay/relay.sock

code() { curl -s --max-time 5 -o /dev/null -w '%{http_code}' "$@" || true; }
# mode PATH -- its permission bits, as ls shows them.
mode() { ls -ld "$1" | cut -c1-10; }
local_health() { curl -s --max-time 5 --unix-socket "$work/api.sock" http://localhost/xymon/api/v1/health; }

# No relay asked for: disabled.
start_api
assert_contains '"relay":"disabled"' "$(api_get /health)" "with no relay socket asked for, /health says disabled"
stop_process "$API_PID"; API_PID=""

# Asked for nothing, the launcher puts it in Xymon's runtime directory,
# XYMONRUNDIR, or XYMONSERVERLOGS where that is empty, as Xymon does: where
# the installed snippets look for it.
mkdir -p "$work/run" "$work/logs"
XYMONRUNDIR="$work/run" API_RELAY_DEFAULT=1 start_api
[ -S "$work/run/xymonapi/relay.sock" ] || fail "[S22] the relay socket is not in XYMONRUNDIR/xymonapi"
stop_process "$API_PID"; API_PID=""
XYMONRUNDIR="" XYMONSERVERLOGS="$work/logs" API_RELAY_DEFAULT=1 start_api
[ -S "$work/logs/xymonapi/relay.sock" ] || fail "[S22] with XYMONRUNDIR empty, the relay socket is not in XYMONSERVERLOGS/xymonapi"
stop_process "$API_PID"; API_PID=""
assert_equal "" "$(ls -A "$work/run"; ls -A "$work/logs")" "[S22] and the API takes its directory away when it stops"

# The port in HTTPS, the relay socket in HTTP, the other socket as it was.
XYMONAPI_RELAY_SOCKET=$relay start_api
assert_contains '"alive"' "$(api_get /health)" "the port speaks HTTPS with xymond's certificate"
assert_contains '"relay":"listening"' "$(api_get /health)" "and /health says the relay listens"
assert_contains '"alive"' "$(curl -s --max-time 5 --unix-socket "$relay" http://localhost/xymon/api/v1/health)" \
	"the relay socket answers in plain HTTP while the port speaks HTTPS"
assert_contains '"alive"' "$(local_health)" "the socket for this machine's programs answers as before"
assert_equal "srw-rw-rw-" "$(mode "$relay")" "the relay socket is open to connect to"
assert_equal "drwxr-xr-x" "$(mode "$work/relay")" "in a directory no one else writes"

# No redirect: a trailing slash is a path the API does not list.
assert_equal "404" "$(code --unix-socket "$relay" http://localhost/xymon/api/v1/health/)" "[C2] a trailing slash is not_found, not a redirect"
assert_equal "404" "$(code --cacert "$XYMONAPI_TLS_CERT" "https://127.0.0.1:$API_PORT/xymon/api/v1/health/")" "[C2] on the port too"
stop_process "$API_PID"; API_PID=""
[ -e "$work/relay" ] && fail "the API left its relay directory behind when it stopped"

# Where the path is not the API's alone, there is no relay, and the API
# runs on.
# refused LABEL TEXT SOCKET -- with that relay socket the API starts, its
# port and other socket answer, /health says refused, and its log TEXT.
refused() {
	XYMONAPI_RELAY_SOCKET="$3" start_api
	assert_contains '"relay":"refused"' "$(api_get /health)" "$1: /health says the relay is refused"
	assert_contains '"alive"' "$(local_health)" "$1: the other socket answers"
	assert_contains "$2" "$(cat "$work/api.log")" "$1: the log says why"
	stop_process "$API_PID"; API_PID=""
}

# Another's socket already listening, in a directory others may write.
mkdir -p "$work/open"; chmod 777 "$work/open"
python3 -c 'import socket,sys,time; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); s.listen(1); time.sleep(60)' "$work/open/relay.sock" &
squatter=$!
register_cleanup 'stop_process "$squatter"'
for _ in $(seq 50); do [ -S "$work/open/relay.sock" ] && break; sleep 0.1; done
refused "a directory others write, another's socket in it" "that no one else writes" "$work/open/relay.sock"
[ -S "$work/open/relay.sock" ] || fail "the API removed a socket it did not make"
stop_process "$squatter"

# A directory on the way others may write, not sticky; a link there to a
# safe directory changes nothing, as the web server follows the path.
mkdir -p "$work/open2" "$work/safe2"; chmod 777 "$work/open2"; ln -s "$work/safe2" "$work/open2/to"
refused "a directory on the way others write" "only root or this user can change" "$work/open2/relay/relay.sock"
refused "a link in a directory others write, to a safe one" "only root or this user can change" "$work/open2/to/relay/relay.sock"

# The directory a link, and a file at the socket's path.
mkdir -p "$work/real"; ln -s "$work/real" "$work/linked"
refused "the directory a link" "that no one else writes" "$work/linked/relay.sock"
mkdir -p "$work/file"; : > "$work/file/relay.sock"
refused "a file at the socket's path" "not a socket" "$work/file/relay.sock"

# A link on the way that leads nowhere: refused, the API running on, not
# stopped by the error.
ln -s "$work/nowhere" "$work/dangling"
refused "a link on the way that leads nowhere" "nowhere" "$work/dangling/relay/relay.sock"

# A directory its group may write: refused unless that group is trusted.
mkdir -p "$work/grp"; chmod 775 "$work/grp"
refused "a directory its group writes, the group not trusted" "XYMONAPI_RELAY_TRUSTED_GROUPS=$(id -gn) trusts it" "$work/grp/relay/relay.sock"
XYMONAPI_RELAY_TRUSTED_GROUPS="$(id -g)" XYMONAPI_RELAY_SOCKET="$work/grp/relay/relay.sock" start_api
assert_contains '"relay":"listening"' "$(api_get /health)" "a directory a trusted group writes is taken as safe"
stop_process "$API_PID"; API_PID=""

# A link on the way, to a directory only the API's user writes, is
# followed; and under a umask of 077 the modes hold.
mkdir -p "$work/safe"; ln -s "$work/safe" "$work/via"
( umask 077; XYMONAPI_RELAY_SOCKET="$work/via/relay/relay.sock" start_api
  assert_contains '"alive"' "$(curl -s --max-time 5 --unix-socket "$work/safe/relay/relay.sock" http://localhost/xymon/api/v1/health)" \
	"a link on the way, to a safe directory, is followed"
  assert_equal "drwxr-xr-x" "$(mode "$work/safe/relay")" "under umask 077 the directory is 755"
  assert_equal "srw-rw-rw-" "$(mode "$work/safe/relay/relay.sock")" "and the socket 666"
  stop_process "$API_PID" )

# A password asked on the relay socket, as on the port; none on the other.
if command -v htpasswd >/dev/null 2>&1; then
	htpasswd -cb "$work/htpasswd" alice secret 2>/dev/null
	XYMONAPI_PASSWD="$work/htpasswd" XYMONAPI_RELAY_SOCKET=$relay start_api
	assert_equal "401" "$(code --unix-socket "$relay" http://localhost/xymon/api/v1/alarms)" "[C3] the relay socket asks for a user"
	assert_equal "401" "$(code --unix-socket "$relay" http://localhost/xymon/api/v1/health/)" "[C3] before anything else, a path it does not list too"
	assert_equal "200" "$(code --unix-socket "$relay" -u alice:secret http://localhost/xymon/api/v1/health)" "[C3] and answers one with its password"
	assert_equal "404" "$(code --unix-socket "$relay" -u alice:secret http://localhost/xymon/api/v1/health/)" "[C2] which then finds no such path"
	assert_equal "401" "$(code --cacert "$XYMONAPI_TLS_CERT" "https://127.0.0.1:$API_PORT/xymon/api/v1/alarms")" "as the port does"
	assert_equal "200" "$(code --unix-socket "$work/api.sock" http://localhost/xymon/api/v1/health)" "while the other socket asks none"
else
	echo "NOTE: the part with a password was not run: Apache's htpasswd is not installed"
fi

pass "the API answers its web server's relay socket in plain HTTP whether its port speaks HTTPS or not, asks the same password there, keeps its other socket, makes the relay only where no one else can sit at its path -- runs on without it otherwise, saying why in its log and /health -- trusts only the groups it is told to, and redirects no path"
