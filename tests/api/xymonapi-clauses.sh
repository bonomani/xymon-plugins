#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/api/xymonapi-clauses.sh
#
# Every rule openapi.yaml numbers -- the C<n>. lines of its description -- is
# checked by at least one test, which cites it as [C<n>] in an assertion's
# message, and no test cites a rule that does not exist: a rule nobody
# tests, or a citation left behind by a renumbering, fails the run. Prints
# which tests check each rule, so that an implementation of the API can see
# which rules it is held to and by what.
#
# Reads files only: no API is started.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
spec="$ROOT/plugins/xymonapi/openapi.yaml"

rules=$(sed -n 's/^ *\(C[0-9][0-9]*\)\. .*/\1/p' "$spec")
[ -n "$rules" ] || fail "openapi.yaml numbers no rules (C1. ...)"

# One line per citation: the test's file name, then the rule. This file is
# left out: it names the form of a citation, not a rule.
cites=$(grep -o '\[C[0-9][0-9]*\]' "$ROOT"/tests/api/*.sh /dev/null | grep -v '/xymonapi-clauses\.sh:' \
	| sed 's|.*/\([^/]*\)\.sh:\[\(C[0-9]*\)\]|\1 \2|' | sort -u)

missing=""
for r in $rules; do
	by=$(printf '%s\n' "$cites" | sed -n "s/^\([^ ]*\) $r\$/\1/p" | tr '\n' ' ')
	printf '%-4s %s\n' "$r" "${by:-(no test)}"
	[ -n "$by" ] || missing="$missing $r"
done
[ -z "$missing" ] || fail "rules of openapi.yaml no test cites:$missing"

for c in $(printf '%s\n' "$cites" | cut -d' ' -f2 | sort -u); do
	printf '%s\n' "$rules" | grep -qx "$c" \
		|| fail "a test cites [$c], which openapi.yaml does not number: $(printf '%s\n' "$cites" | grep " $c\$" | cut -d' ' -f1 | tr '\n' ' ')"
done

pass "every rule openapi.yaml numbers is cited by a test, and every citation names one of them"
