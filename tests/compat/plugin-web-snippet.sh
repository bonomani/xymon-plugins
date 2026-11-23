#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-web-snippet.sh
#
# A plugin's web server snippets, the conf: line of its PLUGIN, are
# installed in ext/PLUGIN, where removing the plugin, or ext/PLUGIN by hand,
# takes them away; the web server includes them in a way that skips a file
# that is gone. An admin's edit survives an install. A snippet an older version shipped, found
# unedited, takes this version's -- recognised under any tree, its path
# put back as @XYMONHOME@ and @XYMONRUNDIR@; an edited one is kept, and said to differ. A tree whose path a web server's
# configuration may not take as it is is said. The relay socket they name
# is in Xymon's runtime directory, read from the server's xymonserver.cfg:
# XYMONRUNDIR, or XYMONSERVERLOGS where it is empty; where it is no path the
# install can read, @XYMONRUNDIR@ stays, and the install says so. A snippet
# byte for byte as the install before wrote it, kept in ext/PLUGIN/.shipped,
# is unedited though the runtime directory moved since. An install that
# adds or replaces a snippet, and an uninstall, say to reload the web
# server; one that changes none says nothing of it.
#
# Installed into a scratch directory. That Apache's IncludeOptional and the
# wildcard include of nginx and lighttpd skip a missing file is the web
# servers' own behaviour, not run here.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
home=$work/server
server_tree "$home"
snippets=$(sed -n 's/^conf: *//p' "$ROOT/plugins/xymonapi/PLUGIN")
[ -n "$snippets" ] || fail "plugins/xymonapi/PLUGIN names no snippet"

# install LOG -- install, or update once installed.
install() { v=install; [ -d "$home/ext/xymonapi" ] && v=update
	"$ROOT/xymon-plugin" "$v" --server xymonapi XYMONHOME="$home" MANDIR="$work/man" >"$work/$1.log" 2>&1 \
	|| fail "install-server ($1) failed: $(tail -n 5 "$work/$1.log")"; }

# shipped SNIPPET HOME [RUNDIR] -- a snippet as shipped, @XYMONHOME@ filled
# in as the task file's is, and @XYMONRUNDIR@, HOME/run by default, as
# server_tree writes it.
shipped() { sed -e "s|@XYMONHOME@|$2|g" -e "s|@XYMONRUNDIR@|${3-$2/run}|g" "$1"; }
install first
for c in $snippets; do
	shipped "$ROOT/plugins/xymonapi/$c" "$home" > "$work/shipped"
	cmp -s "$work/shipped" "$home/ext/xymonapi/$c" || fail "[S16] $c is not in ext/xymonapi as shipped, @XYMONHOME@ filled in"
	grep -q '@XYMON' "$home/ext/xymonapi/$c" && fail "[S16] $c still names a placeholder"
done
assert_contains "$home/run/xymonapi/relay.sock" "$(cat "$home/ext/xymonapi/xymonapi-nginx.conf")" \
	"[S22] the snippet names the relay socket in XYMONRUNDIR, from xymonserver.cfg"
assert_contains "IncludeOptional" "$(cat "$work/first.log")" "[S16] the install says to include it with IncludeOptional"
assert_contains "reload the web server" "$(cat "$work/first.log")" "[S16] a first install says to reload the web server"
assert_contains "register unix:$home/run/xymonapi/local/api.sock" "$(cat "$work/first.log")" "[S22] the install prints the API's socket, Xymon's runtime directory read"

echo "# the admin's port" >> "$home/ext/xymonapi/xymonapi-nginx.conf"
cp "$home/ext/xymonapi/xymonapi-nginx.conf" "$work/edited"
install again
cmp -s "$work/edited" "$home/ext/xymonapi/xymonapi-nginx.conf" || fail "[S16] an install undid the admin's edit to the nginx snippet"
for f in "$home"/ext/.xymon-plugin.*; do [ ! -e "$f" ] || fail "[S16] the directory the snippet was set aside in was left in ext/: $f"; done
assert_not_contains "reload the web server" "$(cat "$work/again.log")" "[S16] an install that changes no snippet says nothing of a reload"

"$ROOT/xymon-plugin" remove --server xymonapi XYMONHOME="$home" MANDIR="$work/man" >"$work/gone.log" 2>&1 || fail "uninstall-server failed"
assert_contains "reload the web server" "$(cat "$work/gone.log")" "[S16] an uninstall says to reload the web server"
for c in $snippets; do
	[ -e "$home/ext/xymonapi/$c" ] && fail "[S16] uninstall-server left $c"
