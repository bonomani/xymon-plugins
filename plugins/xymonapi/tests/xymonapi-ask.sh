#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# plugins/xymonapi/tests/xymonapi-ask.sh
#
# POST /ask is not there unless XYMONAPI_ASK is set; set, it gives the
# question to xymonapi-agent beside the API, with the API's environment --
# the socket included -- and answers the agent's answer, agent and backend;
# the agent's failure is upstream with its last line. A session is the
# caller's: prefixed with user@client from a token, user@password from a
# password, before the agent sees it, and given back as sent. One question
# at a time per caller, and XYMONAPI_ASK_PER_HOUR an hour, else too_many
# with Retry-After; a question too long, or none, is bad_request; GET is
# method_not_allowed.
#
# claude is a stub that records its arguments and answers; the real
# xymonapi-agent and xymonapi-mcp of the checkout are what the API runs.
# Skips where the API cannot run (tests/lib/xymonapi.sh). Needs the xymon
# client of the Xymon tree in XYMON_SRC (for a free port), Apache's
# htpasswd and curl.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../../../tests/lib/xymonapi.sh"

ROOT=$(find_root)

require_bin XYMONCLIENT "$XYMON_SRC/common/xymon"
command -v curl >/dev/null 2>&1 || skip "curl is not installed"
command -v htpasswd >/dev/null 2>&1 || skip "Apache's htpasswd is not installed"

work=$(mktempdir)
register_cleanup 'stop_process "$API_PID"'

mkdir -p "$work/stub" "$work/state"
cat > "$work/stub/claude" <<STUB
#!/bin/sh
printf '%s\n' "\$@" > "$work/claude.args"
case "\$2" in
	*fail*) echo "claude: not logged in" >&2; exit 2 ;;
	*slow*) sleep 3 ;;
esac
printf '{"result":"xymon 4.3.31","permission_denials":[]}\n'
STUB
chmod 755 "$work/stub/claude"
htpasswd -cbB "$work/htpasswd" alice secret 2>/dev/null

export XYMON="$XYMONCLIENT" XYMSRV="127.0.0.1:1" XYMONAPI_PASSWD="$work/htpasswd" \
	XYMONAPI_TOKENS="$work/var/tokens" XYMONAPI_SOCKET="$work/api.sock" \
	XYMONAPI_AGENT_BACKEND=claude XDG_STATE_HOME="$work/state" PATH="$work/stub:$PATH"

post() { # post WHO JSON -- status then body
	local who=$1 json=$2
	case $who in
		xat_*) curl -s --max-time 30 -H "Authorization: Bearer $who" -w '\n%{http_code}' -H 'Content-Type: application/json' -d "$json" "$api/ask" ;;
		*)     curl -s --max-time 30 -u "$who" -w '\n%{http_code}' -H 'Content-Type: application/json' -d "$json" "$api/ask" ;;
	esac
}
status() { printf '%s\n' "$1" | tail -n 1; }
body() { printf '%s\n' "$1" | sed '$d'; }

# Off: not there.
start_api
api=http://127.0.0.1:$API_PORT/xymon/api/v1
out=$(post alice:secret '{"question":"anything red?"}')
assert_equal "404" "$(status "$out")" "[C6] without XYMONAPI_ASK, /ask answers not_found"
assert_contains '"error":"not_found"' "$(body "$out")" "[C1] in the error's form"
stop_process "$API_PID"; API_PID=""

# On.
export XYMONAPI_ASK=1 XYMONAPI_ASK_PER_HOUR=4 XYMONAPI_ASK_MAX=60
start_api
api=http://127.0.0.1:$API_PORT/xymon/api/v1
assert_contains "/ask is on" "$(cat "$work/api.log")" "the log says /ask is on, and where the agent is"

out=$(post alice:secret '{"question":"anything red?"}')
assert_equal "200" "$(status "$out")" "[C6] with XYMONAPI_ASK, /ask answers"
assert_contains '"answer":"xymon 4.3.31"' "$(body "$out")" "[C6] with the agent's answer"
assert_contains '"agent":"xymon"' "$(body "$out")" "[C6] which agent"
assert_contains '"backend":"claude"' "$(body "$out")" "[C6] and which backend"
grep -q '"session"' <<<"$(body "$out")" && fail "a session is given back when none was sent"
args=$(cat "$work/claude.args")
assert_contains "--strict-mcp-config" "$args" "the real xymonapi-agent ran the backend, restricted"
assert_contains "xymonapi-mcp/xymonapi-mcp.sh" "$args" "with the MCP server beside the API"
assert_contains "\"XYMONAPI_SOCKET\": \"$work/api.sock\"" "$args" "[C6] which reaches the API through its own socket, from the API's environment"
assert_contains "--no-session-persistence" "$args" "and no session when none was asked"

