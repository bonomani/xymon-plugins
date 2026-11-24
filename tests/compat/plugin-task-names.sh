#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-task-names.sh
#
# A task is named after its part (S6): each shipped task file a PLUGIN
# names has one section, [NAME-server] for its server-task:, [NAME-client]
# for its client-task: -- the installer's own server task alone keeps
# [xymon-plugin] --, and no include or directory line, which xymonlaunch
# would follow past this check; no plugin is named with a -server or
# -client ending, which another's task would share.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
n=0
for p in "$ROOT"/plugins/*/PLUGIN; do
	d=${p%/PLUGIN} name=${d##*/}
	case $name in *-server|*-client) fail "[S6] plugin $name is named with a part's ending, which another plugin's task would share" ;; esac
	for part in server client; do
		f=$(sed -n "s/^$part-task:[[:space:]]*//p" "$p")
		[ -n "$f" ] || continue
		want="$name-$part"
		[ "$name/$part" != xymon-plugin/server ] || want=xymon-plugin
		sections=$(sed -n 's/^[[:space:]]*\[\(.*\)\][[:space:]]*$/\1/p' "$d/$f")
		assert_equal "$want" "$sections" "[S6] $name's $part task file $f has the one section [$want]"
		if grep -Eq '^[[:space:]]*(optional[[:space:]]+)?(include|directory)[[:space:]]' "$d/$f"; then
			fail "[S6] $name's $part task file $f has an include or directory line"
		fi
		n=$((n + 1))
	done
done
[ "$n" -ge 4 ] || fail "only $n task files found: the check proved nothing"

pass "each of the $n shipped task files has its one section named after its part, [NAME-server] or [NAME-client] (the installer's own server task [xymon-plugin]), no include or directory line; no plugin named with a part's ending"