done

# A kept snippet that is, byte for byte, one an older version shipped --
# its PLUGIN file's conf-stock line gives it by cksum -- was never edited:
# the install puts this version's in its place. One edited is kept, and
# said to differ. Run from a copy of the checkout, its PLUGIN file given
# such a line for a made-up older nginx snippet.
repo=$work/repo
mkdir -p "$repo"
cp -R "$ROOT/xymon-plugin" "$ROOT/LICENSE" "$ROOT/plugins" "$repo/"
printf '# an older version of the nginx snippet\nlocation /xymon/api/ { proxy_pass http://127.0.0.1:1986/xymon/api/; }\n' > "$work/stock-old"
echo "conf-stock: xymonapi-nginx.conf $(cksum < "$work/stock-old" | cut -d' ' -f1,2)" >> "$repo/plugins/xymonapi/PLUGIN"
home2=$work/server2
server_tree "$home2"
install2() { v=install; [ -d "$home2/ext/xymonapi" ] && v=update
	"$repo/xymon-plugin" "$v" --server xymonapi XYMONHOME="$home2" MANDIR="$work/man2" >"$work/$1.log" 2>&1 \
	|| fail "install-server ($1) failed: $(tail -n 5 "$work/$1.log")"; }
install2 fresh
cp "$work/stock-old" "$home2/ext/xymonapi/xymonapi-nginx.conf"
install2 stock
shipped "$repo/plugins/xymonapi/xymonapi-nginx.conf" "$home2" > "$work/shipped"
cmp -s "$work/shipped" "$home2/ext/xymonapi/xymonapi-nginx.conf" \
	|| fail "[S16] an older version's snippet, unedited, was not replaced by this version's"
assert_contains "unedited, is replaced" "$(cat "$work/stock.log")" "[S16] and the install says so"
{ cat "$work/stock-old"; echo "# the admin's"; } > "$home2/ext/xymonapi/xymonapi-nginx.conf"
cp "$home2/ext/xymonapi/xymonapi-nginx.conf" "$work/edited2"
install2 edited
cmp -s "$work/edited2" "$home2/ext/xymonapi/xymonapi-nginx.conf" || fail "[S16] an edited older snippet was replaced"
# This version's is the one the install before wrote: nothing to merge, so
# nothing said and nothing beside it (S7).
assert_not_contains "xymonapi-nginx.conf is kept" "$(cat "$work/edited.log")" "[S16] kept, with nothing to say when this version did not change it"
assert_not_contains "xymonapi-nginx.conf, unedited" "$(cat "$work/edited.log")" "[S16] nor said unedited"
[ ! -e "$home2/ext/xymonapi/xymonapi-nginx.conf.new" ] || fail "[S16] a NAME.new when this version did not change the snippet"
shipped "$repo/plugins/xymonapi/xymonapi-nginx.conf" "$home2" > "$home2/ext/xymonapi/xymonapi-nginx.conf"
install2 same
assert_not_contains "xymonapi-nginx.conf" "$(cat "$work/same.log")" "[S16] a snippet as this version ships it is not spoken of"

# This version's snippets, installed under two different trees, are both
# recognised later as shipped: a next version listing this one's template
# by cksum replaces them. The copy of the checkout plays the next version,
# its nginx snippet changed and this one's listed.
next=$work/next
mkdir -p "$next"
cp -R "$ROOT/xymon-plugin" "$ROOT/LICENSE" "$ROOT/plugins" "$next/"
echo "conf-stock: xymonapi-nginx.conf $(cksum < "$ROOT/plugins/xymonapi/xymonapi-nginx.conf" | cut -d' ' -f1,2)" >> "$next/plugins/xymonapi/PLUGIN"
echo "# the next version's" >> "$next/plugins/xymonapi/xymonapi-nginx.conf"
for h in "$work/treeA" "$work/tree B"; do
	server_tree "$h"
	"$ROOT/xymon-plugin" install --server xymonapi XYMONHOME="$h" MANDIR="$work/manA" >/dev/null 2>&1 || fail "install-server under $h failed"
	"$next/xymon-plugin" update --server xymonapi XYMONHOME="$h" MANDIR="$work/manA" >"$work/next.log" 2>&1 || fail "the next version's install under $h failed"
	assert_contains "# the next version's" "$(cat "$h/ext/xymonapi/xymonapi-nginx.conf")" "[S16] this version's snippet under $h is recognised as shipped, and replaced"
