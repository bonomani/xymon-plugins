#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/xymonapi-runner.sh
#
# tests/run.sh runs the tests of the directories it is given, counts a pass,
# a skip (77) and a failure, and fails the run on a failure; a plugin's make
# test gives it that plugin's tests/, and make with no target runs none.
#
# Runs stand-in tests only. Uses the test helpers of the Xymon tree in
# XYMON_SRC.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
make=${MAKE:-make}

mkdir -p "$work/t"
printf 'exit 0\n' > "$work/t/a.sh"
printf 'exit 77\n' > "$work/t/b.sh"
printf 'exit 1\n' > "$work/t/c.sh"
rc=0
out=$(XYMONAPI_NO_SKIP= "$ROOT/tests/run.sh" "$work/t" 2>&1) || rc=$?
assert_contains "passed: 1, skipped: 1, failed: 1" "$out" "run.sh runs the tests of the directory it is given, and counts each"
[ "$rc" -ne 0 ] || fail "run.sh succeeded with a failing test"
assert_not_contains "plugins/" "$out" "and none of the others"

assert_contains 'tests/run.sh "plugins/xymonapi/tests"' "$("$make" -n -C "$ROOT/plugins/xymonapi" test 2>&1)" "a plugin's make test runs its own tests"
assert_not_contains 'run.sh' "$("$make" -n -C "$ROOT/plugins/xymonapi" 2>&1)" "and make with no target runs none"

pass "run.sh runs and counts the tests of the directories given; make test in a plugin runs its own, make alone none"
