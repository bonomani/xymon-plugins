#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# plugins/xymonapi/tests/xymonapi-alarm-flags.sh
#
# An alarm keeps the severity its test last measured and says beside it what
# xymond added (RFC #113, version 2), from the board's color and prevgapcolor:
#
# - purple, a test gone silent: the colour it last reported, and stale;
# - clear behind a host's conn that is not green, from xymond or xymonnet:
#   the same, and unreachable, reported by that conn's state; not for a
#   dialup host, nor for the conn itself;
# - clear with nothing measured behind it: indeterminate;
# - blue, disabled: the colour it reported, and the status suppressed.
#
# Purple and xymond's own clear come only from a silence or a dead host,
# which a running xymond takes minutes to declare: the board lines are fed
# to alarms() as xymondboard gives them. xymonapi-board.sh checks blue and
# xymonnet's clear against a running xymond.
#
# Needs the Python the API runs on (XYMONAPI_PYTHON, or python3).

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../../../tests/lib/xymonapi.sh"

ROOT=$(find_root)
py=${XYMONAPI_PYTHON:-python3}
command -v "$py" >/dev/null 2>&1 || skip "no Python to run the API's code with ($py)"

# alarms LINES [all] [HOSTS] -- /alarms for the board lines LINES and
# hostinfo's lines HOSTS (host|dialup|DOWNTIME), those not inactive (or
# all), one per line: host, severity, status, the flags present, then
# [domain]. unreachable reads "unreachable<conn" when reported by the conn
# state of the same host.
alarms() {
	"$py" - "$ROOT/plugins/xymonapi" "$1" "${2:-alarms}" "${3:-}" <<'EOF'
import sys
sys.path.insert(0, sys.argv[1])
import xymon
xymon.query = lambda req: sys.argv[4] if req.startswith("hostinfo") else sys.argv[2]
every = xymon.alarms()
conn = {a["host"]: a["id"] for a in every if a["test"] == "conn"}
for a in (every if sys.argv[3] == "all" else [x for x in every if x["state"] != "inactive"]):
    flags = [k for k in ("stale",) if k in a] + (["unreachable<conn" if a["unreachable"].get("reportedBy") == [conn.get(a["host"])] else "unreachable"] if "unreachable" in a else []) + [f'by:{b["kind"]}' + (f'@{b["until"]}' if "until" in b else "") + (f'/{b["text"]}' if "text" in b else "") for b in a.get("suppressedBy", [])]
    print(a["host"], a["severity"], a["state"], *flags, f'[{a["domain"]}]')
EOF
}

# line HOST COLOR PREVGAPCOLOR [DISABLETIME] -- a board line in
# BOARD_FIELDS' order, no disable unless DISABLETIME is given.
line() { printf '%s|conn|%s|1700000000|0|||%s|%s|%s\n' "$1" "$2" "$3" "${4:-0}" "${5:-}"; }

out=$(alarms "$(line silent purple red; line silentyel purple yellow; line silentgreen purple green; line rawpurple purple none; line down clear red; line nonet clear none; line off blue red 1700007200 maint; line offgreen blue green -1; line dt blue red 0 Maint; line selfblue blue none; line delayed green red; line pinned red green; line red red none; line ok green none)" alarms 'dt||*:*:0000:2359:Maint')

assert_contains 'silent critical firing stale' "$out" "purple over red: the red it measured, critical, and stale"
assert_contains 'silentyel warning firing stale' "$out" "purple over yellow: warning, and stale"
assert_contains 'silentgreen cleared firing stale' "$out" "purple over green: cleared, as it was, and stale"
assert_contains 'down critical firing [' "$out" "a conn made clear over red: critical"
assert_not_contains 'down critical firing unreachable' "$out" "and not unreachable: no conn but itself says so"
assert_contains 'nonet indeterminate firing' "$out" "a clear with nothing behind it: indeterminate"
assert_not_contains 'nonet indeterminate firing unreachable' "$out" "and not unreachable"
assert_contains 'off critical suppressed by:disable@2023-11-15T00:13:20Z/maint' "$out" "blue over red, disabled until a time: critical, suppressed by a disable, its end and text"
assert_contains 'offgreen cleared suppressed by:disable [' "$out" "blue over green, disabled until ok (-1): cleared, suppressed by a disable"
assert_contains 'dt critical suppressed by:downtime/Maint [' "$out" "blue in a DOWNTIME window holding it: its cause, which xymond keeps in dismsg; all day, no end"
assert_contains 'selfblue indeterminate suppressed [' "$out" "a blue the test reported itself: suppressed, and nothing said of why"
assert_not_contains 'rawpurple indeterminate firing stale' "$out" "a purple a client sent itself is a report, not a silence: not stale"
assert_contains 'pinned cleared firing [' "$out" "red shown over green reported, a modifier: the green measured, firing as shown"
assert_contains 'red critical firing' "$out" "red: critical, firing, nothing beside it"
assert_not_contains 'red critical firing stale' "$out" "red is not stale"
assert_not_contains 'ok ' "$out" "green is no alarm"
all=$(alarms "$(line red red none; line ok green none; line delayed green red)" all)
assert_contains 'ok cleared inactive [' "$all" "/alarms gives green too: cleared, inactive"
assert_contains 'delayed critical inactive [' "$all" "green shown over red reported, a change delay: the red measured, critical"
assert_contains 'red critical firing' "$all" "and red, firing"

