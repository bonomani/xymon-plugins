#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-server-foreign.sh
#
# On the server, install, update and remove replace or take only a
# directory in ext/ an install left: VERSION and its PLUGIN copy naming the
# plugin and a server part, plain files, or VERSION alone from before the
# copy (S20); not MANIFEST, so an update cut short by pip is put right by
# the next. One cut short, the file in progress there naming it, is
# resumed by install and update, named or not, refused while the process
# it names runs, and refused by remove, naming that update; remove --all
# passes over it. Anything else at ext/NAME -- data and no VERSION, a
# PLUGIN and no VERSION as the plugin's directory copied by hand,
# a PLUGIN naming another, with no server part or a link, a VERSION that
# is a link, a link to the person's own directory -- is left as it is:
# each refusal changes nothing, modes included, and names the path; remove
# --all and update with none named pass over it, saying so, and what it
# says it needs blocks no removal; a
# need's directory stops the plugin needing it before anything changes.
# An install from before the copy is still updated and removed. Removing
# a plugin not there leaves a manual page that is no link of an install.
#
# A scratch server tree, and a copy of the checkout with plugins of its own.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
unset MAN SUDO_USER
export HOME="$work/home" XDG_CONFIG_HOME="$work/cfg" XYMON_PLUGINS_TREES_ONLY=1 XYMON_PLUGINS_TREES=
mkdir -p "$HOME" "$work/man"

# A copy of the checkout: sfree, a server part alone; sneed, needing
# xymon-plugin's; pipper, with a module no Python has.
r=$work/repo; mkdir -p "$r"
cp -R "$ROOT/xymon-plugin" "$ROOT/LICENSE" "$ROOT/plugins" "$r/"
for p in sfree sneed pipper; do
	mkdir -p "$r/plugins/$p"
	printf 'name: %s\nversion: 1.0.0\nsummary: a test\nserver-files: run.sh\n' "$p" > "$r/plugins/$p/PLUGIN"
	: > "$r/plugins/$p/run.sh"
done
printf 'server-needs: xymon-plugin\n' >> "$r/plugins/sneed/PLUGIN"
printf 'name: pipper\nversion: 1.0.0\nsummary: a test\nserver-files: run.sh requirements.txt\nserver-modules: nosuchmodule_xp\n' > "$r/plugins/pipper/PLUGIN"
echo nosuchmodule_xp > "$r/plugins/pipper/requirements.txt"

s=$work/server
server_tree "$s"; mkdir -p "$s/ext"
e=$s/ext

snap() { find "$work" -mindepth 1 \( -path "$work/snap*" -o -path "$work/log*" \) -prune -o -print | sort > "$work/$1"; }
# state FILE -- every path, its mode, each file's cksum, each link's target.
state() {
	snap "$1.p"
	while IFS= read -r p; do
		m=$(ls -ldn "$p" | awk '{ print $1 }')
		if [ -L "$p" ]; then printf '%s -> %s\n' "$p" "$(readlink "$p")"
		elif [ -f "$p" ]; then printf '%s %s %s\n' "$p" "$m" "$(cksum < "$p")"
		else printf '%s %s\n' "$p" "$m"; fi
	done < "$work/$1.p" > "$work/$1"
}
# x ARG... -- the copy's xymon-plugin ARG... on the scratch server, off a terminal.
x() { rc=0; out=$("$r/xymon-plugin" "$@" XYMONHOME="$s" MANDIR="$work/man" </dev/null 2>&1) || rc=$?; }
# refused LABEL WANT ARG... -- it fails, saying WANT, and nothing changed.
refused() {
	local l=$1 w=$2; shift 2
	state snap-r0
	x "$@"
	[ "$rc" -ne 0 ] || fail "[S20] $l: was taken: $out"
	assert_contains "$w" "$out" "[S20] $l: refused, saying so"
	state snap-r1
	cmp -s "$work/snap-r0" "$work/snap-r1" || fail "[S20] $l: the refusal changed something: $(diff "$work/snap-r0" "$work/snap-r1" || :)"
}
# repaired -- xymon-plugin's server part is in place, its MANIFEST naming
# its files.
repaired() {
	for f in xymon-plugin xymon-plugin-report.sh PLUGIN VERSION; do
		assert_file_exists "$d/$f"
		grep -q "	$f\$" "$d/MANIFEST" || fail "[S20] $1: MANIFEST does not name $f"
	done
}
# foreign NAME -- what refusals say of ext/NAME.
foreign() { echo "$e/$1 is not $1's server part as an install leaves it"; }
# all_refused LABEL NAME -- install, update and remove of NAME each refused.
all_refused() {
	refused "$1, install" "$(foreign "$2")" install --server "$2"
	refused "$1, install" "if nothing in it is wanted, remove it by hand: rm -rf $e/$2" install --server "$2"
	refused "$1, update" "$(foreign "$2")" update --server "$2"
	refused "$1, remove" "$(foreign "$2")" remove --server "$2"
}

