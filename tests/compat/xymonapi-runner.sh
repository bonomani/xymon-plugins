#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/xymonapi-runner.sh
#
# tests/run.sh runs the tests of the directories it is given, and those
# only, counts a pass, a skip (77) and a failure, and fails the run on a
# failure.
#
# Runs stand-in tests only. Uses the test helpers of the Xymon tree in
# XYMON_SRC.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)

mkdir -p "$work/t"
printf 'exit 0\n' > "$work/t/a.sh"
printf 'exit 77\n' > "$work/t/b.sh"
printf 'exit 1\n' > "$work/t/c.sh"
rc=0
out=$(XYMONAPI_NO_SKIP= "$ROOT/tests/run.sh" "$work/t" 2>&1) || rc=$?
assert_contains "passed: 1, skipped: 1, failed: 1" "$out" "run.sh runs the tests of the directory it is given, and counts each"
[ "$rc" -ne 0 ] || fail "run.sh succeeded with a failing test"
assert_not_contains "plugins/" "$out" "and none of the others"

pass "run.sh runs and counts the tests of the directories given, and no others"