# Failure: upstream, the agent's last line.
out=$(post alice:secret '{"question":"please fail"}')
assert_equal "502" "$(status "$out")" "[C6] the agent failing is upstream"
assert_contains "not logged in" "$(body "$out")" "[C6] with its last line as the detail"

# Sessions are the caller's.
tok=$(curl -s -u alice:secret -X POST -H 'Content-Type: application/json' -d '{"client":"laptop"}' "$api/tokens" \
	| sed -n 's/.*"token": *"\(xat_[A-Za-z0-9_-]*\)".*/\1/p')
[ -n "$tok" ] || fail "no token for alice"
out=$(post "$tok" '{"question":"what changed?","session":"nightly"}')
assert_equal "200" "$(status "$out")" "a question with a session answers"
assert_contains '"session":"nightly"' "$(body "$out")" "[C7] and gives the name back as sent"
[ -e "$work/state/xymonapi-agent/xymon/claude/alice@laptop:nightly" ] \
	|| fail "[C7] the agent did not see the session as alice@laptop:nightly, from the token: $(ls "$work/state/xymonapi-agent/xymon/claude" 2>/dev/null)"
assert_contains "--session-id" "$(cat "$work/claude.args")" "and started it"
# per-hour so far: alice@password 2 (one failed, still counted), alice@laptop 1

# Limits: one at a time, and per hour.
post "$tok" '{"question":"be slow"}' > "$work/slow.out" &
slow=$!
sleep 1
out=$(post "$tok" '{"question":"meanwhile?"}')
assert_equal "429" "$(status "$out")" "[C8] a second question while one is answered is too_many"
assert_contains "one at a time" "$(body "$out")" "[C8] and says so"
wait "$slow"
assert_equal "200" "$(status "$(cat "$work/slow.out")")" "the slow one answered"
# alice@laptop has asked nightly and slow; the one refused while slow ran is
# not counted. Two more are allowed, the fifth is not.
out=$(post "$tok" '{"question":"three"}')
assert_equal "200" "$(status "$out")" "the third question of the hour answers"
out=$(post "$tok" '{"question":"four"}')
assert_equal "200" "$(status "$out")" "[C8] and the fourth, the last XYMONAPI_ASK_PER_HOUR allows"
out=$(curl -s --max-time 30 -H "Authorization: Bearer $tok" -D "$work/h" -H 'Content-Type: application/json' -d '{"question":"five"}' "$api/ask")
assert_contains '"error":"too_many"' "$out" "[C8] the fifth, past XYMONAPI_ASK_PER_HOUR, is too_many"
assert_contains "this hour" "$out" "[C8] and says why"
grep -qi '^retry-after: [0-9]' "$work/h" || fail "[C8] too_many carries no Retry-After: $(cat "$work/h")"
grep -qi '^HTTP/1.1 429' "$work/h" || fail "[C1] too_many is not 429: $(head -n 1 "$work/h")"
# alice by password is another caller, still within the hour's count
out=$(post alice:secret '{"question":"as password","session":"nightly"}')
assert_equal "200" "$(status "$out")" "[C8] the limits are per caller: alice by password still answers"
[ -e "$work/state/xymonapi-agent/xymon/claude/alice@password:nightly" ] \
	|| fail "[C7] her session by password is not another than by token: $(ls "$work/state/xymonapi-agent/xymon/claude")"

# Bad requests, and the method.
out=$(post alice:secret '{"session":"x"}')
assert_equal "400" "$(status "$out")" "no question is bad_request"
out=$(post alice:secret "{\"question\":\"$(printf 'x%.0s' $(seq 1 61))\"}")
assert_equal "400" "$(status "$out")" "[C8] a question longer than XYMONAPI_ASK_MAX is bad_request"
assert_contains "XYMONAPI_ASK_MAX" "$(body "$out")" "and names the setting"
out=$(post alice:secret '{"question":"q","session":"a b"}')
assert_equal "400" "$(status "$out")" "a session name with a space is bad_request"
out=$(post alice:secret 'not json')
assert_equal "400" "$(status "$out")" "a body that is not JSON is bad_request"
code=$(curl -s -o /dev/null -w '%{http_code}' -u alice:secret "$api/ask")
assert_equal "405" "$code" "[C2] GET /ask is method_not_allowed"
code=$(curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d '{"question":"q"}' "$api/ask")
assert_equal "401" "$code" "[C3] /ask needs a user or token like every path"

pass "/ask is off until XYMONAPI_ASK, then runs xymonapi-agent beside the API with the API's environment, keeps sessions per caller, and limits callers to one question at a time and XYMONAPI_ASK_PER_HOUR an hour"
