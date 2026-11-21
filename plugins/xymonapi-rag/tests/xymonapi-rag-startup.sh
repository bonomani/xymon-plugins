#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# plugins/xymonapi-rag/tests/xymonapi-rag-startup.sh
#
# Off the Xymon server -- no XYMONHISTDIR, so the history comes through the
# API -- xymonapi-rag index can start before the API listens, as when both
# are started by the same boot. An API that gives no answer at all is tried
# again for about a minute, so the index is built once it is up. An API that
# answers -- here a 401, for a password it was not given -- is not retried:
# that failure is reported at once. (On the server, index reads xymond's
# files and does not need the API at all: xymonapi-rag.sh covers that.)
#
# The pages are one page of one passage, written here, so the embedding is
# quick -- what is shown is the waiting, not the pages; the history is
# written here in xymond_history's format. Skips where the API or the search cannot run; the 401 part also
# needs Apache's htpasswd. Needs curl.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../../../tests/lib/xymonapi.sh"

ROOT=$(find_root)

require_bin XYMONCLIENT "$XYMON_SRC/common/xymon"
command -v curl >/dev/null 2>&1 || skip "curl is not installed"

work=$(mktempdir)
register_cleanup 'stop_process "$API_PID"'
RAG_PID=""
register_cleanup 'stop_process "$RAG_PID"'

mkdir -p "$work/docs" "$work/hist" "$work/histlogs/web_example_com/http"
printf '%s\n' '.TH HOSTS.CFG 5 "Version 4.3.31" "Xymon"' '.SH NAME' 'hosts.cfg \- the main Xymon configuration file' \
	> "$work/docs/hosts.cfg.5"
printf 'web.example.com http 1699400000 1699300000 100000 re gr 0\n' > "$work/hist/allevents"
printf 'red Tue Nov  7 23:33:20 2023 HTTP 500 from https://web.example.com/login\n' \
	> "$work/histlogs/web_example_com/http/Tue_Nov_7_23:33:20_2023"

# The history's place is the API's to know, not the indexer's: with
# XYMONHISTDIR in its environment, index would read the files and never
# wait for the API.
export TZ=UTC XYMON="$XYMONCLIENT" XYMSRV="127.0.0.1:1"
HIST="XYMONHISTDIR=$work/hist XYMONHISTLOGS=$work/histlogs"
unset XYMONAPI_RAG_MODEL XYMONHISTDIR XYMONHISTLOGS
export XYMONAPI_RAG_DOCS="$work/docs" XYMONAPI_RAG_INDEX="$work/index.npz" \
	XYMONAPI_RAG_SINCE=1699000000

# The search's own requirements first, with the API not yet started, so a
# missing module skips here rather than fails below.
rc=0
"$ROOT/plugins/xymonapi-rag/xymonapi-rag.sh" search 'anything' > /dev/null 2> "$work/rag.err" || rc=$?
[ "$rc" -eq 77 ] && skip "$(cat "$work/rag.err")"

# 0. The waiting itself, on a stand-in client and clock, so it is shown
#    whatever the runner's speed: an API up at second 13 is read soon
#    after, one never up is given up on after about a minute, a 401 at once.
"${XYMONAPI_PYTHON:-python3}" - "$ROOT/plugins/xymonapi-rag" > "$work/retry.out" 2>&1 <<'PY' \
	|| fail "index's waiting for the API: $(tail -n 3 "$work/retry.out")"
import sys
sys.path.insert(0, sys.argv[1])
import xymonrag

class APIError(Exception):
    def __init__(self, status):
        self.status = status

class Clock:
    now = 0.0
    def monotonic(self): return self.now
    def sleep(self, s): self.now += s

def client(fail_until=None, status=None):
    c = type("C", (), {})()
    c.APIError, c.calls = APIError, []
    def api(path, **kw):
        c.calls.append(clock.now)
        if status is not None:
            raise APIError(status)
        if fail_until is None or clock.now < fail_until:
            raise APIError(None)
        return {"items": ["ok"]}
    c.api = api
    return c

clock = Clock(); xymonrag.time = clock
c = client(fail_until=13)
assert xymonrag._events_when_up(c, "0", None) == ["ok"], "an API up at second 13 is read"
assert c.calls[-1] <= 15, f"and soon after it is up: at {c.calls[-1]}"
clock.now = 0.0; c = client()
try:
    xymonrag._events_when_up(c, "0", None); raise SystemExit("an API never up was not given up on")
