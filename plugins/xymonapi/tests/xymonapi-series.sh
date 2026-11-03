#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# plugins/xymonapi/tests/xymonapi-series.sh
#
# /series reads one dataset of HOST/TEST.rrd under XYMONRRDS and returns its
# values over the time range asked for, and the API refuses a host, test or
# metric name that could leave that directory or reach rrdtool as syntax:
# "../" in a host, ":" in a test. A time it cannot read is refused too, and an
# RRD file that does not exist is a 404. /graphs refuses the same names.
# A range reaching into xymond_rrd's 30 minutes of cached updates first asks
# it to write that host's -- /HOST/ to its control socket, as showgraph
# does -- an older range does not; a left-over rrdctl file, or no XYMONTMP,
# leaves /series answering as before.
#
# The RRD is made here, with three known values at fixed times, so the answer
# is known in advance. Skips where the API cannot run (tests/lib/xymonapi.sh).
# Needs the xymon client of the Xymon tree in XYMON_SRC (for a free port),
# rrdtool and curl.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../../../tests/lib/xymonapi.sh"

ROOT=$(find_root)

require_bin XYMONCLIENT "$XYMON_SRC/common/xymon"
command -v curl >/dev/null 2>&1 || skip "curl is not installed"
command -v rrdtool >/dev/null 2>&1 || skip "rrdtool is not installed"

work=$(mktempdir)
register_cleanup 'stop_process "$API_PID"'
register_cleanup 'stop_process "$RRDCTL_PID"'

# Three five-minute steps, from a time that is a multiple of the step, so
# each update lands on a step of its own and is stored as given.
t0=1699999800
mkdir -p "$work/rrd/host.example.com"
rrd="$work/rrd/host.example.com/la.rrd"
rrdtool create "$rrd" --start "$t0" --step 300 DS:la:GAUGE:600:U:U RRA:AVERAGE:0.5:1:100
rrdtool update "$rrd" "$((t0 + 300)):1" "$((t0 + 600)):2" "$((t0 + 900)):3"

# xymond_rrd's control socket, a stand-in recording what it is sent, and
# beside it a left-over rrdctl file, of a process long gone.
mkdir -p "$work/tmp"
"${XYMONAPI_PYTHON:-python3}" "$ROOT/tests/lib/fake-rrdctl.py" "$work/tmp/rrdctl.1" "$work/rrdctl.req" &
RRDCTL_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -e "$work/rrdctl.req" ] && break; sleep 0.2; done
[ -e "$work/rrdctl.req" ] || fail "the stand-in control socket did not start"
: > "$work/tmp/rrdctl.999"

# /series needs no xymond, but the launcher refuses to start without XYMSRV.
export XYMON="$XYMONCLIENT" XYMSRV="127.0.0.1:1" XYMONRRDS="$work/rrd" XYMONTMP="$work/tmp"
start_api

body=$(api_get "/series?entity=host.example.com&test=la&metric=la&from=$t0&to=$((t0 + 900))")
for v in 1.0 2.0 3.0; do
	assert_contains "\"v\":$v" "$body" "/series returns the value $v stored in the RRD"
done
assert_contains '"metric":"la"' "$body" "/series names the dataset it read"
assert_equal "" "$(cat "$work/rrdctl.req")" "a range long past asks xymond_rrd for nothing"

# A range up to now: xymond_rrd is asked to write the host's cached updates
# first; the left-over file beside its socket does not get in the way.
body=$(api_get "/series?entity=host.example.com&test=la&metric=la&from=-1h")
assert_contains '"metric":"la"' "$body" "/series up to now answers"
assert_contains "/host.example.com/" "$(cat "$work/rrdctl.req")" "and first asks xymond_rrd to write that host's cached updates"

