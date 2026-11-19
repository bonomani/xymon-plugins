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

# alarms LINES [states] -- /alarms (or /states) for the board lines LINES,
# one state per line: host, severity, status, the flags present, then
# [domain]. unreachable reads "unreachable<conn" when reported by the conn
# state of the same host.
alarms() {
	"$py" - "$ROOT/plugins/xymonapi" "$1" "${2:-alarms}" <<'EOF'
import sys
sys.path.insert(0, sys.argv[1])
import xymon
xymon.query = lambda req: sys.argv[2]
every = xymon.states()
conn = {a["host"]: a["id"] for a in every if a["test"] == "conn"}
for a in (every if sys.argv[3] == "states" else xymon.alarms()):
    flags = [k for k in ("stale",) if k in a] + (["unreachable<conn" if a["unreachable"].get("reportedBy") == [conn.get(a["host"])] else "unreachable"] if "unreachable" in a else []) + [f'by:{b["kind"]}' + (f'@{b["until"]}' if "until" in b else "") + (f'/{b["text"]}' if "text" in b else "") for b in a.get("suppressedBy", [])]
    print(a["host"], a["severity"], a["status"], *flags, f'[{a["domain"]}]')
EOF
}

# line HOST COLOR PREVGAPCOLOR [DISABLETIME] -- a board line in
# BOARD_FIELDS' order, no disable unless DISABLETIME is given.
line() { printf '%s|conn|%s|1700000000|0|||%s|%s|%s\n' "$1" "$2" "$3" "${4:-0}" "${5:-}"; }

out=$(alarms "$(line silent purple red; line silentyel purple yellow; line silentgreen purple green; line down clear red; line nonet clear none; line off blue red 1700007200 maint; line offgreen blue green -1; line dt blue red; line red red none; line ok green none)")

assert_contains 'silent critical firing stale' "$out" "purple over red: the red it measured, critical, and stale"
assert_contains 'silentyel warning firing stale' "$out" "purple over yellow: warning, and stale"
assert_contains 'silentgreen cleared firing stale' "$out" "purple over green: cleared, as it was, and stale"
assert_contains 'down critical firing [' "$out" "a conn made clear over red: critical"
assert_not_contains 'down critical firing unreachable' "$out" "and not unreachable: no conn but itself says so"
assert_contains 'nonet indeterminate firing' "$out" "a clear with nothing behind it: indeterminate"
assert_not_contains 'nonet indeterminate firing unreachable' "$out" "and not unreachable"
assert_contains 'off critical suppressed by:disable@2023-11-15T00:13:20Z/maint' "$out" "blue over red, disabled until a time: critical, suppressed by a disable, its end and text"
assert_contains 'offgreen cleared suppressed by:disable [' "$out" "blue over green, disabled until ok (-1): cleared, suppressed by a disable"
assert_contains 'dt critical suppressed by:downtime' "$out" "blue with no disable set: a DOWNTIME window"
assert_contains 'red critical firing' "$out" "red: critical, firing, nothing beside it"
assert_not_contains 'red critical firing stale' "$out" "red is not stale"
assert_not_contains 'ok ' "$out" "green is no alarm"
all=$(alarms "$(line red red none; line ok green none)" states)
assert_contains 'ok cleared inactive [' "$all" "/states gives green too: cleared, inactive"
assert_contains 'red critical firing' "$all" "and red as /alarms does"

# A clear behind a conn that is not green -- red, yellow, blue -- whether
# xymond made it (a colour of its own kept) or xymonnet: unreachable,
# reported by that conn's state. A client test with no rule on a host that
# answers, and a dialup host's (hosts.cfg's dialup, XMH_FLAG_DIALUP), are
# not. Fields: host|test|color|lastchange|acktime|ackmsg|acklist|
# prevgapcolor|disabletime|dismsg|logtime|sender|XMH_FLAG_DIALUP|line1.
reach=$(alarms "$(printf '%s\n' \
	'far|conn|red|1700000000|0|||none|0' 'far|ssh|clear|1700000000|0|||none|0' \
	'gone|conn|red|1700000000|0|||none|0' 'gone|cpu|clear|1700000000|0|||red|0' \
	'slow|conn|yellow|1700000000|0|||none|0' 'slow|ssh|clear|1700000000|0|||none|0' \
	'maint|conn|blue|1700000000|0|||red|0' 'maint|ssh|clear|1700000000|0|||none|0' \
	'dial|conn|red|1700000000|0|||none|0' 'dial|cpu|clear|1700000000|0|||green|0||||dialup' \
	'near|conn|green|1700000000|0|||none|0' 'near|procs|clear|1700000000|0|||none|0')")
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

pass "a state keeps the severity its test last measured, with stale, unreachable or suppressed beside it, and says its domain"
