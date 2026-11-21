#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/xymonapi-runner.sh
#
# tests/run.sh runs the tests of the directories it is given, and those
# only, counts a pass, a skip (77) and a failure, and fails the run on a
# failure. With -j N it runs N at once, counts them the same, prints each
# output whole in the usual order, and XYMONAPI_NO_SKIP=1 still fails a run
# with a skip.
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
out=$(XYMONAPI_NO_SKIP='' "$ROOT/tests/run.sh" "$work/t" 2>&1) || rc=$?
assert_contains "passed: 1, skipped: 1, failed: 1" "$out" "run.sh runs the tests of the directory it is given, and counts each"
[ "$rc" -ne 0 ] || fail "run.sh succeeded with a failing test"
assert_not_contains "plugins/" "$out" "and none of the others"

# -j 2: the same counts, and each output whole, in order.
rc=0
out=$(XYMONAPI_NO_SKIP='' "$ROOT/tests/run.sh" -j 2 "$work/t" 2>&1) || rc=$?
assert_contains "passed: 1, skipped: 1, failed: 1" "$out" "run.sh -j 2 counts each the same"
[ "$rc" -ne 0 ] || fail "run.sh -j 2 succeeded with a failing test"
assert_match "a\.sh -----.*b\.sh -----.*c\.sh -----" "$(printf '%s' "$out" | tr '\n' ' ')" "and prints their outputs in order"

# They do run at once: a.sh waits for a file b.sh makes, which one after
# the other -- a.sh first -- never comes.
mkdir -p "$work/p"
printf 'for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -e %s/b-ran ] && exit 0; sleep 0.25; done\nexit 1\n' "$work/p" > "$work/p/a.sh"
printf ': > %s/b-ran\n' "$work/p" > "$work/p/b.sh"
out=$("$ROOT/tests/run.sh" -j 2 "$work/p" 2>&1) || fail "run.sh -j 2 did not run two tests at once: $out"
assert_contains "passed: 2, skipped: 0, failed: 0" "$out" "run.sh -j 2 runs two tests at once"
rm -f "$work/p/b-ran"
rc=0
"$ROOT/tests/run.sh" "$work/p" > /dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "without -j, a.sh found b.sh's file: the tests did not run one after the other"

# A skip fails the run under XYMONAPI_NO_SKIP=1, with -j as without.
rm -f "$work/t/c.sh"
rc=0
XYMONAPI_NO_SKIP=1 "$ROOT/tests/run.sh" -j 2 "$work/t" > "$work/noskip.log" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "run.sh -j 2 with XYMONAPI_NO_SKIP=1 passed a run with a skip"
assert_contains "XYMONAPI_NO_SKIP=1, and 1 test(s) skipped" "$(cat "$work/noskip.log")" "and says why"

# -j takes a number, 1 or more.
for j in 0 x ""; do
	rc=0
	"$ROOT/tests/run.sh" -j "$j" "$work/t" > "$work/j.log" 2>&1 || rc=$?
	assert_equal "2" "$rc" "run.sh -j '$j' is refused"
done

pass "run.sh runs and counts the tests of the directories given, and no others, one after the other or N at once with -j"