# Data and no VERSION: install refused, before anything is written.
mkdir -p "$e/xymon-plugin"; echo precious > "$e/xymon-plugin/mydata"
refused "install over a directory with data" "$(foreign xymon-plugin)" install --server xymon-plugin
refused "remove of a directory with data" "$(foreign xymon-plugin)" remove --server xymon-plugin
# A need's directory no install left stops the plugin needing it.
refused "a need's directory no install left" "$(foreign xymon-plugin)" install --server sneed
[ ! -e "$e/sneed" ] || fail "[S20] the plugin needing a refused one was installed"
rm -rf "$e/xymon-plugin"

# A link to the person's own directory, a VERSION in it.
mkdir -p "$work/mine"; echo 0.0.1 > "$work/mine/VERSION"; echo precious > "$work/mine/data"
ln -s "$work/mine" "$e/xymon-plugin"
all_refused "a link to the person's own" xymon-plugin
[ -L "$e/xymon-plugin" ] || fail "[S20] the person's link was replaced"
rm -f "$e/xymon-plugin"

# An install, then each of its marks undone: no install's any more.
x install --server xymon-plugin
[ "$rc" -eq 0 ] || fail "[S20] install --server failed: $out"
d=$e/xymon-plugin
cp "$d/PLUGIN" "$work/PLUGIN.kept"
sed -e 's/^name: .*/name: other/' "$work/PLUGIN.kept" > "$d/PLUGIN"
all_refused "a PLUGIN naming another" xymon-plugin
sed -e '/^server-files:/d' "$work/PLUGIN.kept" > "$d/PLUGIN"
all_refused "a PLUGIN with no server part" xymon-plugin
rm -f "$d/PLUGIN"; ln -s "$work/PLUGIN.kept" "$d/PLUGIN"
all_refused "a PLUGIN that is a link" xymon-plugin
rm -f "$d/PLUGIN"; cp "$work/PLUGIN.kept" "$d/PLUGIN"
# A PLUGIN and no VERSION, as the plugin's directory copied by hand, is
# no install: nothing is guessed from a VERSION missing.
mv "$d/VERSION" "$work/VERSION.kept"
all_refused "a PLUGIN and no VERSION" xymon-plugin
echo "xymon-plugin in progress: other 1" > "$d/.xymon-plugin-in-progress"
all_refused "a PLUGIN and no VERSION, the file in progress naming another" xymon-plugin
rm -f "$d/.xymon-plugin-in-progress"
mv "$work/VERSION.kept" "$d/VERSION"
# Cut short, the file in progress there naming it, a process gone, with
# something set aside: remove refuses it, naming the update that resumes
# it; install and update resume it, with or without its VERSION.
cut() { echo "$e/$1 is an install of $1's server part cut short: ./xymon-plugin update --server $1 resumes it, with what it set aside"; }
inprog() { echo "xymon-plugin in progress: $1 $(sh -c 'echo $$')" > "$e/$1/.xymon-plugin-in-progress"; }
aside_with() { mkdir -p "$e/.xymon-plugin.$1"; printf 'xymon-plugin set aside: %s\n' "$1" > "$e/.xymon-plugin.$1/.xymon-plugin-set-aside"; echo mine > "$e/.xymon-plugin.$1/tasks.cfg"; }
inprog xymon-plugin; aside_with xymon-plugin
refused "an install cut short, remove" "$(cut xymon-plugin)" remove --server xymon-plugin
rm -f "$d/VERSION"
refused "an install cut short before its VERSION, remove" "$(cut xymon-plugin)" remove --server xymon-plugin
for a in install update; do
	rm -f "$d/VERSION"; inprog xymon-plugin
	x "$a" --server xymon-plugin
	[ "$rc" -eq 0 ] || fail "[S20] $a of an install cut short before its VERSION failed: $out"
	repaired "an install cut short before its VERSION, ${a}d"
	[ ! -e "$d/.xymon-plugin-in-progress" ] || fail "[S20] the $a resumed left the file in progress"
