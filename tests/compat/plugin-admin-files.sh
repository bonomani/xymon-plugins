#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-admin-files.sh
#
# What is the administrator's stays so through install, update and removal.
# A manual page's name in MANDIR that is not free -- a page of the admin's,
# another's link, a directory -- is left as it is, said, for the server and
# the tools parts, the install going on; this plugin's own link is made and
# kept. So is a command's name in $PREFIX/bin, ours written and replaced,
# an older version's for another script among them, and the only one a
# removal takes. An update to a version that no longer ships a snippet or
# the task file keeps an edited one as NAME.old, said, out of the include
# lines' reach, the task's link removed; an unedited one goes, nothing said; an
# edited snippet replaced by another for the same web server refuses the
# update before anything changes, for a plugin named or one needing it,
# until it is moved out. Removing a plugin whose directory is gone takes
# its task link into it, leaves a file at that name, said, and no SELinux
# module. What an update sets aside goes in a directory of its own, gone
# once it ends: files already in ext/ at the names an older install used,
# and another's .xymon-plugin.* there, stay byte for byte, and are no
# plugin's for verify, update or clean. One cut short keeps it, said, and
# the next update resumes with it: only a marked one of this plugin's, a
# real directory, the person running's, the newest, and only to resume:
# beside a complete install one is stale, said and untouched, verify
# untidy; another user's is named; what it cannot put back keeps it. (plugin-resume.sh cuts one
# short at each point.)
#
# A scratch server tree and prefix; copies of the checkout play the newer
# versions; selinuxenabled and semodule are stand-ins recording their calls.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
unset MAN SUDO_USER
export HOME="$work/home" XDG_CONFIG_HOME="$work/cfg" XYMON_PLUGINS_TREES_ONLY=1 XYMON_PLUGINS_TREES=
mkdir -p "$HOME" "$work/man" "$work/bin"
# SELinux active only as $work/enabled says: for the removals of part 3.
echo 1 > "$work/enabled"
printf '#!/bin/sh\nexit "$(cat %s/enabled)"\n' "$work" > "$work/bin/selinuxenabled"
printf '#!/bin/sh\necho "$*" >> %s/semodule.log\n' "$work" > "$work/bin/semodule"
chmod 755 "$work/bin/selinuxenabled" "$work/bin/semodule"
export PATH="$work/bin:$PATH"

s=$work/server
server_tree "$s"
e=$s/ext d=$e/xymonapi m8=$work/man/man8

# copy DIR -- a copy of the checkout at DIR, a version to edit.
copy() { mkdir -p "$1"; cp -R "$ROOT/xymon-plugin" "$ROOT/LICENSE" "$ROOT/plugins" "$1/"; }
# edit DIR SED -- DIR's xymonapi PLUGIN file, through SED.
edit() { sed -e "$2" "$1/plugins/xymonapi/PLUGIN" > "$work/PLUGIN.e" && mv "$work/PLUGIN.e" "$1/plugins/xymonapi/PLUGIN"; }
# v2 ships neither the nginx nor the lighttpd snippet, nor a task.
v2=$work/v2; copy "$v2"; edit "$v2" 's/^conf: .*/conf: xymonapi-apache.conf/; /^task: /d'
# v3 ships xymonapi-relay-apache.conf in place of xymonapi-apache.conf.
v3=$work/v3; copy "$v3"
cp "$v3/plugins/xymonapi/xymonapi-apache.conf" "$v3/plugins/xymonapi/xymonapi-relay-apache.conf"
edit "$v3" 's/^conf: .*/conf: xymonapi-relay-apache.conf xymonapi-nginx.conf xymonapi-lighttpd.conf/'

# x [-r REPO] ARG... -- REPO's xymon-plugin ARG..., the checkout's by
# default, on the scratch server and prefix, off a terminal.
x() {
	local r=$ROOT; if [ "$1" = -r ]; then r=$2; shift 2; fi
	rc=0; out=$("$r/xymon-plugin" "$@" XYMONHOME="$s" MANDIR="$work/man" PREFIX="$work/prefix" </dev/null 2>&1) || rc=$?
}
ok() { [ "$rc" -eq 0 ] || fail "$1 failed: $out"; }
snap() { find "$work" -mindepth 1 \( -path "$work/snap*" -o -path "$work/semodule.log" \) -prune -o -print | sort > "$work/$1"; }
# state FILE -- every path, its mode, each file's cksum, each link's target.
state() {
	snap "$1.p"
	while IFS= read -r p; do
		md=$(ls -ldn "$p" | awk '{ print $1 }')
		if [ -L "$p" ]; then printf '%s -> %s\n' "$p" "$(readlink "$p")"
		elif [ -f "$p" ]; then printf '%s %s %s\n' "$p" "$md" "$(cksum < "$p")"
		else printf '%s %s\n' "$p" "$md"; fi
	done < "$work/$1.p" > "$work/$1"
}