# An HTTP test's file is named after its URL, colon and all; rrdtool reads
# the colon as its separator unless it is escaped.
http="$work/rrd/host.example.com/tcp.http.host.example.com:8080,.rrd"
rrdtool create "$http" --start "$t0" --step 300 DS:sec:GAUGE:600:U:U RRA:AVERAGE:0.5:1:100
rrdtool update "$http" "$((t0 + 300)):0.5"
body=$(api_get "/series?entity=host.example.com&test=tcp.http.host.example.com:8080,&metric=sec&from=$t0&to=$((t0 + 300))")
assert_contains '"v":0.5' "$body" "/series reads an HTTP test's RRD, whose name holds a colon"

assert_equal "400" "$(api_code '/series?entity=../host.example.com&test=la&metric=la')" "a host name with ../"
assert_equal "400" "$(api_code '/series?entity=host:example.com&test=la&metric=la')" "a host name with a colon"
assert_equal "400" "$(api_code '/series?entity=host.example.com&test=la&metric=l:a')" "a metric name with a colon"
assert_equal "400" "$(api_code '/series?entity=host.example.com&test=la&metric=la&from=yesterday')" "a time that is not now, a number or like -24h"
assert_equal "404" "$(api_code '/series?entity=host.example.com&test=disk&metric=la')" "an RRD file that does not exist"
assert_equal "404" "$(api_code '/series?entity=host.example.com&test=la&metric=nope')" "a dataset the RRD file does not hold"
assert_contains 'no dataset nope' "$(api_get '/series?entity=host.example.com&test=la&metric=nope')" "and the answer names it"
assert_equal "400" "$(api_code "/series?entity=host.example.com&test=la&metric=la&from=$((t0 + 900))&to=$t0")" "from after to"
# Numbers no clock can mean: thousands of digits, which int() itself refuses
# on Python 3.11+, and a relative time of a billion weeks.
long=$(printf '1%.0s' $(seq 1 5000))
assert_equal "400" "$(api_code "/series?entity=host.example.com&test=la&metric=la&from=$long")" "a time of 5000 digits"
assert_equal "400" "$(api_code '/series?entity=host.example.com&test=la&metric=la&from=-1000000000w')" "a relative time of ten digits"

# /graphs checks the same names before it asks showgraph, so this needs no
# web server. What showgraph then draws is xymonapi-graphs.sh's business.
assert_equal "400" "$(api_code '/graphs?entity=../host.example.com&test=la')" "/graphs, a host name with ../"

# rrdtool missing is the server's problem, a 502, not a 404 as if the RRD
# file were not there -- subprocess raises FileNotFoundError for both. The
# answer does not say what went wrong; the log does.
stop_process "$API_PID"; API_PID=""
# A PATH with everything the launcher and this test use, and no rrdtool.
mkdir -p "$work/nobin"
for t in sh bash dirname sed cat tail head grep curl date sleep od tr python3; do
	p=$(command -v "$t") && ln -s "$p" "$work/nobin/$t"
done
PATH="$work/nobin" start_api
assert_equal "502" "$(api_code '/series?entity=host.example.com&test=la&metric=la')" "/series with no rrdtool on PATH"
assert_contains 'xymonapi.log' "$(api_get '/series?entity=host.example.com&test=la&metric=la')" "and the answer points at the log"
assert_not_contains "$work" "$(api_get '/series?entity=host.example.com&test=la&metric=la')" "and holds no path of the server's"
assert_contains 'rrdtool' "$(cat "$work/api.log")" "which says what was missing"

# No XYMONTMP: nothing to ask, and /series answers as before.
stop_process "$API_PID"; API_PID=""
unset XYMONTMP
start_api
assert_contains '"metric":"la"' "$(api_get "/series?entity=host.example.com&test=la&metric=la&from=-1h")" "without XYMONTMP, /series up to now answers"
pass "/series reads the RRD values asked for, first asking xymond_rrd to write the host's cached updates when the range reaches them, answers 404 for a missing file or dataset, 400 for bad times, and refuses names that leave XYMONRRDS"
