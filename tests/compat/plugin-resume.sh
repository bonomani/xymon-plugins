#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-resume.sh
#
# An install or update of a server part cut short, by a failure or by
# SIGTERM, at each point from setting files aside to writing VERSION,
# loses none of the administrator's files: what it set aside stays in its
# marked directory in ext/, said, and the next update resumes with it --
# one cut short before VERSION being an install cut short, which update
# takes (S20) -- the edited task file and snippet back in place and the
# task on, each NAME.old back, whatever its name, and the directory gone;
# to a version that no longer ships them, the edited task file and
# snippet kept as NAME.old instead, the task link gone. No message says to
# remove anything by hand. An edited file in the task link's place, of a
# task the new version no longer ships, is kept as a .old too, and so is
# a task file that one in the link's place replaces, edited too. A .old
# changed since the cut is NAME.1.old. One from before the PLUGIN copy is
# resumed. One cut short is present: clean takes nothing of it, removing
# another keeps the virtualenv, and needing a plugin, it blocks that
# one's removal. Resuming into a version that replaces an edited snippet
# is refused, the snippet found where it was set aside.
#
# Copies of the checkout carry an installer with `exit 1` or
# `kill -TERM $$` put after a line; v2 ships neither the nginx snippet nor
# a task.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
unset MAN SUDO_USER
export HOME="$work/home" XDG_CONFIG_HOME="$work/cfg" XYMON_PLUGINS_TREES_ONLY=1 XYMON_PLUGINS_TREES=
mkdir -p "$HOME" "$work/man"
s=$work/server
server_tree "$s"
e=$s/ext d=$e/xymonapi link=$s/etc/tasks.d/xymonapi.cfg

copy() { mkdir -p "$1"; cp -R "$ROOT/xymon-plugin" "$ROOT/LICENSE" "$ROOT/plugins" "$1/"; }
v2=$work/v2; copy "$v2"
sed -e 's/^conf: .*/conf: xymonapi-apache.conf xymonapi-lighttpd.conf/; /^task: /d' "$ROOT/plugins/xymonapi/PLUGIN" > "$v2/plugins/xymonapi/PLUGIN"