# 1. Manual pages. The server part: a page of the admin's at the name.
echo mine > "$work/page"; mkdir -p "$m8"; cp "$work/page" "$m8/xymonapi.8"
another="$work/man/man8/xymonapi.8 is another's, left as it is: xymonapi's manual page is read as man $d/xymonapi.8"
x install --server xymonapi; ok "install --server beside the admin's page"
assert_contains "$another" "$out" "[S20] install: the admin's page at the name is said"
cmp -s "$work/page" "$m8/xymonapi.8" || fail "[S20] install replaced the admin's page"
grep -q "man8/xymonapi.8" "$d/MANIFEST" && fail "[S29] MANIFEST names the admin's page"
x update --server xymonapi; ok "update --server beside the admin's page"
assert_contains "$another" "$out" "[S20] update: the admin's page at the name is said"
cmp -s "$work/page" "$m8/xymonapi.8" || fail "[S20] update replaced the admin's page"
# Another's link, then a directory.
rm -f "$m8/xymonapi.8"; ln -s /elsewhere/xymonapi.8 "$m8/xymonapi.8"
x update --server xymonapi; ok "update --server beside another's link"
assert_contains "$another" "$out" "[S20] update: another's link at the name is said"
assert_equal /elsewhere/xymonapi.8 "$(readlink "$m8/xymonapi.8")" "[S20] update: another's link is left as it is"
grep -q "man8/xymonapi.8" "$d/MANIFEST" && fail "[S29] MANIFEST names another's link"
rm -f "$m8/xymonapi.8"; mkdir "$m8/xymonapi.8"
x update --server xymonapi; ok "update --server beside a directory at the page's name"
assert_contains "$another" "$out" "[S20] update: a directory at the name is said"
[ -d "$m8/xymonapi.8" ] && [ ! -L "$m8/xymonapi.8" ] || fail "[S20] update: the directory at the page's name is gone"
# The name free: linked, and kept so, said of nothing.
rmdir "$m8/xymonapi.8"
x update --server xymonapi; ok "update --server, the page's name free"
assert_equal "$d/xymonapi.8" "$(readlink "$m8/xymonapi.8")" "[S20] the page's name free, the update links it"
x update --server xymonapi; ok "update --server, the link ours"
assert_equal "$d/xymonapi.8" "$(readlink "$m8/xymonapi.8")" "[S20] the link ours, kept"
assert_not_contains "another's" "$out" "[S20] the link ours is not said another's"
grep -q "man8/xymonapi.8	$d/xymonapi.8" "$d/MANIFEST" || fail "[S29] MANIFEST does not name the link ours"
x remove --server xymonapi; ok "remove --server"
# The tools part, the same.
m1=$work/prefix/share/man/man1
mkdir -p "$m1"; cp "$work/page" "$m1/xymonapi-connect.1"
tanother="$m1/xymonapi-connect.1 is another's, left as it is: xymonapi's manual page is read as man $work/prefix/libexec/xymon-plugins/xymonapi/xymonapi-connect.1"
x install --tools xymonapi; ok "install --tools beside the admin's page"
assert_contains "$tanother" "$out" "[S20] install --tools: the admin's page at the name is said"
cmp -s "$work/page" "$m1/xymonapi-connect.1" || fail "[S20] install --tools replaced the admin's page"
grep -q "man1/xymonapi-connect.1" "$work/prefix/libexec/xymon-plugins/xymonapi/MANIFEST" && fail "[S29] the tools' MANIFEST names the admin's page"
rm -f "$m1/xymonapi-connect.1"; ln -s /elsewhere/xymonapi-connect.1 "$m1/xymonapi-connect.1"
x update --tools xymonapi; ok "update --tools beside another's link"
assert_contains "$tanother" "$out" "[S20] update --tools: another's link at the name is said"
assert_equal /elsewhere/xymonapi-connect.1 "$(readlink "$m1/xymonapi-connect.1")" "[S20] update --tools: another's link is left as it is"
grep -q "man1/xymonapi-connect.1" "$work/prefix/libexec/xymon-plugins/xymonapi/MANIFEST" && fail "[S29] the tools' MANIFEST names another's link"
rm -f "$m1/xymonapi-connect.1"
x update --tools xymonapi; ok "update --tools, the page's name free"
assert_equal "$work/prefix/libexec/xymon-plugins/xymonapi/xymonapi-connect.1" "$(readlink "$m1/xymonapi-connect.1")" "[S20] update --tools links the page's name free"
# A .old in the tools' directory goes with the next update: verify does
# not say an update keeps it.
echo mine > "$work/prefix/libexec/xymon-plugins/xymonapi/notes.old"
x verify --tools xymonapi
assert_not_contains "kept by an update" "$out" "[S30] verify --tools does not say a .old is kept by an update"
x remove --tools xymonapi; ok "remove --tools"
# Its part not there, a page of someone's at its name stays.
mkdir -p "$m1"; echo "someone's page" > "$m1/xymonapi-connect.1"
x remove --tools xymonapi; ok "remove --tools of a part not there"
assert_equal "someone's page" "$(cat "$m1/xymonapi-connect.1")" "[S20] removing a tools part not there took a page at its name"
rm -f "$m1/xymonapi-connect.1"

