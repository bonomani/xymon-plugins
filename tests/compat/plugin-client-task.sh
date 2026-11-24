#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-client-task.sh
#
# A client part's task, as a server part's (S35, S5, S6, S7, S9, S13), in a
# scratch client tree, with a plugin of the test's own whose client-task:
# names its task file: installed off in ext/NAME/tasks.cfg, @XYMONHOME@
# the client's tree, with no link; turned on by enable --client, a link
# etc/clientlaunch.d/NAME.cfg, refused where clientlaunch.cfg does not read
# that directory unless --force; the file as the administrator edited it
# kept by an update, the change of a new version beside it off a terminal,
# the task kept on; a version with no task taking the link, the edited
# file kept as a .old; a run cut short resumed with the file set aside;
# remove taking the link; the directory removed by hand leaving the link,
# said by verify and taken by clean.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
work=$(cd "$work" && pwd -P)
unset MAN SUDO_USER
export HOME="$work/home" XDG_CONFIG_HOME="$work/cfg" XYMON_PLUGINS_TREES_ONLY=1 XYMON_PLUGINS_TREES=
mkdir -p "$HOME" "$work/man"

# A client's tree, its clientlaunch.cfg reading clientlaunch.d/ as Xymon's.
c=$work/client
mkdir -p "$c/bin" "$c/etc" "$c/ext"
: > "$c/bin/xymonclient.sh"; : > "$c/etc/xymonclient.cfg"
printf 'optional directory %s/etc/clientlaunch.d\n' "$c" > "$c/etc/clientlaunch.cfg"
cp "$c/etc/clientlaunch.cfg" "$work/clientlaunch.cfg"

# repo DIR VERSION [notask] -- a copy of the checkout with ctask, a client
# part whose task file is ctask.tasks; the second version adds a line.
repo() {
	mkdir -p "$1"
	cp -R "$ROOT/xymon-plugin" "$ROOT/LICENSE" "$ROOT/plugins" "$1/"
	mkdir -p "$1/plugins/ctask"
	printf 'name: ctask\nversion: %s\nsummary: a test\nclient-files: check.sh\n' "$2" > "$1/plugins/ctask/PLUGIN"
	[ -n "${3:-}" ] || echo "client-task: ctask.tasks" >> "$1/plugins/ctask/PLUGIN"
	printf '#!/bin/sh\nexit 0\n' > "$1/plugins/ctask/check.sh"
	printf '[ctask]\n\tENVFILE @XYMONHOME@/etc/xymonclient.cfg\n\tCMD @XYMONHOME@/ext/ctask/check.sh\n\tINTERVAL 5m\n' > "$1/plugins/ctask/ctask.tasks"
	[ "$2" = 1.0.0 ] || printf '\tLOGFILE @XYMONHOME@/ctask.log\n' >> "$1/plugins/ctask/ctask.tasks"
}
v1=$work/v1 v2=$work/v2 v3=$work/v3
repo "$v1" 1.0.0; repo "$v2" 1.1.0; repo "$v3" 1.2.0 notask

# x REPO ARG... -- that copy's xymon-plugin, off a terminal, on the client.
x() { r=$1; shift; rc=0; out=$("$r/xymon-plugin" "$@" XYMONHOME="$c" MANDIR="$work/man" </dev/null 2>&1) || rc=$?; }
ok() { [ "$rc" -eq 0 ] || fail "$1 failed ($rc): $out"; }
d=$c/ext/ctask link=$c/etc/clientlaunch.d/ctask.cfg

# Installed off: the task file, @XYMONHOME@ the client's, and no link --
# nor clientlaunch.d/ made: a client's etc/ may be the system's, which its
# owner cannot write.
x "$v1" install --client ctask; ok "install --client"
[ ! -e "$c/etc/clientlaunch.d" ] || fail "[S5] the install of a task off made clientlaunch.d/"
assert_not_contains "clientlaunch.d" "$out" "[S5] nor tried to, an error said"
assert_file_exists "$d/tasks.cfg"
assert_contains "CMD $c/ext/ctask/check.sh" "$(cat "$d/tasks.cfg")" "[S6] the task file has @XYMONHOME@ as the client's tree"
{ [ -e "$link" ] || [ -L "$link" ]; } && fail "[S5] the install made a link"
assert_contains "ctask's task is off: ./xymon-plugin enable --client --xymon-home $c ctask turns it on" "$out" "[S5] and says how to turn it on"
x "$v1" status --client; assert_contains "ctask: 1.0.0 installed, off" "$out" "[S13] status says it off"

