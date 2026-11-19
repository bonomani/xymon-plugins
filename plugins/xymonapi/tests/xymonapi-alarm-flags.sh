#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# plugins/xymonapi/tests/xymonapi-alarm-flags.sh
#
# An alarm keeps the severity its test last measured and says beside it what
# xymond added (RFC #113, version 2), from the board's color and prevgapcolor:
#
# - purple, a test gone silent: the colour it last reported, and stale;
# - clear chosen by xymond, a host down: the same, and unreachable;
# - clear from xymonnet, with no colour of the test's own behind it, and a
#   test that was green before the gap: indeterminate;
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

# alarms LINES -- /alarms for the board lines LINES, one alarm per line:
# host, severity, status, the flags present, then [domain].
alarms() {
	"$py" - "$ROOT/plugins/xymonapi" "$1" <<'EOF'
import sys
sys.path.insert(0, sys.argv[1])
import xymon
xymon.query = lambda req: sys.argv[2]
for a in xymon.alarms():
    flags = [k for k in ("stale", "unreachable") if k in a] + [f'by:{b["kind"]}' + (f'@{b["until"]}' if "until" in b else "") + (f'/{b["text"]}' if "text" in b else "") for b in a.get("suppressedBy", [])]
    print(a["host"], a["severity"], a["status"], *flags, f'[{a["domain"]}]')
EOF
}

# line HOST COLOR PREVGAPCOLOR [DISABLETIME] -- a board line in
# BOARD_FIELDS' order, no disable unless DISABLETIME is given.
line() { printf '%s|conn|%s|1700000000|0|||%s|%s|%s\n' "$1" "$2" "$3" "${4:-0}" "${5:-}"; }

out=$(alarms "$(line silent purple red; line silentyel purple yellow; line silentgreen purple green; line down clear red; line nonet clear none; line off blue red 1700007200 maint; line offgreen blue green -1; line dt blue red; line red red none; line ok green none)")

assert_contains 'silent major firing stale' "$out" "purple over red: the red it measured, major, and stale"
assert_contains 'silentyel minor firing stale' "$out" "purple over yellow: minor, and stale"
assert_contains 'silentgreen indeterminate firing stale' "$out" "purple over green: nothing bad measured, indeterminate, and stale"
assert_contains 'down major firing unreachable' "$out" "xymond's clear over red, a host down: major, and unreachable"
assert_contains 'nonet indeterminate firing' "$out" "a clear with nothing behind it: indeterminate"
assert_not_contains 'nonet indeterminate firing unreachable' "$out" "and not unreachable: its host's conn is not red"
assert_contains 'off major suppressed by:disable@2023-11-15T00:13:20Z/maint' "$out" "blue over red, disabled until a time: major, suppressed by a disable, its end and text"
assert_contains 'offgreen indeterminate suppressed by:disable [' "$out" "blue over green, disabled until ok (-1): suppressed by a disable"
assert_contains 'dt major suppressed by:downtime' "$out" "blue with no disable set: a DOWNTIME window"
assert_contains 'red major firing' "$out" "red: major, firing, nothing beside it"
assert_not_contains 'red major firing stale' "$out" "red is not stale"
assert_not_contains 'ok ' "$out" "green is no alarm"

# xymonnet's clear for a host it cannot reach: its conn red, its other tests
# clear behind it -- unreachable. A client test with no rule on a host that
# answers: clear, and not unreachable.
reach=$(alarms "$(printf 'far|conn|red|1700000000|0|||none|0\nfar|ssh|clear|1700000000|0|||none|0\nnear|conn|green|1700000000|0|||none|0\nnear|procs|clear|1700000000|0|||none|0\n')")
assert_contains 'far indeterminate firing unreachable' "$reach" "a clear ssh on a host whose conn is red: unreachable"
assert_not_contains 'near indeterminate firing unreachable' "$reach" "a clear procs on a host that answers: not unreachable"

# The domain: from the table, or the test itself where it says nothing.
assert_contains 'red major firing [network]' "$out" "conn lies in the network domain"
mine=$(alarms "$(printf 'web1|ssh|red|1700000000|0|||none\nweb1|mycheck|yellow|1700000000|0|||none\n')")
assert_contains 'web1 major firing [ssh]' "$mine" "a network service is its own domain"
assert_contains 'web1 minor firing [mycheck]' "$mine" "and so is a script's own test"

pass "an alarm keeps the severity its test last measured, with stale, unreachable or suppressed beside it, and says its domain"