# The command in $PREFIX/bin, the same: a command of the person's, or a
# link, at its name is left as it is, said, and out of MANIFEST; ours is
# written, replaced by an update, and the only one a removal takes.
b=$work/prefix/bin lx=$work/prefix/libexec/xymon-plugins/xymonapi
mkdir -p "$b"; printf '#!/bin/sh\necho mine\n' > "$work/cmd"; cp "$work/cmd" "$b/xymonapi-connect"
# wrapper_of SCRIPT -- the command an install writes for xymonapi's SCRIPT.
wrapper_of() { printf '#!/bin/sh\nexec "%s/%s" "$@"\n' "$lx" "$1"; }
canother="$b/xymonapi-connect is another's, left as it is: run xymonapi's command as $lx/xymonapi-connect.sh"
x install --tools xymonapi; ok "install --tools beside the person's command"
assert_contains "$canother" "$out" "[S4] install --tools: the person's command at the name is said"
cmp -s "$work/cmd" "$b/xymonapi-connect" || fail "[S4] install --tools replaced the person's command"
grep -q "bin/xymonapi-connect" "$lx/MANIFEST" && fail "[S29] the tools' MANIFEST names the person's command"
x update --tools xymonapi; ok "update --tools beside the person's command"
assert_contains "$canother" "$out" "[S4] update --tools: the person's command at the name is said"
cmp -s "$work/cmd" "$b/xymonapi-connect" || fail "[S4] update --tools replaced the person's command"
grep -q "bin/xymonapi-connect" "$lx/MANIFEST" && fail "[S29] the tools' MANIFEST names the person's command after an update"
rm -f "$b/xymonapi-connect"; ln -s /elsewhere/xymonapi-connect "$b/xymonapi-connect"
x update --tools xymonapi; ok "update --tools beside another's link"
assert_contains "$canother" "$out" "[S4] update --tools: another's link at the command's name is said"
assert_equal /elsewhere/xymonapi-connect "$(readlink "$b/xymonapi-connect")" "[S4] update --tools: another's link at the command's name is left as it is"
grep -q "bin/xymonapi-connect" "$lx/MANIFEST" && fail "[S29] the tools' MANIFEST names another's link at the command's name"
# A link is another's even to a file holding the command ours, byte for byte.
rm -f "$b/xymonapi-connect"
wrapper_of xymonapi-connect.sh > "$work/ourcopy"; ln -s "$work/ourcopy" "$b/xymonapi-connect"
x update --tools xymonapi; ok "update --tools beside a link to a copy of its command"
assert_contains "$canother" "$out" "[S4] update --tools: a link to a copy of its command is said another's"
assert_equal "$work/ourcopy" "$(readlink "$b/xymonapi-connect")" "[S4] update --tools: a link to a copy of its command is left as it is"
rm -f "$b/xymonapi-connect"; mkdir "$b/xymonapi-connect"
x update --tools xymonapi; ok "update --tools beside a directory at the command's name"
assert_contains "$canother" "$out" "[S4] update --tools: a directory at the command's name is said"
[ -d "$b/xymonapi-connect" ] || fail "[S4] update --tools: the directory at the command's name is gone"
rmdir "$b/xymonapi-connect"
ours=$(wrapper_of xymonapi-connect.sh; echo x)
x update --tools xymonapi; ok "update --tools, the command's name free"
assert_equal "$ours" "$(cat "$b/xymonapi-connect"; echo x)" "[S4] update --tools writes the command at its name free"
assert_not_contains "is another's" "$out" "[S4] the name free is not said another's"
grep -q "file	.*	$work/prefix/bin/xymonapi-connect\$" "$lx/MANIFEST" || fail "[S29] MANIFEST does not name the command ours"
x update --tools xymonapi; ok "update --tools over its own command"
assert_equal "$ours" "$(cat "$b/xymonapi-connect"; echo x)" "[S4] update --tools keeps writing its own command"
assert_not_contains "is another's" "$out" "[S4] the command ours is not said another's"
# A newer version runs another script under the same name: its update
# replaces the older version's command, and the older one's update the newer's.
v4=$work/v4; copy "$v4"; cp "$v4/plugins/xymonapi/xymonapi-connect.sh" "$v4/plugins/xymonapi/xymonapi-connect2.sh"
edit "$v4" 's/^version: .*/version: 99.0.0/; s/^command: xymonapi-connect .*/command: xymonapi-connect xymonapi-connect2.sh/; s/^\(tools-files: .*\)/\1 xymonapi-connect2.sh/; s/^\(executable: .*\)/\1 xymonapi-connect2.sh/'
x -r "$v4" update --tools xymonapi; ok "update --tools to a version with another wrapper"
assert_equal "$(wrapper_of xymonapi-connect2.sh; echo x)" "$(cat "$b/xymonapi-connect"; echo x)" "[S4] an update did not replace the older version's command"
assert_not_contains "is another's" "$out" "[S4] the older version's command is not said another's"
x update --tools xymonapi; ok "update --tools back from the version with another wrapper"
assert_equal "$ours" "$(cat "$b/xymonapi-connect"; echo x)" "[S4] an update did not replace the other version's command"
x remove --tools xymonapi; ok "remove --tools, the command ours"
[ -e "$b/xymonapi-connect" ] && fail "[S20] remove --tools left its own command"
cp "$work/cmd" "$b/xymonapi-connect"
x install --tools xymonapi; ok "install --tools beside the person's command, again"
x remove --tools xymonapi; ok "remove --tools beside the person's command"
cmp -s "$work/cmd" "$b/xymonapi-connect" || fail "[S20] remove --tools took the person's command"
rm -f "$b/xymonapi-connect"

