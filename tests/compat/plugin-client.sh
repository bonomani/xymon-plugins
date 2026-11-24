#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-client.sh
#
# A plugin's client part goes into a standalone client's tree, by its owner
# (S35). xymon-plugin's own client part is installed, updated and removed
# with --client in a scratch client tree, in two layouts: plain
# directories, and etc/, logs/ and tmp/ links out of the tree, as the
# Ubuntu package has them. Its files, VERSION, PLUGIN copy and MANIFEST go
# under ext/xymon-plugin/, its manual page is linked from MANDIR when that
# can be written, and said when not, and nothing else is written: every
# path of the scratch area is compared with before. Each refusal changes
# nothing: a server's tree with --client, a client's with --server (S18);
# no part named on a client's tree, on a terminal too, two parts together,
# an old install-client, enable and disable --client (S24); a client tree
# that is, or may be, a server's own (S25); --venv, DESTDIR, a plugin with
# no client part, and an ext/ not the person's -- an id on PATH that
# answers another uid, as ownership is ls -n's uid compared with id -u
# (S35); a client file the checkout lacks, before anything is written; a
# directory no install left never taken, a PLUGIN and no VERSION among
# them, one cut short, the file in progress there, resumed by install and
# update, refused by remove; an install whose
# MANIFEST is gone is still one, updated (S35).
# A tree named relative, with ., or through a link finds the same
# ../server (S25). Detection offers the client trees found, and the one
# used last while its marks hold, remembered apart from the server's, and
# not by a run that removed nothing (S25). A client part's needs are
# client parts, checked for every plugin named before any is removed (S3,
# S35).
#
# Scratch trees, which XYMON_PLUGINS_TREES points detection at; answer.py
# plays the person at the terminal.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
# Resolved: the installer names trees by their resolved path, and on macOS
# the temporary directory lies under /var, a link to /private/var.
work=$(cd "$work" && pwd -P)
py=${XYMONAPI_PYTHON:-python3}
# HOME too: a write to the person's home, outside the scratch area, would
# go unseen.
# MAN is this test's own MANDIR override, and SUDO_USER would point the
# command at a real person's settings: neither is taken from outside.
unset MAN SUDO_USER
export HOME="$work/home" XDG_CONFIG_HOME="$work/cfg" XYMON_PLUGINS_TREES_ONLY=1 XYMON_PLUGINS_TREES=
mkdir -p "$HOME"
man=$work/man
mkdir -p "$man"
version=$(sed -n 's/^version: *//p' "$ROOT/plugins/xymon-plugin/PLUGIN")

# client_tree DIR -- DIR, a Xymon client's tree by its two marks, with ext/.
client_tree() {
	mkdir -p "$1/bin" "$1/etc" "$1/ext"
	: > "$1/bin/xymonclient.sh"; : > "$1/etc/xymonclient.cfg"
}

# snap FILE -- every path under the scratch area, but the snapshots and logs.
snap() { find "$work" -mindepth 1 \( -path "$work/snap*" -o -path "$work/log*" \) -prune -o -print | sort > "$work/$1"; }

# state FILE -- snap's paths, with each one's mode, each file's cksum and
# each link's target: a refusal that rewrites a file, as the installation
# used last, or changes a mode, changes it.
state() {
	snap "$1.p"
	while IFS= read -r p; do
		m=$(ls -ldn "$p" | awk '{ print $1 }')
		if [ -L "$p" ]; then printf '%s -> %s\n' "$p" "$(readlink "$p")"
		elif [ -f "$p" ]; then printf '%s %s %s\n' "$p" "$m" "$(cksum < "$p")"
		else printf '%s %s\n' "$p" "$m"; fi
	done < "$work/$1.p" > "$work/$1"
}

# x ARG... -- xymon-plugin ARG..., off a terminal, the one XP names or the
# checkout's; output in out, status in rc.
x() { rc=0; out=$("${XP:-$ROOT/xymon-plugin}" "$@" MANDIR="${MAN:-$man}" </dev/null 2>&1) || rc=$?; }

# term PROMPT ANSWER ARG... -- the same on a terminal, ANSWER typed at
# PROMPT; an empty PROMPT for a run that asks nothing.
term() {
	p=$1 ans=$2; shift 2
	rc=0; out=$("$py" "$ROOT/tests/lib/answer.py" "$p" "$ans" "$ROOT/xymon-plugin" "$@" MANDIR="$man" 2>&1) || rc=$?
}

# refused [RULE] LABEL WANT ARG... -- xymon-plugin ARG... fails, saying WANT,
# and the scratch area is as it was.
refused() {
	local r=$1 l=$2 w=$3; shift 3
	state snap-r0
	x "$@"
	[ "$rc" -ne 0 ] || fail "$r $l: was taken: $out"
	assert_contains "$w" "$out" "$r $l: refused, saying so"
	state snap-r1
	cmp -s "$work/snap-r0" "$work/snap-r1" || fail "$r $l: the refusal changed something: $(diff "$work/snap-r0" "$work/snap-r1" || :)"
}

# untouched [RULE] LABEL ARG... -- xymon-plugin ARG... succeeds, and the
# scratch area is as it was.
untouched() {
	local r=$1 l=$2; shift 2
	state snap-u0
	x "$@"
	[ "$rc" -eq 0 ] || fail "$r $l: failed: $out"
	state snap-u1
	cmp -s "$work/snap-u0" "$work/snap-u1" || fail "$r $l: changed something: $(diff "$work/snap-u0" "$work/snap-u1" || :)"
}

# new STEP -- what appeared since snap-before, one path a line.
new() { snap "snap-$1"; comm -13 "$work/snap-before" "$work/snap-$1"; }

