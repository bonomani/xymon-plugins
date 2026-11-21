#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/run.sh -- run the tests in each DIR, by default every one: each
# plugin's, under plugins/<name>/tests/, then those of how the plugins fit
# together, under tests/compat/, against the built Xymon source tree named
# by XYMON_SRC. Given plugins/NAME/tests, it runs that plugin's alone.
#
#   XYMON_SRC=/path/to/xymon tests/run.sh [-j N] [DIR...]
#
# With -j N, N tests run at once: each says "done" as it ends, and their
# whole outputs follow, in the usual order, once all have ended.
#
# A test passes with 0, skips with 77 -- something it needs is not installed,
# and it says what -- and fails with anything else. The run fails if any test
# fails; with XYMONAPI_NO_SKIP=1 a skip fails it too, which is how CI makes
# sure every test really ran.

cd "$(dirname "$0")/.." || exit 2
jobs=1
case ${1:-} in
	-j) jobs=${2:-}; shift; [ "$#" -eq 0 ] || shift ;;
	-j*) jobs=${1#-j}; shift ;;
esac
case $jobs in
	''|*[!0-9]*|0) echo "tests/run.sh: -j takes how many tests run at once, 1 or more" >&2; exit 2 ;;
esac
[ "$#" -gt 0 ] || set -- plugins/*/tests tests/compat
tests=$(for d in "$@"; do ls "$d"/*.sh; done)
pass=0 skip=0 fail=0
count() {
	case $2 in
		0)  pass=$((pass + 1)) ;;
		77) skip=$((skip + 1)) ;;
		*)  fail=$((fail + 1)); echo "FAIL: $1 (rc=$2)" ;;
	esac
}
if [ "$jobs" -eq 1 ]; then
	for t in $tests; do
		echo "----- $t -----"
		rc=0
		bash "$t" || rc=$?
		count "$t" "$rc"
	done
else
	out=$(mktemp -d "${TMPDIR:-/tmp}/run.XXXXXX") || exit 2
	trap 'rm -rf "$out"' EXIT
	# Each test's output and status in files of its own, by its rank; a
	# test reads no terminal, as under CI.
	n=0
	# shellcheck disable=SC2016 # expanded by the sh that xargs runs
	for t in $tests; do n=$((n + 1)); printf '%s %s\n' "$n" "$t"; done |
		xargs -P "$jobs" -L 1 sh -c 'rc=0; bash "$2" > "$0/$1.log" 2>&1 < /dev/null || rc=$?
			echo "$rc" > "$0/$1.rc"; echo "done: $2 (rc=$rc)"' "$out"
	n=0
	for t in $tests; do
		n=$((n + 1))
		echo "----- $t -----"
		cat "$out/$n.log"
		count "$t" "$(cat "$out/$n.rc" 2>/dev/null || echo "no status")"
	done
fi
echo "----- passed: $pass, skipped: $skip, failed: $fail -----"
[ "$fail" -eq 0 ] || exit 1
if [ "${XYMONAPI_NO_SKIP:-}" = 1 ] && [ "$skip" -ne 0 ]; then
	echo "XYMONAPI_NO_SKIP=1, and $skip test(s) skipped" >&2
	exit 1
fi
exit 0