# 2. Files a newer version no longer ships: the edited nginx snippet and
# task kept as .old, said; the unedited lighttpd snippet gone, silent.
x install --server xymonapi; ok "install --server"
x enable --server xymonapi; ok "enable --server"
echo "# the admin's nginx" >> "$d/xymonapi-nginx.conf"; cp "$d/xymonapi-nginx.conf" "$work/nginx.kept"
echo "# the admin's task" >> "$d/tasks.cfg"; cp "$d/tasks.cfg" "$work/task.kept"
x -r "$v2" update --server xymonapi; ok "update to a version without them"
assert_contains "$d/xymonapi-nginx.conf is no longer shipped: your edited copy is kept as xymonapi-nginx.conf.old" "$out" "[S7] a dropped edited snippet is said kept"
cmp -s "$work/nginx.kept" "$d/xymonapi-nginx.conf.old" || fail "[S7] the dropped edited snippet is not kept as .old"
assert_contains "$d/tasks.cfg is no longer shipped: your edited copy is kept as tasks.cfg.old" "$out" "[S7] a dropped edited task file is said kept"
cmp -s "$work/task.kept" "$d/tasks.cfg.old" || fail "[S7] the dropped edited task file is not kept as tasks.cfg.old"
[ -e "$s/etc/tasks.d/xymonapi.cfg" ] || [ -L "$s/etc/tasks.d/xymonapi.cfg" ] && fail "[S20] the dropped task's link is left"
for f in xymonapi-nginx.conf xymonapi-lighttpd.conf tasks.cfg; do [ ! -e "$d/$f" ] || fail "[S7] $f, no longer shipped, is left"; done
[ ! -e "$d/xymonapi-lighttpd.conf.old" ] || fail "[S7] the unedited dropped snippet was kept"
assert_not_contains "lighttpd.conf is no longer shipped" "$out" "[S7] the unedited dropped snippet goes, nothing said"
grep -q '\.old' "$d/MANIFEST" && fail "[S29] MANIFEST names a .old"
x verify --server xymonapi
[ "$rc" -eq 4 ] || fail "[S30] verify with a .old kept exited $rc, not 4: $out"
assert_contains "untidy: xymonapi: xymonapi-nginx.conf.old, yours, kept by an update" "$out" "[S30] verify says the .old kept"
assert_contains "untidy: xymonapi: tasks.cfg.old, yours, kept by an update" "$out" "[S30] verify says the task's .old kept"
# A .old stays through the updates after, until the admin removes it.
x -r "$v2" update --server xymonapi; ok "a second update to the version without them"
cmp -s "$work/nginx.kept" "$d/xymonapi-nginx.conf.old" && cmp -s "$work/task.kept" "$d/tasks.cfg.old" \
	|| fail "[S7] a .old an update kept is gone after the next update"