# lifecycle LAYOUT TREE -- install, update and remove xymon-plugin's client
# part in TREE, checking what each leaves.
lifecycle() {
	local l=$1 c=$2 d nw
	snap snap-before
	x install --client xymon-plugin XYMONHOME="$c"
	[ "$rc" -eq 0 ] || fail "[S35] $l: install --client failed: $out"
	assert_contains "Target: $c (named by XYMONHOME), part: client" "$out" "[S35] $l: the target and the part are said"
	d=$c/ext/xymon-plugin
	assert_equal "MANIFEST PLUGIN VERSION xymon-plugin xymon-plugin.8" "$(ls -A "$d" | tr '\n' ' ' | sed 's/ $//')" "[S35] $l: ext/xymon-plugin holds the client part's files, and only those"
	[ -x "$d/xymon-plugin" ] || fail "[S35] $l: the installer is not executable"
	assert_equal "$version" "$(cat "$d/VERSION")" "[S35] $l: VERSION is the PLUGIN file's"
	cmp -s "$ROOT/plugins/xymon-plugin/PLUGIN" "$d/PLUGIN" || fail "[S35] $l: PLUGIN is not the checkout's copy"
	assert_equal "$d/xymon-plugin.8" "$(readlink "$man/man8/xymon-plugin.8")" "[S35] $l: the manual page is linked from MANDIR"
	# MANIFEST, line for line: the four files and the page's link, nothing else.
	mf=$(for f in PLUGIN VERSION xymon-plugin xymon-plugin.8; do printf 'file\t%s\t%s\n' "$(cksum < "$d/$f")" "$f"; done
		printf 'link\t%s\t%s\n' "$man/man8/xymon-plugin.8" "$d/xymon-plugin.8")
	assert_equal "$(printf '%s\n' "$mf" | sort)" "$(sort "$d/MANIFEST")" "[S35] $l: MANIFEST records the client part's files and the page's link, and only those"
	new install | while IFS= read -r p; do
		case $p in
			"$d"|"$d/"*|"$man/man8"|"$man/man8/xymon-plugin.8"|"$work/cfg"|"$work/cfg/xymon-plugin"|"$work/cfg/xymon-plugin/installation-used-last-client") ;;
			*) fail "[S35] $l: install --client wrote $p, outside ext/xymon-plugin and the manual page's link" ;;
		esac
	done
	# Damaged, and with a file no version ships: update puts back what the
	# plugin is, and only that.
	echo damaged >> "$d/xymon-plugin"; : > "$d/obsolete"
	x update --client XYMONHOME="$c"
	[ "$rc" -eq 0 ] || fail "[S35] $l: update --client failed: $out"
	assert_contains "Updated xymon-plugin $version in $c/ext/xymon-plugin." "$out" "[S35] $l: update --client says what it updated"
	cmp -s "$ROOT/plugins/xymon-plugin/xymon-plugin" "$d/xymon-plugin" || fail "[S35] $l: update --client did not put the installer back"
	[ ! -e "$d/obsolete" ] || fail "[S35] $l: update --client kept a file no version ships"
	x remove --client xymon-plugin XYMONHOME="$c"
	[ "$rc" -eq 0 ] || fail "[S35] $l: remove --client failed: $out"
	[ -e "$d" ] && fail "[S35] $l: remove --client left $d"
	[ -e "$man/man8/xymon-plugin.8" ] || [ -L "$man/man8/xymon-plugin.8" ] && fail "[S35] $l: remove --client left the manual page's link"
	new remove | while IFS= read -r p; do
		[ -d "$p" ] || [ "$p" = "$work/cfg/xymon-plugin/installation-used-last-client" ] || fail "[S35] $l: remove --client left $p"
	done
	# Again, now that it is gone: nothing to take away, as for a server
	# part, said, and not a refusal.
	x remove --client xymon-plugin XYMONHOME="$c"
	[ "$rc" -eq 0 ] || fail "[S35] $l: remove --client of a plugin not installed failed: $out"
	assert_contains "xymon-plugin is not installed in $c/ext: nothing removed." "$out" "[S35] $l: removing a plugin not installed says so"
	# MANDIR that cannot be written -- not there, as a permission bit would
	# not stop root: the page stays in the directory alone, said.
	nw=$work/no-man
	MAN=$nw x install --client xymon-plugin XYMONHOME="$c"
	[ "$rc" -eq 0 ] || fail "[S35] $l: install --client with MANDIR not there failed: $out"
	assert_contains "$nw/man8 cannot be written: xymon-plugin's manual page is not linked from it" "$out" "[S35] $l: a MANDIR not written is said"
	assert_file_exists "$d/xymon-plugin.8"
	[ -e "$nw" ] && fail "[S35] $l: MANDIR not there was made"
	MAN=$nw x remove --client xymon-plugin XYMONHOME="$c"
	[ "$rc" -eq 0 ] || fail "[S35] $l: remove --client failed: $out"
	# The section a file, and the page's name another's link in a section
	# that can be written: the install goes on without a link, said, and
	# claims none in its MANIFEST.
	fm=$work/file-man; mkdir -p "$fm"; : > "$fm/man8"
	MAN=$fm x install --client xymon-plugin XYMONHOME="$c"
	[ "$rc" -eq 0 ] || fail "[S35] $l: install --client with man8 a file failed: $out"
	assert_contains "$fm/man8 cannot be written" "$out" "[S35] $l: a section that is a file is said"
	assert_file_exists "$d/VERSION"
	MAN=$fm x remove --client xymon-plugin XYMONHOME="$c"
	om=$work/other-man; mkdir -p "$om/man8"; ln -s /elsewhere/xymon-plugin.8 "$om/man8/xymon-plugin.8"
	MAN=$om x install --client xymon-plugin XYMONHOME="$c"
	[ "$rc" -eq 0 ] || fail "[S35] $l: install --client beside another's link failed: $out"
	assert_contains "$om/man8/xymon-plugin.8 is another's, left as it is" "$out" "[S35] $l: another's link at the page's name is said"
	assert_equal /elsewhere/xymon-plugin.8 "$(readlink "$om/man8/xymon-plugin.8")" "[S35] $l: another's link at the page's name is left alone"
	assert_not_contains "$om/man8/xymon-plugin.8" "$(cat "$d/MANIFEST")" "[S29] $l: MANIFEST claims another's link"
	MAN=$om x remove --client xymon-plugin XYMONHOME="$c"
	rm -rf "$fm" "$om"
}

c=$work/plain/client
client_tree "$c"
lifecycle "plain directories" "$c"

# The Ubuntu package's layout: etc/, logs/ and tmp/ links out of the tree.
u=$work/ubuntu/usr/lib/xymon/client
mkdir -p "$u/bin" "$u/ext" "$work/ubuntu/etc/xymon" "$work/ubuntu/var/log/xymon" "$work/ubuntu/var/lib/xymon/tmp"
: > "$u/bin/xymonclient.sh"; : > "$work/ubuntu/etc/xymon/xymonclient.cfg"
ln -s "$work/ubuntu/etc/xymon" "$u/etc"
ln -s "$work/ubuntu/var/log/xymon" "$u/logs"
ln -s "$work/ubuntu/var/lib/xymon/tmp" "$u/tmp"
lifecycle "etc/ a link, as Ubuntu's" "$u"

