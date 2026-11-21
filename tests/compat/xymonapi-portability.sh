#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/xymonapi-portability.sh
#
# The plugins' test scripts, ./xymon-plugin, and every other script a user's
# machine runs -- each plugin's launchers and build/*.sh -- keep to Xymon's portability rules: bash 3.2,
# portable tool flags and regular expressions, no early-exit pipes under
# pipefail, and the rest of what Xymon's BSD and macOS lanes taught it. The
# rules are Xymon's own, read from XYMON_SRC at each run, not a copy kept
# here: Xymon's tests/buildsystem/test-suite-lint.sh (named
# test-suite-portability.sh before Xymon 4.3.32) is run over a
# temporary tree laid out as it expects -- its script and assert.sh beside
# this repository's tests/ and each plugins/NAME/tests/, under
# tests/plugins/NAME/ -- since it checks the tree it sits in.
#
# Two rules are left out. interpreter, no python or perl in a test: Xymon's
# BSD lanes have no Python; every plugin here needs it, so a lane without
# Python cannot run the plugins at all. rrdtool-cli, read a RRD through
# librrd rather than the rrdtool command: the API runs that command itself,
# so the plugins need it, and their tests with it (below).
#
# Skips where XYMON_SRC holds neither. Needs XYMON_SRC.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
check=$XYMON_SRC/tests/buildsystem/test-suite-lint.sh
[ -f "$check" ] || check=$XYMON_SRC/tests/buildsystem/test-suite-portability.sh
[ -f "$check" ] || skip "XYMON_SRC has no tests/buildsystem/test-suite-lint.sh, nor its older name test-suite-portability.sh"

work=$(mktempdir)
tree=$work/tree
mkdir -p "$tree/tests/buildsystem" "$tree/tests/lib" "$tree/tests/plugins"
cp "$check" "$tree/tests/buildsystem/"
cp "$XYMON_SRC/tests/lib/assert.sh" "$tree/tests/lib/assert-xymon.sh"
# This repository's tests, then each plugin's, where the check looks.
(cd "$ROOT/tests" && tar cf - .) | (cd "$tree/tests" && tar xf -)
for d in "$ROOT"/plugins/*/tests; do
	name=$(basename "$(dirname "$d")")
	mkdir -p "$tree/tests/plugins/$name"
	(cd "$d" && tar cf - .) | (cd "$tree/tests/plugins/$name" && tar xf -)
done
# And the installer, which runs on every machine the plugins go to: placed
# where the check looks, and named back as it is here.
cp "$ROOT/xymon-plugin" "$tree/tests/install-sh-under-check.sh"
# The launchers and the build scripts, run on those machines too, placed
# the same way under tests/shipped/, with their paths.
for f in "$ROOT"/plugins/*/*.sh "$ROOT"/build/*.sh; do
	rel=${f#"$ROOT"/}
	mkdir -p "$tree/tests/shipped/$(dirname "$rel")"
	cp "$f" "$tree/tests/shipped/$rel"
done
# The check sources ../lib/assert.sh; this repository has its own file of
# that name, so Xymon's goes in under another, and the check is pointed at it.
sed -e 's|/\.\./lib/assert\.sh"|/../lib/assert-xymon.sh"|' "$tree/tests/buildsystem/$(basename "$check")" \
	> "$work/check.sh"
mv "$work/check.sh" "$tree/tests/buildsystem/$(basename "$check")"

rc=0
bash "$tree/tests/buildsystem/$(basename "$check")" > "$work/report" 2>&1 || rc=$?

# The report gives each violation as "  [RULE] FILE:LINE" and its reason on the
# next, indented line. Keep those of every rule but interpreter and
# rrdtool-cli, with each file named as it is in this repository. rrdtool-cli
# keeps Xymon's tests on librrd, which Xymon links, as the rrdtool command is
# not installed on every lane and a test gating on it checks less there. The
# API runs the rrdtool command itself (plugins/xymonapi/xymon.py, rrdtool info
# and xport): for the plugins it is what the product needs, and CI's
# XYMONAPI_NO_SKIP=1 makes a skip for want of it a failure. The make-tree rules exempt Xymon's
# tests/lib/assert.sh by its name, the one file where its helpers read the
# make tree on purpose; its copy here goes by another name, so it is exempted
# from them the same way, and from nothing else.
awk '
	/^  \[[a-z-]+\] / {
		keep = ($1 != "[interpreter]") && ($1 != "[rrdtool-cli]") && !($1 ~ /^\[make-tree-/ && $2 ~ /^tests\/lib\/assert-xymon\.sh:/)
		if (keep) print; next
	}
	/^      / { if (keep) print; next }
	{ keep = 0 }
' "$work/report" | sed -e 's|tests/shipped/||' -e 's|^\(  \[[a-z-]*\] \)tests/plugins/\([^/]*\)/|\1plugins/\2/tests/|' -e 's|tests/install-sh-under-check\.sh|xymon-plugin|' > "$work/violations"

if [ -s "$work/violations" ]; then
	fail "[S12] the plugins' tests break Xymon's portability rules:
$(cat "$work/violations")"
fi
# Exited with an error for something other than violations -- a rule's own
# self-test, a helper missing -- is a failure of its own, not a pass.
if [ "$rc" -ne 0 ] && ! grep -q 'violation(s); see above' "$work/report"; then
	fail "Xymon's portability check did not run: $(tail -n 5 "$work/report")"
fi

pass "the plugins' tests, xymon-plugin, the launchers and build/*.sh keep to Xymon's portability rules, but the one against Python, which every plugin needs, and the one against the rrdtool command, which the API runs"