# enable: refused where clientlaunch.cfg does not read clientlaunch.d/,
# made all the same with --force; then on, the link to the task file.
echo '# no directory line' > "$c/etc/clientlaunch.cfg"
x "$v1" enable --client ctask
[ "$rc" -ne 0 ] || fail "[S13] enable with a clientlaunch.cfg that does not read clientlaunch.d/ was taken: $out"
assert_contains "$c/etc/clientlaunch.cfg does not read clientlaunch.d/" "$out" "[S13] and says why"
assert_contains "directory $c/etc/clientlaunch.d" "$out" "[S13] and the line to add"
{ [ -e "$link" ] || [ -L "$link" ]; } && fail "[S13] the refused enable made a link"
x "$v1" enable --client ctask --force; ok "enable --client --force"
[ -L "$link" ] || fail "[S13] --force made no link"
x "$v1" disable --client ctask; ok "disable --client"
{ [ -e "$link" ] || [ -L "$link" ]; } && fail "[S13] disable left the link"
cp "$work/clientlaunch.cfg" "$c/etc/clientlaunch.cfg"
x "$v1" enable --client ctask; ok "enable --client"
assert_equal "$c/ext/ctask/tasks.cfg" "$(readlink "$link")" "[S13] enable links clientlaunch.d/ctask.cfg to the task file"
x "$v1" status --client; assert_contains "ctask: 1.0.0 installed, on" "$out" "[S13] status says it on"

# Edited, then updated to a version that changes another line: off a
# terminal nothing is merged, the edit stays, this version's beside it;
# the task stays on.
sed 's/INTERVAL 5m/INTERVAL 1h/' "$d/tasks.cfg" > "$work/edited"; cat "$work/edited" > "$d/tasks.cfg"
x "$v1" verify --client; assert_contains "edited: ctask: tasks.cfg, the administrator's" "$out" "[S30] verify says the task file edited"
printf '#!/bin/sh\n' > "$d/mine.sh.old"; chmod +x "$d/mine.sh.old"
x "$v2" update --client ctask; ok "update --client to 1.1.0"
assert_contains "INTERVAL 1h" "$(cat "$d/tasks.cfg")" "[S7] the update kept the task file as edited"
assert_file_exists "$d/tasks.cfg.new"
assert_contains "LOGFILE" "$(cat "$d/tasks.cfg.new")" "[S7] and wrote this version's beside it"
assert_contains "$d/tasks.cfg is kept as yours" "$out" "[S7] and says so"
assert_equal "$c/ext/ctask/tasks.cfg" "$(readlink "$link")" "[S7] the task stays on"
[ -f "$d/mine.sh.old" ] || fail "[S7] the update took a NAME.old"
x "$v2" verify --client
assert_contains "tasks.cfg.new, this version's beside yours: compare, then remove it" "$out" "[S30] verify says the .new beside the task file"
assert_contains "mine.sh.old, yours, kept by an update: compare, then remove it" "$out" "[S30] and a NAME.old an update keeps"
assert_not_contains "is not what was installed" "$out" "[S30] neither as for an update to fix"
rm -f "$d/tasks.cfg.new" "$d/mine.sh.old"