# Refusals, each changing nothing.
s=$work/srv/server
server_tree "$s"; mkdir -p "$s/ext"
refused "[S18]" "a server's tree with --client" "is a Xymon server's tree (etc/xymonserver.cfg bin/xymond), not a client's: a server's tree takes the server part, --server" \
	install --client xymon-plugin XYMONHOME="$s"
refused "[S18]" "a client's tree with --server" "is a Xymon client's tree (etc/xymonclient.cfg bin/xymonclient.sh), not a server's: a client's tree takes the client part, --client" \
	install --server xymon-plugin XYMONHOME="$c"
h=$work/half/client; mkdir -p "$h/bin" "$h/ext"; : > "$h/bin/xymonclient.sh"
refused "[S18]" "half a client's pair" "it has bin/xymonclient.sh, and a client's has etc/xymonclient.cfg bin/xymonclient.sh" \
	install --client xymon-plugin XYMONHOME="$h"
noext=$work/noext/client; client_tree "$noext"; rmdir "$noext/ext"
refused "[S18]" "a client's tree without ext/" "has no directory ext/" install --client xymon-plugin XYMONHOME="$noext"

refused "[S24]" "no part on a client's tree" "is a Xymon client's tree, whose part is named: ./xymon-plugin install --client --xymon-home $c xymon-plugin" \
	install xymon-plugin XYMONHOME="$c"
snap snap-r0
term '' '' install xymon-plugin XYMONHOME="$c"
[ "$rc" -ne 0 ] || fail "[S24] no part on a client's tree, on a terminal, was taken: $out"
assert_contains "./xymon-plugin install --client --xymon-home $c xymon-plugin" "$out" "[S24] on a terminal too, the command with --client is given"
snap snap-r1
cmp -s "$work/snap-r0" "$work/snap-r1" || fail "[S24] the refusal on a terminal changed something"
refused "[S24]" "two parts" "./xymon-plugin install --client xymon-plugin" install --server --client xymon-plugin XYMONHOME="$c"
refused "[S24]" "two parts, said each" "./xymon-plugin install --server xymon-plugin" install --server --client xymon-plugin XYMONHOME="$c"
refused "[S24]" "status with two parts" "with none, covers every part" status --client --tools
refused "[S24]" "outdated with two parts" "with none, covers every part: the servers, the standalone clients and the tools" outdated --client --tools
refused "[S24]" "install-client" "install-client is now: ./xymon-plugin install --client" install-client xymon-plugin
refused "[S24]" "status-client" "status-client is now: ./xymon-plugin status --client" status-client
refused "[S24]" "enable --client" "the client part has no task" enable --client xymon-plugin XYMONHOME="$c"
refused "[S24]" "disable --client" "the client part has no task" disable --client xymon-plugin XYMONHOME="$c"

refused "[S35]" "--venv with --client" "--venv: a client part has no virtualenv" install --client --venv xymon-plugin XYMONHOME="$c"
refused "[S35]" "DESTDIR with --client" "a client part is not staged yet" install --client xymon-plugin XYMONHOME="$c" DESTDIR="$work/stage"
refused "[S35]" "a plugin with no client part" "xymonapi has no client part" install --client xymonapi XYMONHOME="$c"
# Another uid answered by id: ext/ is then not the person's.
realid=$(command -v id)
mkdir -p "$work/fakeid"
printf '#!/bin/sh\ncase "$*" in -u) echo 4242 ;; -un) echo someone-else ;; *) exec "%s" "$@" ;; esac\n' "$realid" > "$work/fakeid/id"
chmod 755 "$work/fakeid/id"
me=$(ls -ld "$c/ext/" | awk '{ print $3 }')
PATH="$work/fakeid:$PATH" refused "[S35]" "an ext/ not the person's" "$c/ext is $me's, not someone-else's: run this as $me" \
	install --client xymon-plugin XYMONHOME="$c"
x install --client xymon-plugin XYMONHOME="$c"
[ "$rc" -eq 0 ] || fail "[S35] install --client failed: $out"
PATH="$work/fakeid:$PATH" refused "[S35]" "remove from an ext/ not the person's" "is $me's, not someone-else's" \
	remove --client xymon-plugin XYMONHOME="$c"
PATH="$work/fakeid:$PATH" refused "[S35]" "update in an ext/ not the person's" "is $me's, not someone-else's" \
	update --client xymon-plugin XYMONHOME="$c"
# A refusal after the tree is checked leaves no installation remembered.
rm -f "$work/cfg/xymon-plugin/installation-used-last-client"
refused "[S25]" "install of a plugin installed already" "xymon-plugin is installed already" install --client xymon-plugin XYMONHOME="$c"
[ ! -e "$work/cfg/xymon-plugin/installation-used-last-client" ] || fail "[S25] a refused install remembered the installation"
x remove --client xymon-plugin XYMONHOME="$c"