done
assert_equal mine "$(cat "$d/tasks.cfg")" "[S20] the resume put back what was set aside"
# Cut short with nothing set aside, nothing of the admin's -- a first
# install's, as its file in progress says --: remove takes it, and the
# refusals say it would; an update's, VERSION or not, remove refuses.
inprog xymon-plugin
refused "an update cut short before it set anything aside, remove" "$(cut xymon-plugin)" remove --server xymon-plugin
rm -f "$d/VERSION"
refused "an update cut short, no VERSION, remove" "$(cut xymon-plugin)" remove --server xymon-plugin
echo "xymon-plugin in progress: xymon-plugin $(sh -c 'echo $$') first" > "$d/.xymon-plugin-in-progress"
x verify --server xymon-plugin
assert_contains "nothing set aside: ./xymon-plugin update --server xymon-plugin resumes it, or ./xymon-plugin remove --server xymon-plugin takes it" "$out" "[S20] verify says remove takes one cut short with nothing set aside"
x remove --server xymon-plugin
[ "$rc" -eq 0 ] && [ ! -e "$d" ] || fail "[S20] remove did not take one cut short with nothing set aside: $out"
x install --server xymon-plugin
# Another run on it, its process alive and an xymon-plugin: refused, not
# resumed; a process alive that is no run of it, its number taken again:
# resumed.
mkdir -p "$work/fake"; printf '#!/bin/sh\nsleep 30\n' > "$work/fake/xymon-plugin"; chmod 755 "$work/fake/xymon-plugin"
"$work/fake/xymon-plugin" & alive=$!
echo "xymon-plugin in progress: xymon-plugin $alive" > "$d/.xymon-plugin-in-progress"
refused "an install still running" "an install or update of xymon-plugin is running, process $alive: wait for it to end; if no such run is going on, remove $d/.xymon-plugin-in-progress and run this again" update --server xymon-plugin
aside_with xymon-plugin
refused "a removal while one runs" "an install or update of xymon-plugin is running, process $alive" remove --server xymon-plugin
rm -r "$e/.xymon-plugin.xymon-plugin"
kill "$alive"; wait "$alive" 2>/dev/null || :
sleep 30 & other=$!
echo "xymon-plugin in progress: xymon-plugin $other" > "$d/.xymon-plugin-in-progress"
x update --server xymon-plugin
[ "$rc" -eq 0 ] || fail "[S20] a file in progress naming a process that is no run of it refused the update: $out"
[ ! -e "$d/.xymon-plugin-in-progress" ] || fail "[S20] the update resumed left the file in progress"
kill "$other"; wait "$other" 2>/dev/null || :
# MANIFEST gone, an update cut short after VERSION: still an install.
mv "$d/MANIFEST" "$work/MANIFEST.kept"
x update --server xymon-plugin
[ "$rc" -eq 0 ] || fail "[S20] an install with no MANIFEST was not updated: $out"
repaired "an install with no MANIFEST, updated"
mv "$d/VERSION" "$work/VERSION.kept"; ln -s "$work/VERSION.kept" "$d/VERSION"
all_refused "a VERSION that is a link" xymon-plugin
rm -f "$d/VERSION"; mv "$work/VERSION.kept" "$d/VERSION"
mv "$d" "$work/xp.kept"; ln -s "$work/xp.kept" "$d"
all_refused "an install that is a link" xymon-plugin
rm -f "$d"; mv "$work/xp.kept" "$d"