except APIError: pass
assert 55 <= c.calls[-1] <= 60, f"tried for about a minute, last at {c.calls[-1]}"
clock.now = 0.0; c = client(status=401)
try:
    xymonrag._events_when_up(c, "0", None); raise SystemExit("a 401 was not raised")
except APIError: pass
assert len(c.calls) == 1, f"a 401 is not retried: {len(c.calls)} calls"
print("ok")
PY

# 1. Nothing listens on the API's port when index starts; the API comes up
#    some seconds later, as at boot. index must wait and then succeed. (On
#    a slow runner its first try may come after the API is up: 0. shows the
#    waiting either way.)
API_PORT=$(free_port) || fail "no free port for the API"
export XYMONAPI_URL="http://127.0.0.1:$API_PORT"
"$ROOT/plugins/xymonapi-rag/xymonapi-rag.sh" index > "$work/index.out" 2> "$work/rag.err" &
RAG_PID=$!
sleep 5
if ! kill -0 "$RAG_PID" 2>/dev/null; then
	# 77, a module index needs and this machine lacks: said at once, as below.
	rc=0; wait "$RAG_PID" || rc=$?; RAG_PID=""
	[ "$rc" -eq 77 ] && skip "$(cat "$work/rag.err")"
	fail "index gave up within 5 seconds of an API that was not up yet: $(tail -n 3 "$work/rag.err")"
fi
env $HIST XYMONAPI_LISTEN="127.0.0.1:$API_PORT" "$ROOT/plugins/xymonapi/xymonapi.sh" > "$work/api.log" 2>&1 &
API_PID=$!
deadline=$(( $(date +%s) + 60 ))
until curl -s --max-time 5 -o /dev/null "$XYMONAPI_URL/xymon/api/v1/health"; do
	kill -0 "$API_PID" 2>/dev/null || { rc=0; wait "$API_PID" || rc=$?; API_PID=""
		[ "$rc" -eq 77 ] && skip "$(cat "$work/api.log")"
		fail "the API exited with $rc: $(tail -n 5 "$work/api.log")"; }
	[ "$(date +%s)" -lt "$deadline" ] || fail "the API did not answer within 60 seconds"
	sleep 0.2
done
rc=0
wait "$RAG_PID" || rc=$?
RAG_PID=""
# 77, a module index needs and this machine lacks -- fastembed, which some
# platforms package nowhere. The check above runs search, which with no index
# here asks the API and needs none of them, so it cannot catch it.
[ "$rc" -eq 77 ] && skip "$(cat "$work/rag.err")"
[ "$rc" -eq 0 ] || fail "index exited with $rc once the API was up: $(tail -n 5 "$work/rag.err")"
assert_contains "indexed" "$(cat "$work/index.out")" "index built the index after waiting for the API"
assert_contains 'web.example.com http' \
	"$("$ROOT/plugins/xymonapi-rag/xymonapi-rag.sh" search -k 1 --kind history 'HTTP 500 on the login page' 2>/dev/null)" \
	"and the history read through the late API is in it"

# 2. An API that answers, with a 401, is not waited for.
command -v htpasswd >/dev/null 2>&1 || { pass_partial "index waits for an API that is not up yet (the 401 part needs htpasswd)"; }
htpasswd -cbB "$work/passwd" alice secret > /dev/null 2>&1 || fail "htpasswd could not write $work/passwd"
stop_process "$API_PID"; API_PID=""
XYMONHISTDIR="$work/hist" XYMONHISTLOGS="$work/histlogs" XYMONAPI_PASSWD="$work/passwd" start_api
export XYMONAPI_URL="http://127.0.0.1:$API_PORT"
unset XYMONAPI_TOKEN XYMONAPI_TOKEN_FILE
began=$(date +%s)
rc=0
XYMONAPI_RAG_INDEX="$work/index2.npz" "$ROOT/plugins/xymonapi-rag/xymonapi-rag.sh" index > /dev/null 2> "$work/rag.err" || rc=$?
took=$(( $(date +%s) - began ))
[ "$rc" -ne 0 ] || fail "index succeeded against an API that answered 401"
assert_contains 'answered 401' "$(cat "$work/rag.err")" "a 401 is reported"
[ "$took" -lt 10 ] || fail "and should be reported at once, not after $took seconds of retries"
[ -e "$work/index2.npz" ] && fail "a failed indexing left an index behind"

pass "xymonapi-rag index waits for an API that is not up yet, as at boot, and does not wait for one that refuses it"