# ext/ may hold anything: a directory no plugin installed is left as it
# is, and a plugin with no client part is refused, there or not.
mkdir -p "$c/ext/stray"; echo precious > "$c/ext/stray/data"
refused "[S35]" "removing a directory no plugin has" "no plugin stray here" remove --client stray XYMONHOME="$c"
assert_file_exists "$c/ext/stray/data"
mkdir -p "$c/ext/xymonapi"; echo precious > "$c/ext/xymonapi/data"
refused "[S35]" "removing a directory named as a plugin, not its install" "$c/ext/xymonapi is not xymonapi's client part as an install leaves it" remove --client xymonapi XYMONHOME="$c"
# One that looks like an install by links: never one an install leaves.
mkdir -p "$c/ext/xymon-plugin"; echo precious > "$c/ext/xymon-plugin/data"; echo "$version" > "$c/ext/xymon-plugin/VERSION"
ln -s "$ROOT/plugins/xymon-plugin/PLUGIN" "$c/ext/xymon-plugin/PLUGIN"
refused "[S35]" "removing a directory whose PLUGIN is a link" "is not xymon-plugin's client part as an install leaves it" remove --client xymon-plugin XYMONHOME="$c"
assert_file_exists "$c/ext/xymon-plugin/data"
rm -rf "$c/ext/xymon-plugin"
# A stray directory with a PLUGIN file too; and an installation used last
# that a run removing nothing must not rewrite.
printf 'name: other\nclient-files: data\n' > "$c/ext/stray/PLUGIN"
mkdir -p "$work/cfg/xymon-plugin"; echo /another/client > "$work/cfg/xymon-plugin/installation-used-last-client"
untouched "[S35]" "remove --client --all beside directories no install completed" remove --client --all XYMONHOME="$c"
refused "[S35]" "update --client, none named, with only directories no install completed" "nothing is installed" update --client XYMONHOME="$c"
assert_contains "$c/ext/stray is no install of stray's: left as it is" "$out" "[S35] update --client, none named, says what it passes over"
rm -rf "$c/ext/xymon-plugin"
# A PLUGIN and no VERSION is no install, nor with a file in progress
# naming another plugin; one cut short, the file in progress there naming
# it: remove takes a first install's, nothing set aside on a client;
# install and update resume it.
mkdir -p "$c/ext/xymon-plugin"
cp "$ROOT/plugins/xymon-plugin/PLUGIN" "$c/ext/xymon-plugin/PLUGIN"
refused "[S35]" "installing over a PLUGIN and no VERSION" "is not xymon-plugin's client part as an install leaves it" install --client xymon-plugin XYMONHOME="$c"
echo "xymon-plugin in progress: other 1" > "$c/ext/xymon-plugin/.xymon-plugin-in-progress"
refused "[S35]" "installing over a file in progress naming another" "is not xymon-plugin's client part as an install leaves it" install --client xymon-plugin XYMONHOME="$c"
inprog() { echo "xymon-plugin in progress: xymon-plugin $(sh -c 'echo $$')" > "$c/ext/xymon-plugin/.xymon-plugin-in-progress"; }
echo "xymon-plugin in progress: xymon-plugin $(sh -c 'echo $$') first" > "$c/ext/xymon-plugin/.xymon-plugin-in-progress"
rc=0; out=$("$ROOT/xymon-plugin" remove --client xymon-plugin XYMONHOME="$c" </dev/null 2>&1) || rc=$?
[ "$rc" -eq 0 ] && [ ! -e "$c/ext/xymon-plugin" ] || fail "[S35] remove did not take an install cut short, nothing set aside: $out"
mkdir -p "$c/ext/xymon-plugin"; cp "$ROOT/plugins/xymon-plugin/PLUGIN" "$c/ext/xymon-plugin/PLUGIN"
for a in install update; do
	rm -f "$c/ext/xymon-plugin/VERSION"; inprog
	rc=0; out=$("$ROOT/xymon-plugin" "$a" --client xymon-plugin XYMONHOME="$c" </dev/null 2>&1) || rc=$?
	[ "$rc" -eq 0 ] || fail "[S35] $a of an install cut short failed: $out"
	assert_file_exists "$c/ext/xymon-plugin/VERSION"
	[ ! -e "$c/ext/xymon-plugin/.xymon-plugin-in-progress" ] || fail "[S35] the $a resumed left the file in progress"
done
# One cut short for real, after its directory is emptied: the file in
# progress kept, the update resumes it.
cutc=$work/cutc; mkdir -p "$cutc"; cp -R "$ROOT/xymon-plugin" "$ROOT/LICENSE" "$ROOT/plugins" "$cutc/"
awk '{ print } $0 == "\tcopy \"$1\" client \"$dir\"" { print "exit 1" }' "$ROOT/plugins/xymon-plugin/xymon-plugin" > "$cutc/plugins/xymon-plugin/xymon-plugin"
grep -qx 'exit 1' "$cutc/plugins/xymon-plugin/xymon-plugin" || fail "the client's copy line was not found to cut after"
rc=0; out=$("$cutc/xymon-plugin" update --client xymon-plugin XYMONHOME="$c" </dev/null 2>&1) || rc=$?
[ "$rc" -ne 0 ] || fail "[S35] the cut update was taken"
assert_file_exists "$c/ext/xymon-plugin/.xymon-plugin-in-progress"
rc=0; out=$("$ROOT/xymon-plugin" update --client xymon-plugin XYMONHOME="$c" </dev/null 2>&1) || rc=$?
[ "$rc" -eq 0 ] || fail "[S35] the update of one cut short for real failed: $out"
assert_file_exists "$c/ext/xymon-plugin/VERSION"
# Another run on it, its process alive and an xymon-plugin: refused.
mkdir -p "$work/fake"; printf '#!/bin/sh\nsleep 30\n' > "$work/fake/xymon-plugin"; chmod 755 "$work/fake/xymon-plugin"
"$work/fake/xymon-plugin" & alive=$!
echo "xymon-plugin in progress: xymon-plugin $alive" > "$c/ext/xymon-plugin/.xymon-plugin-in-progress"
refused "[S35]" "an update still running" "an install or update of xymon-plugin is running, process $alive" update --client xymon-plugin XYMONHOME="$c"
kill "$alive"; wait "$alive" 2>/dev/null || :
rm -f "$c/ext/xymon-plugin/.xymon-plugin-in-progress"
rm -rf "$c/ext/xymon-plugin"
untouched "[S25]" "a client removal of a plugin not there" remove --client xymon-plugin XYMONHOME="$c"
# An install whose MANIFEST is gone -- an update cut short after its
# VERSION -- is still one: the next update puts it back.
x install --client xymon-plugin XYMONHOME="$c"
rm -f "$c/ext/xymon-plugin/MANIFEST"
x update --client xymon-plugin XYMONHOME="$c"
[ "$rc" -eq 0 ] || fail "[S35] an install with no MANIFEST was not updated: $out"
for f in xymon-plugin xymon-plugin.8 PLUGIN VERSION; do
	assert_file_exists "$c/ext/xymon-plugin/$f"
	grep -q "	$f\$" "$c/ext/xymon-plugin/MANIFEST" || fail "[S35] the MANIFEST an update put back does not name $f"