# remove --all and update with none named pass over it, sfree installed beside.
sed -e 's/^name: .*/name: other/' "$work/PLUGIN.kept" > "$d/PLUGIN"; echo precious > "$d/mydata"
x install --server sfree
[ "$rc" -eq 0 ] || fail "[S20] install --server sfree failed: $out"
mkdir -p "$e/sneed"; echo precious > "$e/sneed/data"
state snap-f0; grep -e "^${d}[ /]" -e "^$e/sneed[ /]" "$work/snap-f0" > "$work/snap-f0.f" || :
x update --server
[ "$rc" -eq 0 ] || fail "[S20] update --server beside directories no install left failed: $out"
assert_contains "Updated sfree" "$out" "[S20] update with none named updates an install"
assert_contains "$d is no install of xymon-plugin's: left as it is" "$out" "[S20] update with none named says what it passes over"
x remove --server --all
[ "$rc" -eq 0 ] || fail "[S20] remove --server --all beside directories no install left failed: $out"
assert_contains "$e/sneed is no install of sneed's: left as it is" "$out" "[S20] remove --all says what it passes over"
[ ! -e "$e/sfree" ] || fail "[S20] remove --server --all left an install"
state snap-f1; grep -e "^${d}[ /]" -e "^$e/sneed[ /]" "$work/snap-f1" > "$work/snap-f1.f" || :
cmp -s "$work/snap-f0.f" "$work/snap-f1.f" || fail "[S20] update or remove --all, none named, changed a directory no install left: $(diff "$work/snap-f0.f" "$work/snap-f1.f" || :)"
rm -rf "$d" "$e/sneed"
# What one no install left says it needs blocks no removal: remove --all
# takes xymon-plugin, beside a directory with a VERSION whose PLUGIN,
# naming another, says it needs it.
x install --server xymon-plugin
mkdir -p "$e/sneed"; echo 1.0.0 > "$e/sneed/VERSION"
printf 'name: other\nserver-files: run.sh\nserver-needs: xymon-plugin\n' > "$e/sneed/PLUGIN"
x remove --server --all
[ "$rc" -eq 0 ] || fail "[S20] a directory no install left blocked remove --all: $out"
[ ! -e "$d" ] || fail "[S20] remove --all left xymon-plugin"
assert_file_exists "$e/sneed/PLUGIN"
rm -rf "$e/sneed"

# An install from before the PLUGIN copy, VERSION alone: updated and removed.
x install --server xymon-plugin
rm -f "$d/PLUGIN" "$d/MANIFEST"
x update --server xymon-plugin
[ "$rc" -eq 0 ] || fail "[S20] an install from before the PLUGIN copy was not updated: $out"
repaired "an install from before the PLUGIN copy, updated"
rm -f "$d/PLUGIN" "$d/MANIFEST"
x update --server
[ "$rc" -eq 0 ] || fail "[S20] update with none named did not take an install from before the PLUGIN copy: $out"
assert_contains "Updated xymon-plugin" "$out" "[S20] update with none named takes an install from before the PLUGIN copy"
repaired "an install from before the PLUGIN copy, updated with none named"
rm -f "$d/PLUGIN" "$d/MANIFEST"
x remove --server xymon-plugin
[ "$rc" -eq 0 ] || fail "[S20] an install from before the PLUGIN copy was not removed: $out"
[ ! -e "$d" ] || fail "[S20] an install from before the PLUGIN copy was left"
# Absent: nothing to take, not a refusal; a manual page of the admin's
# own at its name, no link of an install, stays.
mkdir -p "$work/man/man8"; echo mine > "$work/man/man8/xymon-plugin.8"; cp "$work/man/man8/xymon-plugin.8" "$work/page.kept"
x remove --server xymon-plugin
[ "$rc" -eq 0 ] || fail "[S20] removing a plugin not there failed: $out"
cmp -s "$work/page.kept" "$work/man/man8/xymon-plugin.8" || fail "[S20] removing a plugin not there changed the admin's manual page"
rm -f "$work/man/man8/xymon-plugin.8"
# Nor, with nothing installed, what the plugins share: the virtualenv and
# the stage /plugins serves go only with an install removed (S8).
mkdir -p "$e/venv" "$e/xymon-plugins-dist/plugins"; : > "$e/venv/pyvenv.cfg"
state snap-v0
x remove --server xymon-plugin
[ "$rc" -eq 0 ] || fail "[S8] removing a plugin not there beside a virtualenv failed: $out"
x remove --server --all
[ "$rc" -eq 0 ] || fail "[S8] remove --all with nothing installed failed: $out"
state snap-v1
cmp -s "$work/snap-v0" "$work/snap-v1" || fail "[S8] a removal that removed no install took what the plugins share: $(diff "$work/snap-v0" "$work/snap-v1" || :)"
rm -rf "$e/venv" "$e/xymon-plugins-dist"
# From before the copy, its VERSION a link: no install's either.
x install --server xymon-plugin
rm -f "$d/PLUGIN" "$d/MANIFEST"
mv "$d/VERSION" "$work/VERSION.kept"; ln -s "$work/VERSION.kept" "$d/VERSION"
all_refused "a VERSION alone that is a link" xymon-plugin
rm -rf "$d"

