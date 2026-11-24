#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-task-needs.sh
#
# A plugin's task names in NEEDS only a task its launcher knows when it
# reads it (S34): for the server part, a task of Xymon's own tasks.cfg
# defined before the line that reads tasks.d/. xymonlaunch resolves NEEDS
# against the tasks read so far (common/xymonlaunch.c) and reads tasks.d/
# by name, so another plugin's task may come after and the dependency be
# ignored, "unknown dependency" logged at each reload. Read from the Xymon
# tree in XYMON_SRC.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
cfg=${XYMON_SRC:-}/xymond/etcfiles/tasks.cfg
[ -f "$cfg" ] || skip "no Xymon tree in XYMON_SRC: $cfg"

# The tasks Xymon's tasks.cfg defines before it reads tasks.d/.
known=$(awk '/^[ \t]*(optional[ \t]+)?directory[ \t].*tasks\.d/ { exit }
	/^\[[^]]+\]/ { gsub(/[][]/, ""); print }' "$cfg")
assert_contains "xymond" "$known" "Xymon's tasks.cfg defines xymond before tasks.d/"

n=0
for p in "$ROOT"/plugins/*/PLUGIN; do
	d=$(dirname "$p")
	t=$(sed -n 's/^server-task: //p' "$p")
	[ -n "$t" ] || continue
	while read -r need; do
		n=$((n + 1))
		grep -qx "$need" <<<"$known" \
			|| fail "[S34] $(basename "$d")'s task NEEDS $need, which Xymon's tasks.cfg does not define before tasks.d/: xymonlaunch would ignore it"
	done < <(sed -n 's/^[[:space:]]*NEEDS[[:space:]]\{1,\}\([^[:space:]]*\).*/\1/p' "$d/$t")
done
[ "$n" -gt 0 ] || fail "no NEEDS found in any plugin's task: the test reads nothing"

pass "each plugin's server task NEEDS only a task of Xymon's tasks.cfg, known before tasks.d/ is read ($n checked)"