# Cut short after the directory is emptied: the edited task file set aside,
# said; the next update resumes with it.
cutr=$work/cut; repo "$cutr" 1.1.0
# shellcheck disable=SC2016 # the installer's line, as it is written
line='	fresh "$dir" "$keep" || exit 1'
[ "$(grep -cxF -- "$line" "$ROOT/plugins/xymon-plugin/xymon-plugin")" -eq 1 ] || fail "the installer has not once the line: $line"
awk -v l="$line" '{ print } $0 == l { print "\tkill -TERM $$" }' "$ROOT/plugins/xymon-plugin/xymon-plugin" > "$cutr/plugins/xymon-plugin/xymon-plugin"
x "$cutr" update --client ctask
[ "$rc" -ne 0 ] || fail "[S7] the cut update succeeded: $out"
[ -d "$c/ext/.xymon-plugin.ctask" ] || fail "[S7] the cut update left no set-aside directory: $out"
assert_contains "set aside in $c/ext/.xymon-plugin.ctask" "$out" "[S7] and says what it set aside"
x "$v2" update --client ctask; ok "update --client resuming"
assert_contains "Resuming the install of ctask cut short" "$out" "[S7] the next update resumes"
assert_contains "INTERVAL 1h" "$(cat "$d/tasks.cfg")" "[S7] with the edited task file"
[ ! -e "$c/ext/.xymon-plugin.ctask" ] || fail "[S7] the resumed update left the set-aside directory"
assert_equal "$c/ext/ctask/tasks.cfg" "$(readlink "$link")" "[S7] the task still on"

# A version with no task: the link goes, the edited file kept as a .old.
x "$v3" update --client ctask; ok "update --client to a version with no task"
{ [ -e "$link" ] || [ -L "$link" ]; } && fail "[S7] a version with no task left the link"
assert_file_exists "$d/tasks.cfg.old"
assert_contains "INTERVAL 1h" "$(cat "$d/tasks.cfg.old")" "[S7] and kept the edited task file as a .old"
x "$v3" verify --client
assert_contains "tasks.cfg.old, yours, kept by an update: compare, then remove it" "$out" "[S30] verify says the .old kept"
rm -f "$d/tasks.cfg.old"

# remove takes the link.
x "$v1" update --client ctask; ok "update --client back to a version with a task"
x "$v1" enable --client ctask; ok "enable --client again"