# x [-r REPO] ARG... -- REPO's xymon-plugin ARG..., the checkout's by
# default, on the scratch server, off a terminal.
x() {
	local r=$ROOT; if [ "$1" = -r ]; then r=$2; shift 2; fi
	rc=0; out=$("$r/xymon-plugin" "$@" XYMONHOME="$s" MANDIR="$work/man" </dev/null 2>&1) || rc=$?
}
ok() { [ "$rc" -eq 0 ] || fail "$1 failed: $out"; }
# cut BASE LINE ACTION -- a copy of BASE whose installer runs ACTION after
# LINE, a whole line of it, there once.
cut() {
	local c=$work/cut
	rm -rf "$c"; copy "$c"; cp "$1/plugins/xymonapi/PLUGIN" "$c/plugins/xymonapi/PLUGIN"
	[ "$(grep -cxF -- "$2" "$ROOT/plugins/xymon-plugin/xymon-plugin")" -eq 1 ] || fail "the installer has not once the line: $2"
	awk -v l="$2" -v a="$3" '{ print } $0 == l { print a }' "$ROOT/plugins/xymon-plugin/xymon-plugin" > "$c/plugins/xymon-plugin/xymon-plugin"
}
# admin -- xymonapi installed, on, its nginx snippet and task file edited,
# NAME.old files of every kind of name beside them.
admin() {
	x remove --server xymonapi; rm -rf "$d" "$e"/.xymon-plugin.*
	x install --server xymonapi; ok "install --server"
	x enable --server xymonapi; ok "enable --server"
	echo "# the admin's nginx" >> "$d/xymonapi-nginx.conf"; cp "$d/xymonapi-nginx.conf" "$work/nginx.kept"
	echo "# the admin's task" >> "$d/tasks.cfg"; cp "$d/tasks.cfg" "$work/task.kept"
	echo "# apache before" > "$d/xymonapi-apache.conf.old"
	echo "# spaced" > "$d/my notes.old"; echo "# star" > "$d/a*b.old"
}
# kept LABEL VERSION -- after the resume, nothing of the admin's lost.
kept() {
	if [ "$2" = v1 ]; then
		cmp -s "$work/nginx.kept" "$d/xymonapi-nginx.conf" || fail "[S7] $1: the edited snippet is not back"
		cmp -s "$work/task.kept" "$d/tasks.cfg" || fail "[S7] $1: the edited task file is not back"
		assert_equal "$d/tasks.cfg" "$(readlink "$link")" "[S13] $1: the task is on"
	else
		cmp -s "$work/nginx.kept" "$d/xymonapi-nginx.conf.old" || fail "[S7] $1: the edited snippet no longer shipped is not kept as .old"
		cmp -s "$work/task.kept" "$d/tasks.cfg.old" || fail "[S7] $1: the edited task file no longer shipped is not kept as .old"
		[ ! -e "$link" ] && [ ! -L "$link" ] || fail "[S20] $1: the task link of a task no longer shipped is left"
	fi
	assert_equal "# apache before" "$(cat "$d/xymonapi-apache.conf.old")" "[S7] $1: a .old is kept"
	assert_equal "# spaced" "$(cat "$d/my notes.old")" "[S7] $1: a .old with a space is kept"
	assert_equal "# star" "$(cat "$d/a*b.old")" "[S7] $1: a .old with a * is kept"
	for f in "$e"/.xymon-plugin.*; do [ ! -e "$f" ] || fail "[S7] $1: $f is left"; done
	# A file set aside the same as the directory's is no second copy.
	for f in "$d"/*.[0-9].old; do [ ! -e "$f" ] || fail "[S7] $1: $f, a copy of a file set aside the same"; done
	[ -f "$d/VERSION" ] || fail "[S20] $1: no VERSION after the resume"
	[ ! -e "$d/.xymon-plugin-in-progress" ] || fail "[S20] $1: the file in progress is left"
}

points='	aside "$1"
	[ ! -L "$ext" ] || die "$ext is a link: left as it is"
	fresh "$ext" "$keep" || exit 1
	copy "$1" server "$ext"
	task "$1"
			mv "$AS/$c" "$dst" || exit 1
	conf "$1"
	aside_back
		mv "$AS/$f" "$(old_name "$ext/$f")" || exit 1'
# Each point, by exit and by SIGTERM, to this version; by exit, to v2.
while IFS= read -r p; do
	for a in 'exit 1' 'kill -TERM $$'; do
		for v in v1 v2; do
			[ "$v" = v1 ] || [ "$a" = 'exit 1' ] || continue
			if [ "$v" = v1 ]; then b=$ROOT; else b=$v2; fi
			l="cut by $a after${p}, to $v"
			admin; cut "$b" "$p" "$a"
			x -r "$work/cut" update --server xymonapi
			[ "$rc" -ne 0 ] || fail "$l: the cut update was taken"
			assert_not_contains "rm -rf" "$out" "[S20] $l: no removal by hand is advised"
			case $out in *"set aside in"*) assert_contains "the next install or update of xymonapi resumes, and puts them back" "$out" "[S7] $l: said" ;; esac
			x -r "$b" update --server xymonapi; ok "$l: the update after"
			assert_not_contains "rm -rf" "$out" "[S20] $l: no removal by hand is advised after"
			kept "$l" "$v"
		done
	done
done <<EOF
$points
EOF

# Said under SIGTERM, which a shell's EXIT trap alone does not see.
admin; cut "$ROOT" '	copy "$1" server "$ext"' 'kill -TERM $$'
x -r "$work/cut" update --server xymonapi
assert_contains "the install of xymonapi was cut short, with" "$out" "[S7] the run killed by SIGTERM says what it set aside"
assert_contains "tasks.cfg" "$out" "[S7] naming the task file"
x update --server xymonapi; ok "the update after one killed"

# Cut short before VERSION, install resumes it too.
admin; cut "$ROOT" '	aside_back' 'exit 1'
x -r "$work/cut" update --server xymonapi
[ ! -e "$d/VERSION" ] || fail "the cut did not come before VERSION"
x install --server xymonapi; ok "install of one cut short"
kept "install of one cut short" v1

# An edited file in the task link's place, of a task the new version no
# longer ships: kept as a .old, said.
admin
rm -f "$link"; cp "$d/tasks.cfg" "$link"; echo "# read by xymonlaunch" >> "$link"; cp "$link" "$work/link.kept"
x -r "$v2" update --server xymonapi; ok "update to v2, a file in the link's place"
assert_contains "$link, edited, read by xymonlaunch in the link's place, is kept" "$out" "[S7] the file in the link's place is said kept"
found=; for f in "$d"/tasks.cfg*.old; do cmp -s "$f" "$work/link.kept" && found=1; done
[ -n "$found" ] || fail "[S7] the edited file in the task link's place is lost"
[ ! -e "$link" ] || fail "[S20] the file in the task link's place is left"

# The task file in the link's place, and the task file it replaces edited
# too, by another hand: neither lost, the one replaced kept as a .old.
admin
rm -f "$link"; cp "$d/tasks.cfg" "$link"; echo "# edit A, in tasks.d" >> "$link"; cp "$link" "$work/a.kept"
echo "# edit B, in the plugin's directory" >> "$d/tasks.cfg"; cp "$d/tasks.cfg" "$work/b.kept"
x update --server xymonapi; ok "update, a file in the link's place and the task file both edited"
cmp -s "$work/a.kept" "$d/tasks.cfg" || fail "[S6] the file xymonlaunch read is not the task file"
found=; for f in "$d"/tasks.cfg*.old; do cmp -s "$f" "$work/b.kept" && found=1; done
[ -n "$found" ] || fail "[S7] the task file it replaced, edited too, is lost"
assert_contains "$d/tasks.cfg, edited too, is kept as a .old of it" "$out" "[S7] and said"

# A .old set aside, and one at its name changed since the cut: the second
# is NAME.1.old, never NAME.old.N.old.
admin; cut "$ROOT" '	copy "$1" server "$ext"' 'exit 1'
x -r "$work/cut" update --server xymonapi
echo "# apache .old changed since" > "$d/xymonapi-apache.conf.old"
x update --server xymonapi; ok "update, a .old changed since the cut"
assert_equal "# apache before" "$(cat "$d/xymonapi-apache.conf.old")" "[S7] the .old set aside is back"
assert_equal "# apache .old changed since" "$(cat "$d/xymonapi-apache.conf.1.old" 2>/dev/null)" "[S7] the .old changed since is NAME.1.old"
for f in "$d"/*.old.*.old; do [ ! -e "$f" ] || fail "[S7] a .old named $f"; done

# An install from before the PLUGIN copy, cut short, is resumed.
admin; rm -f "$d/PLUGIN" "$d/MANIFEST"; cut "$ROOT" '	[ ! -L "$ext" ] || die "$ext is a link: left as it is"' 'exit 1'
x -r "$work/cut" update --server xymonapi
[ "$rc" -ne 0 ] || fail "the cut update of one from before the PLUGIN copy was taken"
x update --server xymonapi; ok "update of one from before the PLUGIN copy, cut short"
cmp -s "$work/nginx.kept" "$d/xymonapi-nginx.conf" || fail "[S20] one from before the PLUGIN copy, cut short: the edited snippet is not back"
cmp -s "$work/task.kept" "$d/tasks.cfg" || fail "[S20] one from before the PLUGIN copy, cut short: the task file is not back"

# Cut short, it is present: clean takes nothing of it, a removal of
# another keeps the virtualenv, and one needing it, cut short, blocks its
# removal.
admin; x install --server xymon-plugin; ok "install --server xymon-plugin"
mkdir -p "$e/venv"; echo mine > "$e/venv/marker"
cut "$ROOT" '	copy "$1" server "$ext"' 'exit 1'
x -r "$work/cut" update --server xymonapi
x clean --server --all --yes
[ "$(readlink "$link")" = "$d/tasks.cfg" ] || fail "[S31] clean took the task link of one cut short"
[ -L "$work/man/man8/xymonapi.8" ] || fail "[S31] clean took the manual page's link of one cut short"
[ -d "$e/xymon-plugins-dist/plugins/xymonapi" ] || fail "[S31] clean took the staged copy of one cut short"
refused_c() { x clean --server xymonapi; [ "$rc" -ne 0 ] || fail "[S31] clean of one cut short was taken"; }
refused_c
x remove --server xymon-plugin; ok "remove of another beside one cut short"
assert_file_exists "$e/venv/marker"
x update --server xymonapi; ok "update after one cut short"
x install --server xymonapi-mcp; ok "install --server xymonapi-mcp"
cut "$ROOT" '	copy "$1" server "$ext"' '[ "$1" != xymonapi-mcp ] || exit 1'
x -r "$work/cut" update --server xymonapi-mcp
[ -f "$e/xymonapi-mcp/.xymon-plugin-in-progress" ] || fail "xymonapi-mcp was not cut short"
x remove --server xymonapi
[ "$rc" -ne 0 ] || fail "[S3] removing what one cut short needs was taken"
assert_contains "xymonapi is needed by xymonapi-mcp" "$out" "[S3] one cut short blocks the removal of what it needs"
x update --server xymonapi-mcp; ok "update of xymonapi-mcp cut short"
x remove --server xymonapi-mcp; ok "remove xymonapi-mcp"

# Resuming, the refusal of a replaced edited snippet holds: it is looked
# for where the run cut short set it aside too.
v3=$work/v3; copy "$v3"
cp "$v3/plugins/xymonapi/xymonapi-apache.conf" "$v3/plugins/xymonapi/xymonapi-relay-apache.conf"
sed -e 's/^conf: .*/conf: xymonapi-relay-apache.conf xymonapi-nginx.conf xymonapi-lighttpd.conf/' "$ROOT/plugins/xymonapi/PLUGIN" > "$v3/plugins/xymonapi/PLUGIN"
admin; echo "# Require ip 10.0.0.0/8" >> "$d/xymonapi-apache.conf"
cut "$ROOT" '	copy "$1" server "$ext"' 'exit 1'
x -r "$work/cut" update --server xymonapi
x -r "$v3" update --server xymonapi
[ "$rc" -ne 0 ] || fail "[S7] resuming into a version replacing the edited snippet was taken"
assert_contains "$e/.xymon-plugin.xymonapi/xymonapi-apache.conf, which you edited, is no longer shipped: this version's xymonapi-relay-apache.conf replaces it" "$out" "[S7] resuming, the replacement is refused, naming where the edited one is"
x -r "$v3" install --server xymonapi
[ "$rc" -ne 0 ] || fail "[S7] an install resuming into a version replacing the edited snippet was taken"
assert_contains "$e/.xymon-plugin.xymonapi/xymonapi-apache.conf, which you edited" "$out" "[S7] an install resuming refuses it too"
x update --server xymonapi; ok "update back"

# An update of an install from before the PLUGIN copy: the manual page
# it copied into MANDIR takes the link.
admin; rm -f "$d/PLUGIN" "$d/MANIFEST"; rm -f "$work/man/man8/xymonapi.8"; echo "old page" > "$work/man/man8/xymonapi.8"
x update --server xymonapi; ok "update of one from before the PLUGIN copy"
assert_equal "$d/xymonapi.8" "$(readlink "$work/man/man8/xymonapi.8")" "[S20] the page it copied takes the link"

# A task file that is a link to the admin's, of a task a version no
# longer ships: the link goes, said, what it names left; a snippet with no
# copy as written beside it is kept, said not told unedited.
admin; cp "$d/tasks.cfg" "$work/my-tasks.cfg"; rm -f "$d/tasks.cfg"; ln -s "$work/my-tasks.cfg" "$d/tasks.cfg"
rm -f "$d/.shipped/xymonapi-nginx.conf"
x -r "$v2" update --server xymonapi; ok "update to v2, the task file a link"
assert_contains "$d/tasks.cfg, a link to $work/my-tasks.cfg, is no longer shipped: the link is removed, what it names left as it is" "$out" "[S7] the link to the admin's task file is said"
[ -f "$work/my-tasks.cfg" ] || fail "[S7] the file the task link named is gone"
assert_contains "$d/xymonapi-nginx.conf is no longer shipped: it is kept as xymonapi-nginx.conf.old, as it could not be told unedited" "$out" "[S7] a snippet with no copy as written is not said edited"

# cutfirst BASE LINE ACTION -- as cut, ACTION put before the first LINE.
cutfirst() {
	local c=$work/cut
	rm -rf "$c"; copy "$c"; cp "$1/plugins/xymonapi/PLUGIN" "$c/plugins/xymonapi/PLUGIN"
	awk -v l="$2" -v a="$3" '$0 == l && !done { print a; done = 1 } { print }' "$ROOT/plugins/xymon-plugin/xymon-plugin" > "$c/plugins/xymon-plugin/xymon-plugin"
	grep -qxF -- "$3" "$c/plugins/xymon-plugin/xymon-plugin" || fail "the installer has not the line: $2"
}
# waiting FILE -- until FILE is there, at most 60 seconds.
waiting() { i=0; while [ ! -e "$1" ]; do sleep 0.2; i=$((i + 1)); [ "$i" -lt 300 ] || fail "$1 never came"; done; }

# Two runs at once: the second, its check passed before the first wrote
# its file in progress, makes its own only where none is there -- one
# step, with noclobber -- and stops, the first still running.
admin
cutfirst "$ROOT" '	progress "$1"' '	: > "$EXTROOT/waitingB"; while [ ! -e "$EXTROOT/goB" ]; do sleep 0.2; done'
rm -rf "$work/cutB"; mv "$work/cut" "$work/cutB"
cut "$ROOT" '	aside "$1"' '	: > "$EXTROOT/waitingA"; while [ ! -e "$EXTROOT/goA" ]; do sleep 0.2; done'
rm -rf "$work/cutA"; mv "$work/cut" "$work/cutA"
"$work/cutB/xymon-plugin" update --server xymonapi XYMONHOME="$s" MANDIR="$work/man" </dev/null > "$work/B.log" 2>&1 & pb=$!
waiting "$e/waitingB"
"$work/cutA/xymon-plugin" update --server xymonapi XYMONHOME="$s" MANDIR="$work/man" </dev/null > "$work/A.log" 2>&1 & pa=$!
waiting "$e/waitingA"
: > "$e/goB"; rcb=0; wait "$pb" || rcb=$?
[ "$rcb" -ne 0 ] || fail "[S20] a second run at once was taken: $(cat "$work/B.log")"
assert_contains "an install or update of xymonapi is running, process $pa" "$(cat "$work/B.log")" "[S20] the second run says the first runs"
: > "$e/goA"; rca=0; wait "$pa" || rca=$?
[ "$rca" -eq 0 ] || fail "[S20] the first run failed: $(cat "$work/A.log")"
rm -f "$e/waitingA" "$e/waitingB" "$e/goA" "$e/goB"
kept "two runs at once" v1

# The file in progress is never written through: a link there, or a hard
# link to a file outside, is replaced, the file it names untouched.
admin; echo precious > "$work/victim"; echo precious > "$work/victim2"
ln -s "$work/victim" "$d/.xymon-plugin-in-progress"
x update --server xymonapi; ok "update, a link in place of the file in progress"
assert_equal precious "$(cat "$work/victim")" "[S20] the file in progress was written through a link"
ln "$work/victim2" "$d/.xymon-plugin-in-progress"
x update --server xymonapi; ok "update, a hard link in place of the file in progress"
assert_equal precious "$(cat "$work/victim2")" "[S20] the file in progress was written through a hard link"

# NAME.old of every kind: hidden, in a directory, a link, a directory
# named so, names with a backslash or a leading dash -- each kept through
# an update and through one cut short and resumed; verify says each kept.
admin
printf 'k1\n' > "$d/.hidden.old"; mkdir "$d/dir.old"; echo k2 > "$d/dir.old/f"
mkdir -p "$d/sub"; echo k3 > "$d/sub/x.old"; ln -s /elsewhere "$d/lnk.old"
printf 'k4\n' > "$d/a\\tb.old"; printf 'k5\n' > "$d/-n.old"
oldsok() {
	assert_equal k1 "$(cat "$d/.hidden.old")" "[S7] $1: a hidden .old is kept"
	assert_equal k2 "$(cat "$d/dir.old/f")" "[S7] $1: a directory named .old is kept whole"
	assert_equal k3 "$(cat "$d/sub/x.old")" "[S7] $1: a .old in a directory is kept"
	assert_equal /elsewhere "$(readlink "$d/lnk.old")" "[S7] $1: a link named .old is kept as a link"
	assert_equal k4 "$(cat "$d/a\\tb.old")" "[S7] $1: a .old with a backslash is kept"
	assert_equal k5 "$(cat "$d/-n.old")" "[S7] $1: a .old with a leading dash is kept"
}
x update --server xymonapi; ok "update with .old files of every kind"
oldsok "an update"
cut "$ROOT" '	copy "$1" server "$ext"' 'exit 1'
x -r "$work/cut" update --server xymonapi
x update --server xymonapi; ok "update after one cut short, .old files of every kind"
oldsok "a resume"
x verify --server xymonapi
for f in .hidden.old dir.old/f sub/x.old lnk.old; do
	assert_contains "untidy: xymonapi: $f, yours, kept by an update" "$out" "[S30] verify says $f kept"
done
grep -q '\.old' "$d/MANIFEST" && fail "[S29] MANIFEST names a .old"

# A resume says to reload the web server: a snippet may have changed
# before the cut.
admin; cut "$ROOT" '	conf "$1"' 'exit 1'
x -r "$work/cut" update --server xymonapi
x update --server xymonapi; ok "update after one cut short after conf"
assert_contains "reload the web server" "$out" "[S16] the resume says to reload the web server"
x status --server xymonapi
assert_not_contains "cut short" "$out" "[S15] status of one resumed"

# status says one cut short.
admin; cut "$ROOT" '	copy "$1" server "$ext"' 'exit 1'
x -r "$work/cut" update --server xymonapi
x status --server xymonapi
assert_contains "xymonapi: cut short: ./xymon-plugin update --server xymonapi resumes it" "$out" "[S15] status says one cut short"
x update --server xymonapi; ok "update after one cut short"

# An install of a plugin needing it resumes one cut short, VERSION still
# there: not passed over as installed.
admin; cut "$ROOT" '	aside "$1"' 'exit 1'
x -r "$work/cut" update --server xymonapi
assert_file_exists "$d/VERSION"
x install --server xymonapi-mcp; ok "install of one needing it, it cut short"
kept "a need cut short, resumed by the install needing it" v1
x remove --server xymonapi-mcp; ok "remove xymonapi-mcp"

# The copies as the install before wrote them, set aside, are the ones a
# resume meets the files with: one at that name in the directory since
# does not take their place. Unedited, both are replaced by this version's.
vn=$work/vn; copy "$vn"; echo "# newer task" >> "$vn/plugins/xymonapi/xymonapi.tasks.DIST"; echo "# newer nginx" >> "$vn/plugins/xymonapi/xymonapi-nginx.conf"
x remove --server xymonapi; x install --server xymonapi; ok "install --server"
cut "$vn" '	fresh "$ext" "$keep" || exit 1' 'exit 1'
x -r "$work/cut" update --server xymonapi
mkdir -p "$d/.shipped"; echo "# not as written" > "$d/.shipped/tasks.cfg"; echo "# not as written" > "$d/.shipped/xymonapi-nginx.conf"
x -r "$vn" update --server xymonapi; ok "resume with copies at the .shipped names"
assert_contains "$d/tasks.cfg, unedited, is replaced by this version's" "$out" "[S7] the task file is met with the copy set aside"
assert_contains "$d/xymonapi-nginx.conf, unedited, is replaced by this version's" "$out" "[S7] the snippet is met with the copy set aside"

# A first install cut short, nothing set aside: remove takes it.
x remove --server xymonapi
cut "$ROOT" '	aside "$1"' 'exit 1'
x -r "$work/cut" install --server xymonapi
[ -f "$d/.xymon-plugin-in-progress" ] || fail "the first install was not cut short"
x remove --server xymonapi; ok "remove of a first install cut short"
[ ! -e "$d" ] && [ ! -e "$e/.xymon-plugin.xymonapi" ] || fail "[S20] remove of a first install cut short left it"
# Resumed and cut short again, still a first install's.
x -r "$work/cut" install --server xymonapi
cut "$ROOT" '	conf "$1"' 'exit 1'
x -r "$work/cut" install --server xymonapi
[ "$rc" -ne 0 ] || fail "the resumed first install was not cut short"
x remove --server xymonapi; ok "remove of a first install cut short twice"
# An update cut short once all is put back, VERSION not yet written,
# nothing set aside: its files are the admin's, remove refuses it.
admin; cut "$ROOT" '	aside_back' 'exit 1'
x -r "$work/cut" update --server xymonapi
[ ! -e "$d/VERSION" ] && [ ! -e "$e/.xymon-plugin.xymonapi" ] || fail "the cut did not come after all was put back, before VERSION"
x remove --server xymonapi
[ "$rc" -ne 0 ] || fail "[S20] remove took an update cut short with the admin's files back in place"
x update --server xymonapi; ok "update after one cut short after all was put back"
kept "an update cut short after all was put back" v1
x remove --server xymonapi; ok "remove --server"

# Cut after fresh, the PLUGIN copy kept: the resume knows what the
# install before put in place -- its SELinux module, which this version
# has not, goes.
mkdir -p "$work/sebin"; printf '#!/bin/sh\nexit 0\n' > "$work/sebin/selinuxenabled"
printf '#!/bin/sh\necho "$*" >> %s/semodule.log\n' "$work" > "$work/sebin/semodule"; chmod 755 "$work/sebin/selinuxenabled" "$work/sebin/semodule"
nosel=$work/nosel; copy "$nosel"; sed -e '/^selinux: /d' "$ROOT/plugins/xymonapi/PLUGIN" > "$nosel/plugins/xymonapi/PLUGIN"
PATH="$work/sebin:$PATH" x install --server xymonapi; ok "install with SELinux"
cut "$nosel" '	fresh "$ext" "$keep" || exit 1' 'exit 1'
: > "$work/semodule.log"
PATH="$work/sebin:$PATH" x -r "$work/cut" update --server xymonapi
PATH="$work/sebin:$PATH" x -r "$nosel" update --server xymonapi; ok "resume to a version without the module"
assert_contains "-r xymonapi" "$(cat "$work/semodule.log")" "[S23] the resume removes the module the install before loaded"
x remove --server xymonapi

pass "an install or update cut short, by a failure or SIGTERM, at each point, keeps the admin's files in its marked directory, said; the next update or install resumes with them, every one back or, no longer shipped, kept as .old, the directory gone, no removal by hand advised"