# Another kept for the same file: the one there before is renamed, not lost.
x update --server xymonapi; ok "update back to the version with them"
echo "# the admin's nginx, again" >> "$d/xymonapi-nginx.conf"; cp "$d/xymonapi-nginx.conf" "$work/nginx2.kept"
x -r "$v2" update --server xymonapi; ok "update without them again"
cmp -s "$work/nginx2.kept" "$d/xymonapi-nginx.conf.old" || fail "[S7] the newer edited snippet is not the .old"
cmp -s "$work/nginx.kept" "$d/xymonapi-nginx.conf.1.old" || fail "[S7] the .old there before was not kept as .1.old"
x verify --server xymonapi
assert_contains "untidy: xymonapi: xymonapi-nginx.conf.1.old, yours, kept by an update" "$out" "[S30] verify says the older .old"
# The include lines the install gives end in .conf: a .old is no match.
for g in 'xymonapi-nginx*.conf' 'xymonapi-lighttpd*.conf' 'xymonapi-apache.conf'; do
	# shellcheck disable=SC2254 # the include's pattern, as a glob
	for o in xymonapi-nginx.conf.old xymonapi-lighttpd.conf.old xymonapi-apache.conf.old; do case $o in $g) fail "[S7] $g, an include the install gives, matches a .old" ;; esac; done
done
x remove --server xymonapi; ok "remove --server"
# Unedited, the task file goes too, nothing said; and a snippet with no
# copy in .shipped/, as an older install left it, known unedited by a
# conf-stock line of the installed version's alone.
x install --server xymonapi; ok "install --server"
rm -f "$d/.shipped/xymonapi-lighttpd.conf"
printf 'conf-stock: xymonapi-lighttpd.conf %s\n' "$(sed -e "s|$s|@XYMONHOME@|g" "$d/xymonapi-lighttpd.conf" | cksum | cut -d' ' -f1,2)" >> "$d/PLUGIN"
x -r "$v2" update --server xymonapi; ok "update to a version without them, nothing edited"
assert_not_contains "no longer shipped" "$out" "[S7] unedited dropped files go, nothing said"
for f in tasks.cfg.old xymonapi-nginx.conf.old xymonapi-lighttpd.conf.old; do [ ! -e "$d/$f" ] || fail "[S7] unedited, $f was kept"; done
x remove --server xymonapi; ok "remove --server"

# The edited apache snippet, replaced by xymonapi-relay-apache.conf: refused
# before anything changes, named, the plugin needing it updated or all.
x install --server xymonapi-mcp; ok "install --server xymonapi-mcp"
# Unedited, it is replaced, not refused.
x -r "$v3" update --server xymonapi; ok "update replacing an unedited snippet"
x update --server xymonapi; ok "update back"
echo "# the admin's restriction" >> "$d/xymonapi-apache.conf"; cp "$d/xymonapi-apache.conf" "$work/apache.kept"
for a in "xymonapi" "xymonapi-mcp" ""; do
	state snap-r0
	# shellcheck disable=SC2086 # no name: update all
	x -r "$v3" update --server $a
	[ "$rc" -ne 0 ] || fail "[S7] update ${a:-all} replacing an edited snippet was taken: $out"
	assert_contains "$d/xymonapi-apache.conf, which you edited, is no longer shipped: this version's xymonapi-relay-apache.conf replaces it" "$out" "[S7] update ${a:-all}: the refusal names both"
	assert_contains "Move $d/xymonapi-apache.conf away, run the update again" "$out" "[S7] update ${a:-all}: the refusal says how to clear it"
	state snap-r1
	cmp -s "$work/snap-r0" "$work/snap-r1" || fail "[S7] update ${a:-all}: the refusal changed something: $(diff "$work/snap-r0" "$work/snap-r1" || :)"
done
mv "$d/xymonapi-apache.conf" "$work/apache.mine"
x -r "$v3" update --server xymonapi; ok "update once the edited snippet is moved out"
assert_file_exists "$d/xymonapi-relay-apache.conf"
[ ! -e "$d/xymonapi-apache.conf" ] && [ ! -e "$d/xymonapi-apache.conf.old" ] || fail "[S7] the moved snippet came back"
x remove --server xymonapi-mcp xymonapi; ok "remove --server"