done
assert_contains "hold characters a web server's configuration may not take" "$(cat "$work/next.log")" \
	"[S16] a tree whose path a web server may not take as it is is said"

# Under a tree whose path is also part of the snippets' text -- /xymon in
# /xymon/api/ -- an older version's snippet, unedited, is still recognised.
# DESTDIR stages the tree at /xymon.
"$repo/xymon-plugin" install --server xymonapi XYMONHOME=/xymon DESTDIR="$work/stage" MANDIR=/usr/share/man >/dev/null 2>&1 \
	|| fail "install-server under DESTDIR at /xymon failed"
cp "$work/stock-old" "$work/stage/xymon/ext/xymonapi/xymonapi-nginx.conf"
"$repo/xymon-plugin" update --server xymonapi XYMONHOME=/xymon DESTDIR="$work/stage" MANDIR=/usr/share/man >"$work/xymon.log" 2>&1 \
	|| fail "install-server under DESTDIR at /xymon failed"
assert_not_contains "reload the web server" "$(cat "$work/xymon.log")" "[S16] under DESTDIR there is no web server to reload"
shipped "$repo/plugins/xymonapi/xymonapi-nginx.conf" /xymon @XYMONRUNDIR@ > "$work/shipped"
cmp -s "$work/shipped" "$work/stage/xymon/ext/xymonapi/xymonapi-nginx.conf" \
	|| fail "[S16] under /xymon, an older version's snippet was taken for edited"

# Where XYMONRUNDIR is empty, XYMONSERVERLOGS, as Xymon does; where it
# names a variable, the install cannot know it: @XYMONRUNDIR@ stays, said.
cfgcase() {
	h=$work/$1; server_tree "$h"
	printf '%s\noptional directory %s/etc/xymonserver.d\n' "$2" "$h" > "$h/etc/xymonserver.cfg"
	"$ROOT/xymon-plugin" install --server xymonapi XYMONHOME="$h" MANDIR="$work/man$1" >"$work/$1.log" 2>&1 || fail "install-server ($1) failed"
	cat "$h/ext/xymonapi/xymonapi-nginx.conf"
}
assert_contains "/var/log/xymon/xymonapi/relay.sock" "$(cfgcase logs 'XYMONRUNDIR=""
XYMONSERVERLOGS="/var/log/xymon"    # Logs')" "[S22] with XYMONRUNDIR empty, the snippet names XYMONSERVERLOGS"
assert_contains "/run/xymon/xymonapi/relay.sock" "$(cfgcase plain 'XYMONRUNDIR=/run/xymon')" "[S22] an unquoted XYMONRUNDIR is read"
assert_contains "@XYMONRUNDIR@/xymonapi/relay.sock" "$(cfgcase var 'XYMONRUNDIR="$XYMONVAR/run"')" "[S22] one that names a variable is left as @XYMONRUNDIR@"
assert_contains "put Xymon's runtime directory in its place" "$(cat "$work/var.log")" "[S22] and the install says so"
assert_not_contains "register unix:" "$(cat "$work/var.log")" "[S22] and gives no socket path, nor a command, it cannot know"
assert_not_contains "<" "$(cat "$work/var.log")" "[S22] nor a placeholder to type"
# Set again in xymonserver.d/, which Xymon reads after xymonserver.cfg: that
# value wins; an editor's backup there is left out, as Xymon leaves it.
h=$work/dropin; server_tree "$h"
mkdir -p "$h/etc/xymonserver.d"
echo 'XYMONRUNDIR="/run/xymon"' > "$h/etc/xymonserver.d/local.cfg"
echo 'XYMONRUNDIR="/backup/run"' > "$h/etc/xymonserver.d/local.cfg~"
"$ROOT/xymon-plugin" install --server xymonapi XYMONHOME="$h" MANDIR="$work/mandropin" >"$work/dropin.log" 2>&1 || fail "install-server (dropin) failed"
assert_contains "/run/xymon/xymonapi/relay.sock" "$(cat "$h/ext/xymonapi/xymonapi-nginx.conf")" "[S22] XYMONRUNDIR set in xymonserver.d/ wins over xymonserver.cfg's"