# An update cut short by pip, MANIFEST not written: the next one goes.
# A stand-in Python, lacking the module, whose pip fails: nothing fetched.
real=$(command -v python3)
mkdir -p "$work/stand"
cat > "$work/stand/python3" <<EOF
#!/bin/sh
if [ "\$1" = -m ] && [ "\$2" = venv ]; then mkdir -p "\$3/bin" && cp "\$0" "\$3/bin/python3"; exit; fi
if [ "\$1" = -m ] && [ "\$2" = pip ]; then
	[ -e "$work/pip-ok" ] || { echo "pip: no network here" >&2; exit 3; }
	mkdir -p "$work/site" && : > "$work/site/nosuchmodule_xp.py"; exit 0
fi
case "\$2" in *sys.executable*) echo "\$0"; exit ;; esac
PYTHONPATH="$work/site" exec "$real" -S "\$@"
EOF
chmod 755 "$work/stand/python3"
: > "$work/stand/empty"; chmod 755 "$work/stand/empty"
XYMONAPI_PYTHON='' x install --server pipper PYTHON="$work/stand/empty"
[ "$rc" -eq 0 ] || fail "[S29] install --server pipper failed: $out"
XYMONAPI_PYTHON='' x update --server --venv pipper PYTHON="$work/stand/python3"
[ "$rc" -ne 0 ] || fail "[S29] pip failing was taken for success: $out"
assert_contains "pip could not install" "$out" "[S29] the update is cut short by pip"
# Again with --venv, pip now working: the update goes, the module in.
: > "$work/pip-ok"
XYMONAPI_PYTHON='' x update --server --venv pipper PYTHON="$work/stand/python3"
[ "$rc" -eq 0 ] || fail "[S20] the update after one cut short by pip failed: $out"
assert_contains "installing the modules of $e/pipper/requirements.txt" "$out" "[S20] the update resumed runs pip again"
"$e/venv/bin/python3" -c 'import nosuchmodule_xp' || fail "[S20] the module is not importable by the virtualenv's Python after the resumed update"
grep -q "	run.sh\$" "$e/pipper/MANIFEST" || fail "[S20] the resumed update's MANIFEST does not name run.sh"
x remove --server pipper
[ "$rc" -eq 0 ] || fail "[S20] removing pipper failed: $out"

# A name no plugin's can be is no install, nor a dependent: what its
# PLUGIN says it needs blocks no removal.
x install --server xymon-plugin
mkdir -p "$e/evil name"; echo 1.0.0 > "$e/evil name/VERSION"; : > "$e/evil name/MANIFEST"
printf 'name: evil name\nserver-files: run.sh\nserver-needs: xymon-plugin\n' > "$e/evil name/PLUGIN"
x remove --server xymon-plugin
[ "$rc" -eq 0 ] || fail "[S20] a directory named as no plugin can be blocked a removal: $out"
assert_file_exists "$e/evil name/PLUGIN"
rm -rf "$e/evil name"