done
x remove --client xymon-plugin XYMONHOME="$c"
# update with none named passes over them, updating only an install.
x install --client xymon-plugin XYMONHOME="$c"
state snap-s0; grep "^$c/ext/stray" "$work/snap-s0" > "$work/snap-s0.stray"
x update --client XYMONHOME="$c"
[ "$rc" -eq 0 ] || fail "[S35] update --client beside a stray directory failed: $out"
state snap-s1; grep "^$c/ext/stray" "$work/snap-s1" > "$work/snap-s1.stray"
cmp -s "$work/snap-s0.stray" "$work/snap-s1.stray" || fail "[S35] update --client changed a stray directory"
# The site's own scripts in ext/, no PLUGIN, no VERSION, no plugin's name:
# not read, nothing said, nothing touched (S20).
echo '#!/bin/sh' > "$c/ext/check_raid.sh"; mkdir -p "$c/ext/mes-scripts"; echo mine > "$c/ext/mes-scripts/run"
state snap-m0; grep -e "^$c/ext/check_raid.sh " -e "^$c/ext/mes-scripts[ /]" "$work/snap-m0" > "$work/snap-m0.f" || :
x update --client XYMONHOME="$c"
[ "$rc" -eq 0 ] || fail "[S35] update --client beside the site's own scripts failed: $out"
for w in check_raid.sh mes-scripts; do assert_not_contains "$w" "$out" "[S35] update --client says nothing of the site's $w"; done
x remove --client --all XYMONHOME="$c"
[ "$rc" -eq 0 ] || fail "[S35] remove --client --all beside the site's own scripts failed: $out"
for w in check_raid.sh mes-scripts; do assert_not_contains "$w" "$out" "[S35] remove --client --all says nothing of the site's $w"; done
state snap-m1; grep -e "^$c/ext/check_raid.sh " -e "^$c/ext/mes-scripts[ /]" "$work/snap-m1" > "$work/snap-m1.f" || :
[ -s "$work/snap-m1.f" ] && cmp -s "$work/snap-m0.f" "$work/snap-m1.f" || fail "[S35] the site's own scripts changed: $(diff "$work/snap-m0.f" "$work/snap-m1.f" || :)"
rm -rf "$c/ext/check_raid.sh" "$c/ext/mes-scripts"
x install --client xymon-plugin XYMONHOME="$c"
x remove --client xymon-plugin XYMONHOME="$c"
rm -f "$work/cfg/xymon-plugin/installation-used-last-client"
rm -rf "$c/ext/stray" "$c/ext/xymonapi"
refused "[S35]" "removing a plugin with no client part" "xymonapi has no client part" remove --client xymonapi XYMONHOME="$c"

# An ext/ that is a link would take the plugins out of the tree.
l=$work/linked; client_tree "$l"; rmdir "$l/ext"; mkdir -p "$work/elsewhere"; ln -s "$work/elsewhere" "$l/ext"
refused "[S18]" "an ext/ that is a link" "$l/ext is a link" install --client xymon-plugin XYMONHOME="$l"

# verify changes nothing: it remembers no installation.
v=$work/vsrv; server_tree "$v"
x verify --server XYMONHOME="$v"
[ ! -e "$work/cfg/xymon-plugin/installation-used-last-server" ] || fail "[S25] verify remembered the installation"

# A server's own client tree, and one that may be.
o=$work/own; server_tree "$o/server"; client_tree "$o/client"
echo "XYMONCLIENTHOME=\"$o/client\"" >> "$o/server/etc/xymonserver.cfg"
refused "[S25]" "a server's own client tree" "is the client tree of the Xymon server $o/server" install --client xymon-plugin XYMONHOME="$o/client"
o=$work/other; server_tree "$o/server"; client_tree "$o/client"
echo "XYMONCLIENTHOME=\"$work/elsewhere\"" >> "$o/server/etc/xymonserver.cfg"
refused "[S25]" "a ../server naming another tree" "the Xymon server $o/server beside it names $work/elsewhere as its XYMONCLIENTHOME; refused while in doubt" \
	install --client xymon-plugin XYMONHOME="$o/client"
o=$work/none; server_tree "$o/server"; client_tree "$o/client"
refused "[S25]" "a ../server naming none" "beside it names no XYMONCLIENTHOME this command can read" install --client xymon-plugin XYMONHOME="$o/client"
o=$work/shared/client; client_tree "$o"; : > "$o/etc/xymonserver.cfg"
refused "[S25]" "a xymonserver.cfg in its etc/" "its etc/ holds a xymonserver.cfg" install --client xymon-plugin XYMONHOME="$o"
# Named relative, or with slashes at its end, the same tree is refused the
# same way: ../server is found from the tree's absolute path.
o=$work/own
(cd "$o" && refused "[S25]" "a server's own client named relative" "is the client tree of the Xymon server $o/server" install --client xymon-plugin XYMONHOME=client)
refused "[S25]" "a server's own client named with slashes at its end" "is the client tree of the Xymon server $o/server" install --client xymon-plugin XYMONHOME="$o/client//"
(cd "$o/client" && refused "[S25]" "a server's own client named ." "is the client tree of the Xymon server $o/server" install --client xymon-plugin --xymon-home .)
refused "[S25]" "a server's own client named with /. at its end" "is the client tree of the Xymon server $o/server" install --client xymon-plugin XYMONHOME="$o/client/."
# Through a link elsewhere: ../server is the one beside the tree itself.
mkdir -p "$work/via"; ln -s "$o/client" "$work/via/client"
refused "[S25]" "a server's own client named through a link" "is the client tree of the Xymon server $o/server" install --client xymon-plugin XYMONHOME="$work/via/client"
# No part named on it: the server named, as with --server.
refused "[S25]" "no part on a server's own client tree" "is the client tree of the Xymon server $o/server: name the server, ./xymon-plugin install --xymon-home $o/server --server" \
	install xymon-plugin XYMONHOME="$o/client"
# Named ., a tree's paths are built from its absolute one.
cd "$c"; x install --client xymon-plugin XYMONHOME=.; cd "$OLDPWD"
[ "$rc" -eq 0 ] || fail "[S25] install --client named . failed: $out"
assert_equal "$c/ext/xymon-plugin/xymon-plugin.8" "$(readlink "$man/man8/xymon-plugin.8")" "[S25] named ., the manual page's link is absolute"
x remove --client xymon-plugin XYMONHOME="$c"
# Under DESTDIR, a relative XYMONHOME is a path inside the stage, as given.
cd "$work"; x install --server xymon-plugin XYMONHOME=rel DESTDIR="$work/stage"; cd "$OLDPWD"
[ "$rc" -eq 0 ] || fail "[S25] a relative XYMONHOME under DESTDIR failed: $out"
assert_file_exists "$work/stage/rel/ext/xymon-plugin/VERSION"
rm -rf "$work/stage"