# The runtime directory moved: the snippets the install before wrote,
# unedited, name the old one, and take this install's; one edited is kept.
h=$work/moved; server_tree "$h"
"$ROOT/xymon-plugin" install --server xymonapi XYMONHOME="$h" MANDIR="$work/manmoved" >/dev/null 2>&1 || fail "install-server (moved) failed"
echo "# the admin's" >> "$h/ext/xymonapi/xymonapi-apache.conf"
cp "$h/ext/xymonapi/xymonapi-apache.conf" "$work/edited3"
mkdir -p "$h/etc/xymonserver.d"; echo 'XYMONRUNDIR="/run/xymon"' > "$h/etc/xymonserver.d/run.cfg"
"$ROOT/xymon-plugin" update --server xymonapi XYMONHOME="$h" MANDIR="$work/manmoved" >"$work/moved.log" 2>&1 || fail "install-server (moved again) failed"
assert_contains "/run/xymon/xymonapi/relay.sock" "$(cat "$h/ext/xymonapi/xymonapi-nginx.conf")" "[S16] a snippet as the install before wrote it, naming a runtime directory moved since, takes this install's"
assert_not_contains "xymonapi-nginx.conf is kept as yours" "$(cat "$work/moved.log")" "[S16] and is not said to be edited"
cmp -s "$work/edited3" "$h/ext/xymonapi/xymonapi-apache.conf" || fail "[S16] an edited snippet was replaced when the runtime directory moved"
assert_contains "xymonapi-apache.conf is kept as yours" "$(cat "$work/moved.log")" "[S16] and is said to differ"
assert_contains "xymonapi-apache.conf does not name /run/xymon" "$(cat "$work/moved.log")" "[S16] and to name a runtime directory that is not Xymon's"
assert_contains "reload the web server" "$(cat "$work/moved.log")" "[S16] and the install says to reload the web server"
# Edited still at the next install: the record of what was written is kept.
"$ROOT/xymon-plugin" update --server xymonapi XYMONHOME="$h" MANDIR="$work/manmoved" >"$work/moved2.log" 2>&1 || fail "install-server (moved, third) failed"
cmp -s "$work/edited3" "$h/ext/xymonapi/xymonapi-apache.conf" || fail "[S16] an edited snippet was replaced at a later install"
assert_not_contains "reload the web server" "$(cat "$work/moved2.log")" "[S16] nothing changed, no reload said"

# A snippet made a link, its target copied into .shipped/ as if the install
# had written it: the install writes a snippet anew, and not through the
# link -- the target is the Xymon user's to point, not the install's to write.
echo "an outside file" > "$work/victim"
ln -sf "$work/victim" "$h/ext/xymonapi/xymonapi-nginx.conf"
cp "$work/victim" "$h/ext/xymonapi/.shipped/xymonapi-nginx.conf"
"$ROOT/xymon-plugin" update --server xymonapi XYMONHOME="$h" MANDIR="$work/manmoved" >/dev/null 2>&1 || fail "install-server (link) failed"
assert_equal "an outside file" "$(cat "$work/victim")" "[S16] an install does not write through a snippet made a link"
[ -L "$h/ext/xymonapi/xymonapi-nginx.conf" ] && fail "[S16] the snippet made a link was left a link"

# The same with a hard link, which is a plain file: the target is not
# written either.
echo "another outside file" > "$work/victim2"
rm -f "$h/ext/xymonapi/xymonapi-lighttpd.conf"
ln "$work/victim2" "$h/ext/xymonapi/xymonapi-lighttpd.conf"
cp "$work/victim2" "$h/ext/xymonapi/.shipped/xymonapi-lighttpd.conf"
"$ROOT/xymon-plugin" update --server xymonapi XYMONHOME="$h" MANDIR="$work/manmoved" >/dev/null 2>&1 || fail "install-server (hard link) failed"
assert_equal "another outside file" "$(cat "$work/victim2")" "[S16] an install does not write through a snippet hard-linked to another file"
assert_contains "relay.sock" "$(cat "$h/ext/xymonapi/xymonapi-lighttpd.conf")" "[S16] and the snippet is this version's"