# Named update of something there no install left: said as such, not as
# absent; absent, install is advised.
mkdir -p "$d"; echo precious > "$d/mydata"
refused "update of a directory with data and no VERSION" "$(foreign xymon-plugin)" update --server xymon-plugin
rm -rf "$d"
refused "update of a plugin not there" "xymon-plugin is not installed: ./xymon-plugin install --server xymon-plugin" update --server xymon-plugin

# verify, update with none named and remove --all see what in ext/ may be
# a plugin's: one cut short before its VERSION, and a directory with a
# VERSION. The site's own scripts there, a file and a directory with
# neither and no plugin's name, are not read: nothing said, nothing touched.
x install --server sfree
echo '#!/bin/sh' > "$e/check_raid.sh"; mkdir -p "$e/mes-scripts"; echo mine > "$e/mes-scripts/run"
v() { rc=0; out=$("$r/xymon-plugin" verify --server "$@" XYMONHOME="$s" MANDIR="$work/man" </dev/null 2>&1) || rc=$?; }
v
[ "$rc" -eq 0 ] || fail "[S20] verify with none named beside the site's own scripts exited $rc, not 0: $out"
for w in check_raid.sh mes-scripts; do assert_not_contains "$w" "$out" "[S20] verify says nothing of the site's $w"; done
mkdir -p "$d" "$e/thirdparty"; cp "$work/PLUGIN.kept" "$d/PLUGIN"; echo mine > "$d/tasks.cfg"; echo theirs > "$e/thirdparty/run"
inprog xymon-plugin; aside_with xymon-plugin
# And a plugin's directory copied by hand: no install, passed over.
cp -R "$r/plugins/sneed" "$e/sneed"
# A VERSION in it, and no PLUGIN: no install from before the copy, which
# only a plugin of this checkout can be.
echo 1.0 > "$e/thirdparty/VERSION"
v xymon-plugin
[ "$rc" -eq 3 ] || fail "[S20] verify of one cut short before its VERSION exited $rc, not 3: $out"
assert_contains "broken: xymon-plugin: $(cut xymon-plugin)" "$out" "[S20] verify says one cut short before its VERSION is one, naming the update that resumes it"
assert_not_contains "not installed" "$out" "[S20] and not that it is not installed"
v
[ "$rc" -eq 3 ] || fail "[S20] verify with none named exited $rc, not 3: $out"
assert_contains "broken: thirdparty: $(foreign thirdparty)" "$out" "[S20] verify with none named sees a third party's directory"
assert_contains "broken: xymon-plugin: $(cut xymon-plugin)" "$out" "[S20] and one cut short before its VERSION"
site() { grep -e "^$e/thirdparty[ /]" -e "^$e/sneed[ /]" -e "^$e/check_raid.sh " -e "^$e/mes-scripts[ /]" "$1" || :; }
state snap-t0; site "$work/snap-t0" > "$work/snap-t0.f"
x remove --server --all
[ "$rc" -eq 0 ] || fail "[S20] remove --all beside a third party's directory failed: $out"
assert_contains "$e/thirdparty is no install of thirdparty's: left as it is" "$out" "[S20] remove --all passes over a third party's directory, said"
assert_contains "$d is no install of xymon-plugin's: left as it is" "$out" "[S20] and one cut short before its VERSION"
assert_equal mine "$(cat "$d/tasks.cfg")" "[S20] remove --all leaves one cut short as it is"
for w in check_raid.sh mes-scripts; do assert_not_contains "$w" "$out" "[S20] remove --all says nothing of the site's $w"; done
x update --server
[ "$rc" -eq 0 ] || fail "[S20] update with none named beside a third party's directory failed: $out"
assert_contains "$e/thirdparty is no install of thirdparty's: left as it is" "$out" "[S20] update with none named passes over a third party's directory, said"
assert_contains "Updated xymon-plugin" "$out" "[S20] and resumes one cut short before its VERSION"
assert_contains "$e/sneed is no install of sneed's: left as it is" "$out" "[S20] and passes over a plugin's directory copied by hand"
assert_equal mine "$(cat "$d/tasks.cfg")" "[S20] keeping its task file"
for w in check_raid.sh mes-scripts; do assert_not_contains "$w" "$out" "[S20] update says nothing of the site's $w"; done
x remove --server --all
state snap-t1; site "$work/snap-t1" > "$work/snap-t1.f"
grep -q "^$e/check_raid.sh " "$work/snap-t1.f" && grep -q "^$e/mes-scripts/run " "$work/snap-t1.f" || fail "[S20] the site's own scripts are gone"
cmp -s "$work/snap-t0.f" "$work/snap-t1.f" || fail "[S20] update or remove --all changed what no install left: $(diff "$work/snap-t0.f" "$work/snap-t1.f" || :)"
rm -rf "$d" "$e/thirdparty" "$e/sneed" "$e/check_raid.sh" "$e/mes-scripts"

