#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/xymonapi-manifest-watch.sh
#
# The API takes up an update by itself (S7): installed, it watches its
# MANIFEST, an install's last step (S29), and once that is rewritten it
# stops as on SIGTERM, ending with 0, its socket taken away, for
# xymonlaunch to start the new code. MANIFEST gone, as during an update,
# it goes on; started while it was gone, it stops once it is there. No process is looked for: the test waits for its own child.
#
# Skips where the API cannot run (tests/lib/xymonapi.sh). Needs the xymon
# client of the Xymon tree in XYMON_SRC (for a free port) and curl.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)

require_bin XYMONCLIENT "$XYMON_SRC/common/xymon"
command -v curl >/dev/null 2>&1 || skip "curl is not installed"

work=$(mktempdir)
server_tree "$work/inst"
# shellcheck disable=SC2016 # API_PID is read at cleanup
register_cleanup 'stop_process "$API_PID"'
"$ROOT/xymon-plugin" install --server xymonapi XYMONHOME="$work/inst" MANDIR="$work/man" >"$work/install.log" 2>&1 \
	|| fail "xymon-plugin install --server failed: $(tail -n 5 "$work/install.log")"
ext=$work/inst/ext/xymonapi
assert_file_exists "$ext/MANIFEST"
API_ROOT=$ext
export XYMON="$XYMONCLIENT" XYMSRV="127.0.0.1:1" \
	XYMONAPI_SOCKET="$work/run/api.sock"
start_api
[ -S "$work/run/api.sock" ] || fail "the API made no socket at $work/run/api.sock"

# Unchanged, past a few polls: the API goes on.
sleep 7
kill -0 "$API_PID" 2>/dev/null || fail "[S7] the API stopped with its MANIFEST unchanged: $(tail -n 3 "$work/api.log")"

# Gone, as fresh leaves it during an update: the API goes on.
mv "$ext/MANIFEST" "$work/MANIFEST"
sleep 7
kill -0 "$API_PID" 2>/dev/null || fail "[S7] the API stopped while MANIFEST was gone: $(tail -n 3 "$work/api.log")"

# Written again, a new file, as an install's last step: it stops.
cp "$work/MANIFEST" "$ext/MANIFEST"
deadline=$(( $(date +%s) + 20 ))
while kill -0 "$API_PID" 2>/dev/null && [ "$(date +%s)" -lt "$deadline" ]; do sleep 0.5; done
kill -0 "$API_PID" 2>/dev/null && fail "[S7] the API still runs 20 seconds after its MANIFEST changed"
rc=0; wait "$API_PID" || rc=$?
API_PID=""
assert_equal 0 "$rc" "[S7] the API stops with 0, so that xymonlaunch counts no failure"
assert_contains "MANIFEST changed, an update" "$(cat "$work/api.log")" "[S7] and says why"
[ -e "$work/run/api.sock" ] && fail "[S7] the API left its socket behind"

# Started while MANIFEST is gone, as xymonlaunch may during an update: it
# goes on, and stops once MANIFEST is there.
mv "$ext/MANIFEST" "$work/MANIFEST"
start_api
sleep 7
kill -0 "$API_PID" 2>/dev/null || fail "[S7] the API started without MANIFEST stopped: $(tail -n 3 "$work/api.log")"
cp "$work/MANIFEST" "$ext/MANIFEST"
deadline=$(( $(date +%s) + 20 ))
while kill -0 "$API_PID" 2>/dev/null && [ "$(date +%s)" -lt "$deadline" ]; do sleep 0.5; done
kill -0 "$API_PID" 2>/dev/null && fail "[S7] the API started during an update still runs 20 seconds after MANIFEST came"
rc=0; wait "$API_PID" || rc=$?
API_PID=""
assert_equal 0 "$rc" "[S7] and stops with 0"

# xymonapi-rag's MANIFEST, whose code /search imports: one that comes --
# xymonapi-rag installed beside it -- stops the API too.
start_api
sleep 7
kill -0 "$API_PID" 2>/dev/null || fail "[S7] the API stopped with nothing changed: $(tail -n 3 "$work/api.log")"
mkdir -p "$work/inst/ext/xymonapi-rag"
printf 'file\t1 1\txymonrag.py\n' > "$work/inst/ext/xymonapi-rag/MANIFEST"
deadline=$(( $(date +%s) + 20 ))
while kill -0 "$API_PID" 2>/dev/null && [ "$(date +%s)" -lt "$deadline" ]; do sleep 0.5; done
kill -0 "$API_PID" 2>/dev/null && fail "[S7] the API still runs 20 seconds after xymonapi-rag's MANIFEST came"
rc=0; wait "$API_PID" || rc=$?
API_PID=""
assert_equal 0 "$rc" "[S7] and stops with 0"
assert_contains "xymonapi-rag/MANIFEST changed, an update" "$(cat "$work/api.log")" "[S7] saying which"

pass "the API installed stops by itself, with 0 and its socket taken away, once its MANIFEST is written again, and not while it is gone; started while it is gone, once it comes; and once xymonapi-rag's comes"