# install and update replace ext/NAME whole: one no install left is left
# as it is -- data in it, a VERSION beside data, a link to the person's own.
mkdir -p "$c/ext/xymon-plugin"; echo precious > "$c/ext/xymon-plugin/mydata"
refused "[S28]" "install over a directory no install left" "$c/ext/xymon-plugin is not xymon-plugin's client part as an install leaves it" install --client xymon-plugin XYMONHOME="$c"
refused "[S28]" "update of a directory with no VERSION, said as none, not as absent" "$c/ext/xymon-plugin is not xymon-plugin's client part as an install leaves it" update --client xymon-plugin XYMONHOME="$c"
echo "$version" > "$c/ext/xymon-plugin/VERSION"
refused "[S28]" "update of a directory no install left" "$c/ext/xymon-plugin is not xymon-plugin's client part as an install leaves it" update --client xymon-plugin XYMONHOME="$c"
assert_file_exists "$c/ext/xymon-plugin/mydata"
rm -rf "$c/ext/xymon-plugin"; mkdir -p "$work/mine"; echo "$version" > "$work/mine/VERSION"; ln -s "$work/mine" "$c/ext/xymon-plugin"
refused "[S28]" "update of a link to the person's own" "is not xymon-plugin's client part as an install leaves it" update --client xymon-plugin XYMONHOME="$c"
[ -L "$c/ext/xymon-plugin" ] || fail "[S28] the person's link was replaced"
rm -f "$c/ext/xymon-plugin"
# An install's own marks, one by one: each makes it no install's.
x install --client xymon-plugin XYMONHOME="$c"
[ "$rc" -eq 0 ] || fail "[S35] install --client failed: $out"
cp "$c/ext/xymon-plugin/PLUGIN" "$work/PLUGIN.kept"
sed -e 's/^name: .*/name: other/' "$work/PLUGIN.kept" > "$c/ext/xymon-plugin/PLUGIN"
refused "[S35]" "removing an install whose PLUGIN names another" "is not xymon-plugin's client part as an install leaves it" remove --client xymon-plugin XYMONHOME="$c"
sed -e '/^client-files:/d' "$work/PLUGIN.kept" > "$c/ext/xymon-plugin/PLUGIN"
refused "[S35]" "removing an install whose PLUGIN has no client part" "is not xymon-plugin's client part as an install leaves it" remove --client xymon-plugin XYMONHOME="$c"
cp "$work/PLUGIN.kept" "$c/ext/xymon-plugin/PLUGIN"
mv "$c/ext/xymon-plugin/VERSION" "$work/VERSION.kept"; ln -s "$work/VERSION.kept" "$c/ext/xymon-plugin/VERSION"
refused "[S35]" "removing an install whose VERSION is a link" "is not xymon-plugin's client part as an install leaves it" remove --client xymon-plugin XYMONHOME="$c"
rm -f "$c/ext/xymon-plugin/VERSION"; mv "$work/VERSION.kept" "$c/ext/xymon-plugin/VERSION"
mv "$c/ext/xymon-plugin" "$work/xp.kept"; ln -s "$work/xp.kept" "$c/ext/xymon-plugin"
refused "[S35]" "removing an install that is a link" "is not xymon-plugin's client part as an install leaves it" remove --client xymon-plugin XYMONHOME="$c"
rm -f "$c/ext/xymon-plugin"; mv "$work/xp.kept" "$c/ext/xymon-plugin"
# --all passes over what is installed already, saying so.
x install --client --all XYMONHOME="$c"
[ "$rc" -eq 0 ] || fail "[S24] install --client --all failed: $out"
assert_contains "xymon-plugin is installed already ($version): left as it is" "$out" "[S24] install --client --all names the plugin installed already"
assert_not_contains "Installed xymon-plugin" "$out" "[S24] install --client --all passes over the plugin installed already"
# outdated reads a client's tree as a server's (S32): a gh on PATH
# answers the releases in $work/tags.
mkdir -p "$work/gh"; printf '#!/bin/sh\ncat "%s"\n' "$work/tags" > "$work/gh/gh"; chmod 755 "$work/gh/gh"
newer=$(echo "$version" | awk -F. -v OFS=. '{ $NF = $NF + 1; print }')
echo "xymon-plugin/v$newer" > "$work/tags"
PATH="$work/gh:$PATH" x outdated --client XYMONHOME="$c"
[ "$rc" -eq 6 ] || fail "[S32] outdated --client, a newer release: not 6 ($rc): $out"
assert_contains "Xymon client $c:" "$out" "[S32] outdated --client names the client's tree"
assert_contains "xymon-plugin: $version installed; $newer released: ./xymon-plugin update --client --xymon-home $c xymon-plugin" "$out" "[S32] and the update that takes the newer release, for the client part"
echo "xymon-plugin/v$version" > "$work/tags"
PATH="$work/gh:$PATH" x outdated XYMONHOME="$c"
[ "$rc" -eq 0 ] || fail "[S32] outdated, no part, on a client's tree up to date: not 0 ($rc): $out"
assert_contains "Xymon client $c:" "$out" "[S32] outdated with no part reads a client's tree named"
assert_contains "xymon-plugin: $version installed; up to date" "$out" "[S32] and says it up to date"
# clean --client (S31): installed, refused, naming remove; its directory
# removed by hand, the manual page's link left is said by verify and taken
# by clean, with --yes off a terminal, and only it: a link of another
# tree's plugin stays.
refused "[S31]" "clean --client of a plugin installed" "xymon-plugin is installed: ./xymon-plugin remove --client xymon-plugin" clean --client xymon-plugin XYMONHOME="$c"
mkdir -p "$work/other/ext/gone"; : > "$work/other/ext/gone/gone.8"; ln -s "$work/other/ext/gone/gone.8" "$man/man8/gone.8"
rm -rf "$c/ext/xymon-plugin"
x verify --client XYMONHOME="$c"
[ "$rc" -eq 4 ] || fail "[S30] verify --client, a manual page's link left: not 4 ($rc): $out"
assert_contains "untidy: $man/man8/xymon-plugin.8, a manual page's link of xymon-plugin, which is gone: ./xymon-plugin clean --client xymon-plugin" "$out" "[S30] verify --client says the link left, naming clean --client"
assert_not_contains "gone.8" "$out" "[S30] and not a link into another tree"
x clean --client --all XYMONHOME="$c"
[ "$rc" -eq 4 ] || fail "[S31] clean --client off a terminal without --yes: not 4 ($rc): $out"
assert_contains "Nothing removed: off a terminal, --yes removes it." "$out" "[S31] off a terminal, clean --client removes nothing without --yes"
[ -L "$man/man8/xymon-plugin.8" ] || fail "[S31] clean --client without --yes removed the link"
x clean --client xymon-plugin --yes XYMONHOME="$c"
[ "$rc" -eq 0 ] || fail "[S31] clean --client --yes failed ($rc): $out"
assert_contains "Removed $man/man8/xymon-plugin.8." "$out" "[S31] clean --client --yes removes the link left"
{ [ -e "$man/man8/xymon-plugin.8" ] || [ -L "$man/man8/xymon-plugin.8" ]; } && fail "[S31] clean --client left the link"
[ -L "$man/man8/gone.8" ] || fail "[S31] clean --client took a link into another tree"
rm -f "$man/man8/gone.8"
x verify --client XYMONHOME="$c"
[ "$rc" -eq 0 ] || fail "[S30] verify --client after clean: not 0 ($rc): $out"
# enable with two parts: no command for the client part, which has no task.
refused "[S24]" "enable, two parts" "the client part has no task" enable --server --client xymon-plugin XYMONHOME="$c"
assert_not_contains "enable --client" "$out" "[S24] enable with two parts proposes enable --client"
refused "[S24]" "uninstall-client" "uninstall-client is now: ./xymon-plugin remove --client" uninstall-client xymon-plugin
refused "[S24]" "enable, no part, on a client's tree" "the client part has no task to turn on or off yet" enable xymon-plugin XYMONHOME="$c"