# A removal refused for a need refuses before anything goes, the stage
# /plugins serves included: two named, the second needed by one staying.
x install --server sneed sfree
[ "$rc" -eq 0 ] || fail "[S3] install --server sneed sfree failed: $out"
echo extra > "$e/xymon-plugins-dist/extra"
refused "removing two, one needed by a plugin that stays" "xymon-plugin is needed by sneed" remove --server sfree xymon-plugin
assert_file_exists "$e/sfree/VERSION"
x remove --server --all
rm -f "$e/xymon-plugins-dist/extra"

# The command to remove by hand, pasted, names the directory: a path with
# a space and a quote in it, quoted.
qs="$work/it's my/server"; server_tree "$qs"; mkdir -p "$qs/ext/xymon-plugin"; echo precious > "$qs/ext/xymon-plugin/mydata"
rc=0; out=$("$r/xymon-plugin" install --server xymon-plugin XYMONHOME="$qs" MANDIR="$work/man" </dev/null 2>&1) || rc=$?
[ "$rc" -ne 0 ] || fail "[S20] install over a directory with data, in a path with a space, was taken"
cmd=${out##*: rm -rf }
eval "set -- $cmd" || fail "[S20] the removal by hand is no shell command: $cmd"
[ "$#" -eq 1 ] && [ "$1" = "$qs/ext/xymon-plugin" ] || fail "[S20] the removal by hand does not name the directory as one word: $cmd"
rm -rf "$work/it's my"

# The dialogue offers neither install, update nor remove of a directory no
# install left, which each would refuse.
mkdir -p "$d"; echo 0.0.1 > "$d/VERSION"; echo precious > "$d/mydata"
sed -e 's/^name: .*/name: other/' "$work/PLUGIN.kept" > "$d/PLUGIN"
# menu -- the dialogue's menu on the scratch server, Enter doing nothing.
menu() {
	rc=0; out=$(XYMON_PLUGINS_TREES="$s" MANDIR="$work/man" PREFIX="$work/prefix" "${XYMONAPI_PYTHON:-python3}" "$ROOT/tests/lib/answer.py" \
		'Use it? [Y/n] ' '' 'What do you want to do? [0] ' '' -- "$r/xymon-plugin" 2>&1) || rc=$?
	[ "$rc" -eq 0 ] || fail "[S20] the dialogue beside a directory no install left failed: $out"
}
menu
assert_contains "-- broken: $(foreign xymon-plugin)" "$out" "[S20] the dialogue lists it, saying it is none"
for w in "install xymon-plugin on the server" "remove xymon-plugin from the server" "update the server's plugins"; do
	assert_not_contains "$w" "$out" "[S20] the dialogue does not offer to $w, refused"
done
# With an install beside, update is offered, not as repairing it.
x install --server sfree
menu
assert_contains "update the server's plugins" "$out" "[S20] the dialogue offers to update the install beside"
assert_not_contains "repairs xymon-plugin" "$out" "[S20] and not as repairing a directory no install left, passed over"
x remove --server sfree
# With no VERSION in it, installing it is not offered either.
rm -f "$d/VERSION"
menu
assert_not_contains "install xymon-plugin on the server" "$out" "[S20] the dialogue does not offer to install over a directory no install left"
rm -rf "$d"

pass "on the server, install, update and remove replace or take only a directory an install left, or one from before the PLUGIN copy; any other, a link among them, is refused before anything changes, passed over, said, by remove --all and update with none named, and needing nothing; an update cut short by pip is put right by the next"