# A file in the link's place, edited, and a version with no task: kept
# with the task file, said (S6).
cp "$d/tasks.cfg" "$work/t"; rm "$link"
sed 's/INTERVAL 5m/INTERVAL 2h/' "$work/t" > "$link"
x "$v3" update --client ctask; ok "update --client to no task, a file in the link's place"
assert_contains "$link, edited, read by xymonlaunch in the link's place, is kept with ctask's task file" "$out" "[S6] the file in the link's place is kept, said"
{ [ -e "$link" ] || [ -L "$link" ]; } && fail "[S7] the file in the link's place stayed"
grep -l 'INTERVAL 2h' "$d"/*.old > /dev/null 2>&1 || fail "[S6] the edited file in the link's place was lost: $(ls -A "$d")"
rm -f "$d"/*.old
x "$v1" update --client ctask; ok "update --client back to a task, again"
x "$v1" enable --client ctask; ok "enable --client, again"

# A clientlaunch.d/ in which nothing can be removed nor made, as the
# system's: rm and ln refuse there (a mode bit stops nothing for root, who
# runs the CI's lanes). disable and remove fail, saying so; an update that
# must change it is refused before anything is replaced, not cut short.
mkdir -p "$work/ro"
for t in rm ln; do
	# shellcheck disable=SC2016 # the shim's own $a and $@
	printf '#!/bin/sh\nfor a; do case $a in %s/*) echo "%s: $a: Permission denied" >&2; exit 1 ;; esac; done\nexec %s "$@"\n' \
		"$c/etc/clientlaunch.d" "$t" "$(command -v "$t")" > "$work/ro/$t"
	chmod 755 "$work/ro/$t"
done
ro() { op=$PATH; PATH=$work/ro:$PATH; x "$@"; PATH=$op; }
ro "$v1" disable --client ctask
[ "$rc" -ne 0 ] || fail "[S13] disable that could not remove the link succeeded: $out"
assert_contains "could not remove $link: ctask stays on" "$out" "[S13] and says why"
[ -L "$link" ] || fail "[S13] the link went all the same"
ro "$v3" update --client ctask
[ "$rc" -ne 0 ] || fail "[S7] an update to no task, the link not removable, succeeded: $out"
assert_contains "$c/etc/clientlaunch.d cannot be written, where ctask's update must change $link: nothing is replaced" "$out" "[S7] and is refused, saying why"
[ ! -e "$c/ext/.xymon-plugin.ctask" ] || fail "[S7] the refused update was cut short, not refused before anything: $out"
x "$v1" status --client; assert_contains "ctask: 1.0.0 installed, on" "$out" "[S7] the install as it was"
cp "$d/tasks.cfg" "$work/t"; rm "$link"; cat "$work/t" > "$link"
ro "$v2" update --client ctask
[ "$rc" -ne 0 ] || fail "[S7] an update that must make a link in place of a file, not writable, succeeded: $out"
assert_contains "cannot be written, where ctask's update must change $link: nothing is replaced" "$out" "[S7] refused, saying why"
[ ! -e "$c/ext/.xymon-plugin.ctask" ] || fail "[S7] the refused update was cut short: $out"
{ [ -f "$link" ] && [ ! -L "$link" ]; } || fail "[S7] the file in the link's place was touched"
x "$v1" update --client ctask; ok "update --client, the file made a link"
ro "$v1" remove --client ctask
[ "$rc" -ne 0 ] || fail "[S8] remove that could not remove the link succeeded: $out"
assert_contains "could not remove $link: ctask's task stays on" "$out" "[S8] and says why"
x "$v1" remove --client ctask; ok "remove --client, the link left"
{ [ -e "$link" ] || [ -L "$link" ]; } && fail "[S9] the link left was not removed"
x "$v1" install --client ctask; ok "install --client, after"
x "$v1" enable --client ctask; ok "enable --client, after"
x "$v1" remove --client ctask; ok "remove --client"
{ [ -e "$link" ] || [ -L "$link" ]; } && fail "[S8] remove --client left the task link"

# The directory removed by hand: the link left, taken by remove (S9), or
# said by verify and taken by clean (S30, S31).
x "$v1" install --client ctask; ok "install --client, to remove by hand"
x "$v1" enable --client ctask; ok "enable --client, to remove by hand"
rm -rf "$d"
x "$v1" remove --client ctask; ok "remove --client of a directory gone"
{ [ -e "$link" ] || [ -L "$link" ]; } && fail "[S9] remove --client of a directory gone left the task link"
assert_contains "its task link, left, is removed" "$out" "[S9] and says so"
x "$v1" install --client ctask; ok "install --client again"
x "$v1" enable --client ctask; ok "enable --client once more"
rm -rf "$d"
x "$v1" verify --client
[ "$rc" -eq 4 ] || fail "[S30] verify --client with a task link left: not 4 ($rc): $out"
assert_contains "the task link of ctask, which is gone: ./xymon-plugin clean --client ctask" "$out" "[S30] verify says the task link left"
x "$v1" clean --client ctask --yes; ok "clean --client"
{ [ -e "$link" ] || [ -L "$link" ]; } && fail "[S31] clean --client left the task link"

# A cut update, then the directory removed by hand: the set-aside
# directory said by verify with no name, and by remove (S7, S30).
x "$v1" install --client ctask; ok "install --client, to cut"
x "$cutr" update --client ctask
[ "$rc" -ne 0 ] || fail "[S7] the cut update succeeded: $out"
rm -rf "$d"
x "$v1" verify --client
[ "$rc" -eq 4 ] || fail "[S30] verify --client with a set-aside directory left: not 4 ($rc): $out"
assert_contains "$c/ext/.xymon-plugin.ctask, set aside on" "$out" "[S30] verify says the set-aside directory left"
x "$v1" remove --client ctask; ok "remove --client, the directory gone, set aside"
assert_contains "$c/ext/.xymon-plugin.ctask, set aside on" "$out" "[S7] remove says it too"

pass "a client part's task, as a server part's: installed off with the client's tree filled in, enable through clientlaunch.d refused unless clientlaunch.cfg reads it or --force, edits and on kept by an update, a cut update resumed, a version with no task taking the link and keeping the edit, remove and clean taking the link"