# 3. Removing a plugin whose directory is gone.
echo 0 > "$work/enabled"; : > "$work/semodule.log"
mkdir -p "$s/etc/tasks.d"; ln -s "$d/tasks.cfg" "$s/etc/tasks.d/xymonapi.cfg"
x remove --server xymonapi; ok "remove of a plugin gone, its task link left"
[ -L "$s/etc/tasks.d/xymonapi.cfg" ] && fail "[S20] the task link into the plugin's directory gone is left"
echo mytask > "$s/etc/tasks.d/xymonapi.cfg"
x remove --server xymonapi; ok "remove of a plugin gone, a task file at the link's name"
assert_equal mytask "$(cat "$s/etc/tasks.d/xymonapi.cfg")" "[S20] a file at the task link's name, the plugin gone, is left"
assert_contains "$s/etc/tasks.d/xymonapi.cfg is left as it is: xymonapi is not installed" "$out" "[S20] and said"
assert_equal "" "$(cat "$work/semodule.log")" "[S23] removing a plugin gone removes no SELinux module"
rm -f "$s/etc/tasks.d/xymonapi.cfg"
x install --server xymonapi; ok "install --server"
: > "$work/semodule.log"
x remove --server xymonapi; ok "remove --server"
assert_equal "-r xymonapi" "$(cat "$work/semodule.log")" "[S23] removing an install removes its SELinux module"
echo 1 > "$work/enabled"