# A clear behind a conn that is not green -- red, yellow, blue -- whether
# xymond made it (a colour of its own kept) or xymonnet: unreachable,
# reported by that conn's state. A client test with no rule on a host that
# answers, and a dialup host's (hosts.cfg's dialup, from hostinfo), are
# not.
reach=$(alarms "$(printf '%s\n' \
	'far|conn|red|1700000000|0|||none|0' 'far|ssh|clear|1700000000|0|||none|0' \
	'gone|conn|red|1700000000|0|||none|0' 'gone|cpu|clear|1700000000|0|||red|0' \
	'slow|conn|yellow|1700000000|0|||none|0' 'slow|ssh|clear|1700000000|0|||none|0' \
	'maint|conn|blue|1700000000|0|||red|0' 'maint|ssh|clear|1700000000|0|||none|0' \
	'dial|conn|red|1700000000|0|||none|0' 'dial|cpu|clear|1700000000|0|||green|0' \
	'near|conn|green|1700000000|0|||none|0' 'near|procs|clear|1700000000|0|||none|0')" alarms 'dial|dialup|')
assert_contains 'far indeterminate firing unreachable<conn' "$reach" "xymonnet's clear ssh behind a red conn: unreachable, reported by the conn"
assert_contains 'gone critical firing unreachable<conn' "$reach" "xymond's clear over red: critical, as measured, and unreachable"
assert_contains 'slow indeterminate firing unreachable<conn' "$reach" "behind a yellow conn too, as xymond reads it"
assert_contains 'maint indeterminate firing unreachable<conn' "$reach" "and behind a blue one"
assert_not_contains 'dial cleared firing unreachable' "$reach" "a dialup host's clear is not unreachable: nothing failed"
assert_not_contains 'near indeterminate firing unreachable' "$reach" "a clear procs on a host that answers: not unreachable"

# The domain: from the table, or the test itself where it says nothing.
assert_contains 'red critical firing [network]' "$out" "conn lies in the network domain"
mine=$(alarms "$(printf 'web1|ssh|red|1700000000|0|||none\nweb1|mycheck|yellow|1700000000|0|||none\n')")
assert_contains 'web1 critical firing [ssh]' "$mine" "a network service is its own domain"
assert_contains 'web1 warning firing [mycheck]' "$mine" "and so is a script's own test"

# A DOWNTIME's end, as xymond reads the window (check_downtime,
# within_sla): the first minute it no longer holds the test, its end minute
# inside; none for a window that never ends, or does not hold the test.
ends=$(TZ=UTC "$py" - "$ROOT/plugins/xymonapi" <<'EOF'
import calendar, sys, time
sys.path.insert(0, sys.argv[1])
import xymon
at = lambda s: calendar.timegm(time.strptime(s, "%Y-%m-%d %H:%M"))
for spec, test, now in [("*:*:0000:2359:Maint", "conn", "2026-11-20 03:00"),
                        ("conn:*:0200:0400:x", "conn", "2026-11-20 03:00"),
                        ("conn:*:0200:0400:x", "ssh", "2026-11-20 03:00"),
                        ("*:2330:0400", "cpu", "2026-11-16 23:45"),
                        ("W:0800:1700", "cpu", "2026-11-20 16:00"),
                        ("6:0000:2359,0:0000:2359", "cpu", "2026-11-21 10:00"),
                        ("conn,ssh:*:0100:0200:a,*:0300:0330", "ssh", "2026-11-20 01:30")]:
    end = xymon._downtime_until(spec, test, at(now))
    print(spec, test, time.strftime("%Y-%m-%d %H:%M", time.gmtime(end)) if end else "none")
EOF
)
assert_contains '*:*:0000:2359:Maint conn none' "$ends" "a window all day every day never ends"
assert_contains 'conn:*:0200:0400:x conn 2026-11-20 04:01' "$ends" "a window ends the minute after its end"
assert_contains 'conn:*:0200:0400:x ssh none' "$ends" "a window naming other tests holds none of this one"
assert_contains '*:2330:0400 cpu 2026-11-17 04:01' "$ends" "one across midnight ends the next morning"
assert_contains 'W:0800:1700 cpu 2026-11-20 17:01' "$ends" "W is Monday to Friday"
assert_contains '6:0000:2359,0:0000:2359 cpu 2026-11-23 00:00' "$ends" "a weekend, two windows, ends on Monday"
assert_contains 'conn,ssh:*:0100:0200:a,*:0300:0330 ssh 2026-11-20 02:01' "$ends" "a list of tests, then the next window"

pass "an alarm keeps the severity its test last measured, with stale, unreachable or suppressed beside it, and says its domain"