# Detection: the client trees found, on a terminal; the one chosen
# remembered for the client part, apart from the server's.
export XYMON_PLUGINS_TREES="$s:$c"
x install --client xymon-plugin
[ "$rc" -ne 0 ] || fail "[S25] off a terminal, --client with no installation named was taken"
assert_contains "$c, a Xymon client" "$out" "[S4] [S25] and the refusal lists the trees found, installing nothing"
term 'Use it? [Y/n] ' '' install --client xymon-plugin
[ "$rc" -eq 0 ] || fail "[S25] Enter at the client found failed: $out"
assert_contains "Xymon client: $c (detected)" "$out" "[S25] the one client tree found is proposed"
assert_not_contains "$s" "$out" "[S25] and not the server"
assert_contains "Target: $c (detected, confirmed), part: client" "$out" "[S25] the first line says what chose it"
assert_equal "$c" "$(cat "$work/cfg/xymon-plugin/installation-used-last-client")" "[S25] it is remembered as the client tree used last"
[ -e "$work/cfg/xymon-plugin/installation-used-last-server" ] && fail "[S25] the client's choice was remembered as the server's"
# outdated with none named reads every tree found, the standalone clients
# among them, as status does (S32).
PATH="$work/gh:$PATH" x outdated
[ "$rc" -eq 0 ] || fail "[S32] outdated with none named, all up to date: not 0 ($rc): $out"
assert_contains "Xymon server $s:" "$out" "[S32] outdated with none named reads the servers found"
assert_contains "Xymon client $c:" "$out" "[S32] and the standalone clients found"
assert_contains "xymon-plugin: $version installed; up to date" "$out" "[S32] with what each holds"
# A client tree detection does not find: the one used last, while its marks hold.
export XYMON_PLUGINS_TREES="$s"
term 'Use it? [Y/n] ' '' update --client xymon-plugin
[ "$rc" -eq 0 ] || fail "[S25] the client tree used last was not offered: $out"
assert_contains "Xymon client: $c (detected)" "$out" "[S25] the client tree used last is offered"
x remove --client xymon-plugin XYMONHOME="$c"
mv "$c/etc/xymonclient.cfg" "$c/etc/xymonclient.cfg.off"
x install --client xymon-plugin
[ "$rc" -ne 0 ] || fail "[S25] the client tree used last, its marks gone, was taken"
assert_not_contains "$c" "$out" "[S25] its marks gone, it is not offered"
mv "$c/etc/xymonclient.cfg.off" "$c/etc/xymonclient.cfg"
export XYMON_PLUGINS_TREES=

