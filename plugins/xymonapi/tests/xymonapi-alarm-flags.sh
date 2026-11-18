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
# host, severity, status, then the flags present.
alarms() {
	"$py" - "$ROOT/plugins/xymonapi" "$1" <<'EOF'
import sys
sys.path.insert(0, sys.argv[1])
import xymon
xymon.query = lambda req: sys.argv[2]
for a in xymon.alarms():
    flags = [k for k in ("stale", "unreachable") if k in a]
    print(a["host"], a["severity"], a["status"], *flags)
EOF
}

# line HOST COLOR PREVGAPCOLOR -- a board line in BOARD_FIELDS' order.
line() { printf '%s|conn|%s|1700000000|0|||%s\n' "$1" "$2" "$3"; }

out=$(alarms "$(line silent purple red; line silentyel purple yellow; line silentgreen purple green; line down clear red; line nonet clear none; line off blue red; line offgreen blue green; line red red none; line ok green none)")

assert_contains 'silent major firing stale' "$out" "purple over red: the red it measured, major, and stale"
assert_contains 'silentyel minor firing stale' "$out" "purple over yellow: minor, and stale"
assert_contains 'silentgreen indeterminate firing stale' "$out" "purple over green: nothing bad measured, indeterminate, and stale"
assert_contains 'down major firing unreachable' "$out" "xymond's clear over red, a host down: major, and unreachable"
assert_contains 'nonet indeterminate firing unreachable' "$out" "xymonnet's clear, nothing behind it: indeterminate, and unreachable"
assert_contains 'off major suppressed' "$out" "blue over red: major, suppressed"
assert_contains 'offgreen indeterminate suppressed' "$out" "blue over green: indeterminate, suppressed"
assert_contains 'red major firing' "$out" "red: major, firing, nothing beside it"
assert_not_contains 'red major firing stale' "$out" "red is not stale"
assert_not_contains 'ok ' "$out" "green is no alarm"

pass "an alarm keeps the severity its test last measured, with stale, unreachable or suppressed beside it"