# 4. What an update sets aside: in a directory of its own. Files at the
# names an older install used, and another's .xymon-plugin.* holding what
# would make it a plugin's, stay byte for byte.
x install --server xymonapi; ok "install --server"
x enable --server xymonapi; ok "enable --server"
echo "# the admin's" >> "$d/xymonapi-nginx.conf"
echo old-task > "$e/.xymonapi.tasks.cfg"; echo old-snippet > "$e/.xymonapi.xymonapi-nginx.conf"
echo old-shipped > "$e/.xymonapi.tasks.cfg.shipped"
mkdir -p "$e/.xymon-plugin.theirs"; echo 1.0.0 > "$e/.xymon-plugin.theirs/VERSION"
printf 'name: .xymon-plugin.theirs\nserver-files: run\n' > "$e/.xymon-plugin.theirs/PLUGIN"
ln -s /elsewhere "$e/.xymon-plugin.link"
theirs() { state "$1"; grep -e "^$e/\.xymonapi\." -e "^$e/\.xymon-plugin\." "$work/$1" > "$work/$1.f" || :; }
theirs snap-a0
# ours_left -- the .xymon-plugin.* in ext/ that are not the planted ones.
ours_left() {
	for f in "$e"/.xymon-plugin.*; do
		case ${f##*/} in .xymon-plugin.theirs|.xymon-plugin.link) ;; *) [ ! -e "$f" ] || echo "$f" ;; esac
	done
}
x update --server xymonapi; ok "update beside files at the names an older install used"
x -r "$v2" update --server; ok "update, none named, to a version without the nginx snippet"
x verify --server
assert_not_contains ".xymon-plugin." "$out" "[S7] verify reads no .xymon-plugin.* as a plugin"
x clean --server --all --yes
assert_not_contains ".xymon-plugin." "$out" "[S7] clean reads no .xymon-plugin.* as a plugin"
theirs snap-a1
cmp -s "$work/snap-a0.f" "$work/snap-a1.f" || fail "[S7] an update changed what lies in ext/ at the names an older install used: $(diff "$work/snap-a0.f" "$work/snap-a1.f" || :)"
[ -z "$(ours_left)" ] || fail "[S28] the update left the directory it set files aside in: $(ours_left)"
assert_file_exists "$d/xymonapi-nginx.conf.old"
# Back to this version, the apache snippet edited too.
echo "# the admin's" >> "$d/xymonapi-apache.conf"; cp "$d/xymonapi-apache.conf" "$work/apache.kept"
x update --server xymonapi; ok "update back to this version"
cmp -s "$work/apache.kept" "$d/xymonapi-apache.conf" || fail "[S7] the edited snippet was not kept"
theirs snap-a2
cmp -s "$work/snap-a0.f" "$work/snap-a2.f" || fail "[S7] an update changed what lies in ext/: $(diff "$work/snap-a0.f" "$work/snap-a2.f" || :)"
[ -z "$(ours_left)" ] || fail "[S28] the update left the directory it set files aside in: $(ours_left)"
# An update that fails once files are set aside keeps them, said, in
# ext/.xymon-plugin.xymonapi, the plugin's directory cut short: remove
# refuses it, another user's update too; the next update resumes, every
# file back, the directory and the file in progress gone. A file changed
# since the cut is kept as a .old, said, never over the one set aside.
sa=$e/.xymon-plugin.xymonapi
x enable --server xymonapi; ok "enable --server"
echo "# the admin's task" >> "$d/tasks.cfg"; cp "$d/tasks.cfg" "$work/task.kept"
plugin_of() { mkdir -p "$1"; printf 'xymon-plugin set aside: %s\ndate: 2026-01-02 03:04\n' "$2" > "$1/.xymon-plugin-set-aside"; }
plugin_of "$e/.xymon-plugin.other" xymonapi-rag; echo theirs > "$e/.xymon-plugin.other/tasks.cfg"
echo "xymonapi" > "$e/.xymon-plugin.theirs/tasks.cfg"
theirs snap-a3
v4=$work/v4; copy "$v4"; ln -sf xymon.py "$v4/plugins/xymonapi/app.py"
cutshort() {
	x -r "$v4" update --server xymonapi
	[ "$rc" -ne 0 ] || fail "an update with a plugin file a link was taken: $out"
	assert_contains "set aside in $sa: the next install or update of xymonapi resumes, and puts them back" "$out" "[S7] the failed update says where what it set aside is"
	assert_file_exists "$d/.xymon-plugin-in-progress"
}
cutshort
cmp -s "$work/apache.kept" "$sa/xymonapi-apache.conf" || fail "[S7] the failed update did not keep the edited snippet"
cmp -s "$work/task.kept" "$sa/tasks.cfg" || fail "[S7] the failed update did not keep the edited task file"
assert_file_exists "$sa/xymonapi-nginx.conf.old"
refused() {
	local l=$1 w=$2; shift 2
	state snap-r0
	x "$@"
	[ "$rc" -ne 0 ] || fail "[S7] $l: was taken: $out"
	assert_contains "$w" "$out" "[S7] $l: refused, saying so"
	state snap-r1
	cmp -s "$work/snap-r0" "$work/snap-r1" || fail "[S7] $l: the refusal changed something: $(diff "$work/snap-r0" "$work/snap-r1" || :)"
}
refused "removing an install cut short" "$d is an install of xymonapi's server part cut short: ./xymon-plugin update --server xymonapi resumes it" remove --server xymonapi
mkdir -p "$work/otherid"; printf '#!/bin/sh\n[ "$1" = -u ] && { echo 4242; exit; }\nexec %s "$@"\n' "$(command -v id)" > "$work/otherid/id"; chmod 755 "$work/otherid/id"
PATH="$work/otherid:$PATH" refused "another user's update" "$sa, set aside by an install of xymonapi cut short, is $(id -un)'s: left as it is; an install or update of xymonapi by that user resumes it" update --server xymonapi
x update --server xymonapi; ok "update after one cut short"
assert_contains "Resuming the install of xymonapi cut short, with what it set aside in $sa" "$out" "[S7] the update says it resumes"
cmp -s "$work/apache.kept" "$d/xymonapi-apache.conf" || fail "[S7] the edited snippet set aside was not put back"
cmp -s "$work/task.kept" "$d/tasks.cfg" || fail "[S7] the edited task file set aside was not put back"
assert_equal "$d/tasks.cfg" "$(readlink "$s/etc/tasks.d/xymonapi.cfg")" "[S13] the task put back is on, as it was"
assert_file_exists "$d/xymonapi-nginx.conf.old"
[ ! -e "$sa" ] && [ ! -e "$d/.xymon-plugin-in-progress" ] || fail "[S7] the set-aside directory or the file in progress is left"
# Changed after the cut: kept as a .old, said; the one set aside is back.
cutshort
echo "# changed after the cut" >> "$d/tasks.cfg"; cp "$d/tasks.cfg" "$work/task.after"
x update --server xymonapi; ok "update after one cut short, the task file changed since"
assert_contains "$d/tasks.cfg differs from the copy the run cut short set aside, which is put back: it is kept as tasks.cfg.old" "$out" "[S7] the file changed since is said kept"
cmp -s "$work/task.kept" "$d/tasks.cfg" || fail "[S7] the task file set aside is not the one back"
cmp -s "$work/task.after" "$d/tasks.cfg.old" || fail "[S7] the task file changed since is not kept as tasks.cfg.old"
rm -f "$d/tasks.cfg.old"
theirs snap-a4
cmp -s "$work/snap-a3.f" "$work/snap-a4.f" || fail "[S7] resuming changed another directory: $(diff "$work/snap-a3.f" "$work/snap-a4.f" || :)"
# Beside a complete install, one is stale: update and install refused,
# said with its date; remove and verify name it, verify as untidy.
plugin_of "$sa" xymonapi; echo older > "$sa/xymonapi-nginx.conf"
stale="$sa, set aside on 2026-01-02 03:04 by an install of xymonapi cut short, is left: compare it with $d, then remove it"
gone="$sa, set aside on 2026-01-02 03:04 by an install of xymonapi cut short, is left, $d gone: take back what you want from it, then remove it"
refused "an update beside a stale one" "$stale; then install or update xymonapi" update --server xymonapi
x verify --server xymonapi
[ "$rc" -eq 4 ] || fail "[S30] verify beside a stale one exited $rc, not 4: $out"
assert_contains "untidy: xymonapi: $stale" "$out" "[S30] verify says the stale one untidy"
x remove --server xymonapi; ok "remove beside a stale one"
assert_contains "$gone" "$out" "[S7] remove names the stale one, to take back from"
assert_not_contains "compare it with" "$out" "[S7] and not to compare with the directory it removed"
assert_equal older "$(cat "$sa/xymonapi-nginx.conf")" "[S7] and leaves it"
x verify --server
assert_contains "untidy: xymonapi: $sa, set aside on" "$out" "[S30] verify names the one of a plugin gone"
x verify --server xymonapi
assert_contains "untidy: xymonapi: $sa, set aside on" "$out" "[S30] verify of the plugin gone, named, names it too"
refused "an install beside a stale one, its plugin gone" "$gone; then install or update xymonapi" install --server xymonapi
rm -rf "$sa"
# Not one to resume with: a link, a directory not marked, or marked for
# another plugin: refused before anything changes.
x install --server xymonapi; ok "install --server"
ln -s "$e/.xymon-plugin.other" "$sa"
refused "a link in the set-aside directory's place" "$sa is a link, or no directory: left as it is" update --server xymonapi
rm -f "$sa"; mkdir "$sa"; echo mine > "$sa/notes"
refused "an unmarked directory in its place" "$sa is not set aside by xymon-plugin for xymonapi: left as it is" update --server xymonapi
# verify and remove do not call it set aside by an install cut short.
x verify --server xymonapi
assert_contains "untidy: xymonapi: $sa is not set aside by xymon-plugin: left as it is" "$out" "[S30] verify names an unmarked one as none of the installer's"
assert_not_contains "set aside on" "$out" "[S30] and gives it no date"
plugin_of "$sa" xymonapi-rag
refused "one marked for another plugin" "$sa is not set aside by xymon-plugin for xymonapi" update --server xymonapi
rm -rf "$sa"
# What a resume cannot put back keeps the directory, said.
plugin_of "$sa" xymonapi; mkdir -p "$sa/sub"; echo precious > "$sa/sub/file"
echo "xymon-plugin in progress: xymonapi $(sh -c 'echo $$')" > "$d/.xymon-plugin-in-progress"
x update --server xymonapi; ok "update with a directory holding what it cannot put back"
assert_contains "$sa holds what was not put back" "$out" "[S7] what cannot be put back is said"
assert_equal precious "$(cat "$sa/sub/file")" "[S7] and kept"
rm -rf "$sa" "$e/.xymon-plugin.other"
# An admin's app.py.old is no file of the install: MANIFEST names it not;
# and a PLUGIN copy hard-linked to a file outside is written anew, never
# through.
cp "$d/app.py" "$d/app.py.old"
cp "$d/PLUGIN" "$work/plugin.out"; echo "# outside" >> "$work/plugin.out"; rm -f "$d/PLUGIN"; ln "$work/plugin.out" "$d/PLUGIN"
x update --server xymonapi; ok "update beside app.py.old, the PLUGIN copy a hard link"
grep -q 'app\.py\.old' "$d/MANIFEST" && fail "[S29] MANIFEST names the admin's app.py.old"
assert_file_exists "$d/app.py.old"
grep -q "# outside" "$work/plugin.out" || fail "[S20] the update wrote the PLUGIN copy through a hard link"
grep -q "# outside" "$d/PLUGIN" && fail "[S20] the PLUGIN copy was not written anew"
rm -f "$d/app.py.old"
x remove --server xymonapi; ok "remove --server"
[ -z "$(ours_left)" ] || fail "[S28] a run left a directory to set files aside in: $(ours_left)"

pass "a manual page's or a command's name not free is left as it is, said, on the server and the tools, ours written and replaced; an update keeps an edited file no longer shipped as .old, said, refuses one replaced for the same web server before anything changes, and sets files aside in a directory of its own, gone after; removing a plugin gone takes only its task link and no SELinux module"