# A client part's needs are client parts: a copy of the checkout with a
# plugin of its own, needing xymon-plugin's.
r=$work/repo; mkdir -p "$r"
cp -R "$ROOT/xymon-plugin" "$ROOT/LICENSE" "$ROOT/plugins" "$r/"
mkdir -p "$r/plugins/cneed"
printf 'name: cneed\nversion: 1.0.0\nsummary: a test\nclient-files: check.sh\nclient-needs: xymon-plugin\n' > "$r/plugins/cneed/PLUGIN"
: > "$r/plugins/cneed/check.sh"
# What it needs is checked as the plugin named is, before anything
# changes: a directory no install left where xymon-plugin's goes stops the
# install of cneed, and is left as it is.
mkdir -p "$c/ext/xymon-plugin"; echo precious > "$c/ext/xymon-plugin/mydata"
XP="$r/xymon-plugin" refused "[S35]" "a client part whose need's directory no install left" "is not xymon-plugin's client part as an install leaves it" install --client cneed XYMONHOME="$c"
assert_file_exists "$c/ext/xymon-plugin/mydata"
rm -rf "$c/ext/xymon-plugin"
rc=0; out=$("$r/xymon-plugin" install --client cneed XYMONHOME="$c" MANDIR="$man" </dev/null 2>&1) || rc=$?
[ "$rc" -eq 0 ] || fail "[S35] a client part needing another failed: $out"
assert_file_exists "$c/ext/xymon-plugin/VERSION"
assert_file_exists "$c/ext/cneed/check.sh"
rc=0; out=$("$r/xymon-plugin" remove --client xymon-plugin XYMONHOME="$c" MANDIR="$man" </dev/null 2>&1) || rc=$?
[ "$rc" -ne 0 ] || fail "[S35] a client part another needs was removed"
assert_contains "xymon-plugin is needed by cneed" "$out" "[S35] and the refusal names the one that needs it"
assert_file_exists "$c/ext/xymon-plugin/VERSION"
assert_file_exists "$c/ext/cneed/VERSION"
# An installed plugin gone from the checkout: update with none named
# passes over it, said, and updates the others.
x update --client XYMONHOME="$c"
[ "$rc" -eq 0 ] || fail "[S35] update --client with a plugin gone from the checkout failed: $out"
assert_contains "cneed is not in this checkout: left as it is" "$out" "[S35] update --client says it passes over a plugin gone from the checkout"
assert_contains "Updated xymon-plugin $version" "$out" "[S35] and updates the others"
assert_file_exists "$c/ext/cneed/check.sh"
# Two named, one needed by a plugin that stays: nothing removed (S3).
mkdir -p "$r/plugins/zfree"; printf 'name: zfree\nversion: 1.0.0\nsummary: a test\nclient-files: z.sh\n' > "$r/plugins/zfree/PLUGIN"
: > "$r/plugins/zfree/z.sh"
XP=$r/xymon-plugin x install --client zfree XYMONHOME="$c"
[ "$rc" -eq 0 ] || fail "[S35] install --client zfree failed: $out"
XP=$r/xymon-plugin refused "[S3]" "removing two, one needed by a plugin that stays" "xymon-plugin is needed by cneed" remove --client zfree xymon-plugin XYMONHOME="$c"
XP=$r/xymon-plugin x remove --client zfree XYMONHOME="$c"
# A directory there no install left -- no VERSION, or a PLUGIN naming
# another -- is no plugin's install: what its PLUGIN says it needs
# blocks nothing (S3).
mkdir -p "$c/ext/native"; printf 'name: native\nclient-needs: cneed\n' > "$c/ext/native/PLUGIN"
mkdir -p "$c/ext/half"; printf 'name: other\nclient-files: h.sh\nclient-needs: cneed\n' > "$c/ext/half/PLUGIN"; echo 1.0.0 > "$c/ext/half/VERSION"
rc=0; out=$("$r/xymon-plugin" remove --client cneed XYMONHOME="$c" MANDIR="$man" </dev/null 2>&1) || rc=$?
[ "$rc" -eq 0 ] || fail "[S3] a directory no install completed blocked a removal: $out"
[ ! -e "$c/ext/cneed" ] || fail "[S3] cneed was not removed: $out"
assert_file_exists "$c/ext/native/PLUGIN"
assert_file_exists "$c/ext/half/VERSION"
rm -rf "$c/ext/native" "$c/ext/half"
# Nor one whose name no plugin's can be, its PLUGIN naming it.
mkdir -p "$c/ext/evil name"; echo 1.0.0 > "$c/ext/evil name/VERSION"
printf 'name: evil name\nclient-files: h.sh\nclient-needs: xymon-plugin\n' > "$c/ext/evil name/PLUGIN"
XP=$r/xymon-plugin x remove --client xymon-plugin XYMONHOME="$c"
[ "$rc" -eq 0 ] || fail "[S3] a directory named as no plugin can be blocked a removal: $out"
assert_file_exists "$c/ext/evil name/PLUGIN"
rm -rf "$c/ext/evil name"
# Both named, the one needing the other: both go.
XP=$r/xymon-plugin x install --client cneed XYMONHOME="$c"
XP=$r/xymon-plugin x remove --client cneed xymon-plugin XYMONHOME="$c"
[ "$rc" -eq 0 ] || fail "[S3] removing a plugin and the one it needs, both named, failed: $out"
XP=$r/xymon-plugin x install --client cneed XYMONHOME="$c"
"$r/xymon-plugin" remove --client --all XYMONHOME="$c" MANDIR="$man" </dev/null >/dev/null 2>&1 || fail "[S35] remove --client --all failed"
[ -e "$c/ext/cneed" ] || [ -e "$c/ext/xymon-plugin" ] && fail "[S35] remove --client --all left a plugin"
printf 'client-needs: xymonapi:server\n' >> "$r/plugins/cneed/PLUGIN"
sed -e '/^client-needs: xymon-plugin$/d' "$r/plugins/cneed/PLUGIN" > "$r/plugins/cneed/PLUGIN.new" && mv "$r/plugins/cneed/PLUGIN.new" "$r/plugins/cneed/PLUGIN"
rc=0; out=$("$r/xymon-plugin" install --client cneed XYMONHOME="$c" MANDIR="$man" </dev/null 2>&1) || rc=$?
[ "$rc" -ne 0 ] || fail "[S35] a client part needing a server part was taken"
assert_contains "cannot hold" "$out" "[S35] and the refusal says why"
[ -e "$c/ext/cneed" ] && fail "[S35] the refused client part was installed anyway"
# With another named before it, the refusal still comes before anything
# changes: the other is not installed either (S3).
rc=0; out=$("$r/xymon-plugin" install --client xymon-plugin cneed XYMONHOME="$c" MANDIR="$man" </dev/null 2>&1) || rc=$?
[ "$rc" -ne 0 ] || fail "[S3] a client part needing a server part was installed with another"
[ -e "$c/ext/xymon-plugin" ] && fail "[S3] the plugin named before the refused one was installed: $out"
# A file its PLUGIN names that the checkout lacks: refused before anything
# is written, the plugin named before it too.
mkdir -p "$r/plugins/bad"; printf 'name: bad\nversion: 1.0.0\nsummary: a test\nclient-files: a.sh missing.sh\n' > "$r/plugins/bad/PLUGIN"
: > "$r/plugins/bad/a.sh"
XP=$r/xymon-plugin refused "[S35]" "a client file the checkout lacks" "bad's PLUGIN file names 'missing.sh' for its client part" install --client bad XYMONHOME="$c"
XP=$r/xymon-plugin refused "[S35]" "a client file the checkout lacks, another named first" "names 'missing.sh'" install --client xymon-plugin bad XYMONHOME="$c"

# A path with a quote in it: the command a refusal gives, run as printed,
# acts on that tree.
qc="$work/it's/client"; client_tree "$qc"
refused "[S24]" "no part on a client's tree with a quote in its path" "whose part is named" install xymon-plugin XYMONHOME="$qc"
cmd=${out##*whose part is named: }
cmd=${cmd#./xymon-plugin }
eval "set -- $cmd" || fail "[S24] the command given for a path with a quote is no shell command: $cmd"
x "$@"
[ "$rc" -eq 0 ] || fail "[S24] the command given for a path with a quote failed: $cmd: $out"
assert_file_exists "$qc/ext/xymon-plugin/VERSION"
x remove --client xymon-plugin XYMONHOME="$qc"

# The installation used last that cannot be written: said, the run done.
: > "$work/cfg-file"
XDG_CONFIG_HOME="$work/cfg-file" x install --client xymon-plugin XYMONHOME="$c"
[ "$rc" -eq 0 ] || fail "[S25] an installation used last that cannot be written failed the run: $out"
assert_contains "could not remember $c as the installation used last in $work/cfg-file/xymon-plugin" "$out" "[S25] an installation used last that cannot be written is said"
x remove --client xymon-plugin XYMONHOME="$c"

pass "a client part installs, updates and removes in a standalone client's tree, either layout, writing only ext/NAME and its manual page's link; a tree of the other kind, no part on a client's tree, two parts, enable, --venv, DESTDIR, a server's own client or one in doubt, and an ext/ not the person's are refused, changing nothing; detection offers the client trees and the one used last"