# A version that drops a snippet: the install says to reload. The copy of
# the checkout plays it, its PLUGIN naming one snippet fewer.
drop=$work/drop
mkdir -p "$drop"
cp -R "$ROOT/xymon-plugin" "$ROOT/LICENSE" "$ROOT/plugins" "$drop/"
sed 's/^\(conf: .*\) xymonapi-nginx.conf/\1/; s/^conf: xymonapi-nginx.conf /conf: /' "$drop/plugins/xymonapi/PLUGIN" > "$work/PLUGIN" && mv "$work/PLUGIN" "$drop/plugins/xymonapi/PLUGIN"
grep -q '^conf: .*xymonapi-nginx.conf' "$drop/plugins/xymonapi/PLUGIN" && fail "the test's copy still names the nginx snippet"
"$drop/xymon-plugin" update --server xymonapi XYMONHOME="$h" MANDIR="$work/manmoved" >"$work/drop.log" 2>&1 || fail "install-server (drop) failed"
[ -e "$h/ext/xymonapi/xymonapi-nginx.conf" ] && fail "[S16] a snippet this version has no more was left"
assert_contains "reload the web server" "$(cat "$work/drop.log")" "[S16] an install that drops a snippet says to reload the web server"

# With Xymon's xymoncmd in the tree, Xymon reads its configuration itself,
# as xymonlaunch does for the API: a value naming a variable is expanded.
# Under DESTDIR the stage's xymoncmd is not run, and the variable stays
# unknown.
if [ -x "${XYMON_SRC:-}/common/xymoncmd" ]; then
	h=$work/xcmd; server_tree "$h"
	cp "$XYMON_SRC/common/xymoncmd" "$h/bin/"
	printf 'XYMONVAR="/var/lib/xymon"\nXYMONRUNDIR="$XYMONVAR/run"\noptional directory %s/etc/xymonserver.d\n' "$h" > "$h/etc/xymonserver.cfg"
	"$ROOT/xymon-plugin" install --server xymonapi XYMONHOME="$h" MANDIR="$work/manxcmd" >"$work/xcmd.log" 2>&1 || fail "install-server (xymoncmd) failed"
	assert_contains "/var/lib/xymon/run/xymonapi/relay.sock" "$(cat "$h/ext/xymonapi/xymonapi-nginx.conf")" "[S22] xymoncmd expands a XYMONRUNDIR that names a variable"
	mkdir -p "$work/xstage/xh"; cp -R "$h/bin" "$h/etc" "$work/xstage/xh/"
	"$ROOT/xymon-plugin" install --server xymonapi XYMONHOME=/xh DESTDIR="$work/xstage" MANDIR=/usr/share/man >"$work/xstage.log" 2>&1 || fail "install-server (xymoncmd, DESTDIR) failed"
	assert_contains "@XYMONRUNDIR@/xymonapi/relay.sock" "$(cat "$work/xstage/xh/ext/xymonapi/xymonapi-nginx.conf")" "[S22] under DESTDIR the stage's xymoncmd is not run"
else
	echo "NOTE: the xymoncmd part was not run: no common/xymoncmd in XYMON_SRC"
fi

# xymonapi 4.0.0's snippets, with the relay under $XYMONHOME/tmp, are
# recognised unedited, by this version's conf-stock lines, and replaced.
h=$work/v4; server_tree "$h"
"$ROOT/xymon-plugin" install --server xymonapi XYMONHOME="$h" MANDIR="$work/manv4" >/dev/null 2>&1 || fail "install-server (v4) failed"
for c in $snippets; do
	sed -e 's|@XYMONRUNDIR@/xymonapi/relay.sock|@XYMONHOME@/tmp/xymonapi-relay/relay.sock|' -e "s|@XYMONHOME@|$h|g" \
		"$ROOT/plugins/xymonapi/$c" > "$h/ext/xymonapi/$c"
done
"$ROOT/xymon-plugin" update --server xymonapi XYMONHOME="$h" MANDIR="$work/manv4" >"$work/v4.log" 2>&1 || fail "install-server (v4 again) failed"
for c in $snippets; do
	shipped "$ROOT/plugins/xymonapi/$c" "$h" > "$work/shipped"
	cmp -s "$work/shipped" "$h/ext/xymonapi/$c" || fail "[S22] xymonapi 4.0.0's $c, unedited, was not replaced by this version's"
done

pass "a plugin's web server snippets live in ext/PLUGIN, keep the admin's edits, go with the plugin, an older version's, unedited, is replaced by this one's, and the relay socket they name is in Xymon's runtime directory"
