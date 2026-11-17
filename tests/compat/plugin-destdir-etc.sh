#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-destdir-etc.sh
#
# Under DESTDIR, nothing is written outside it. Xymon's own staged install
# may leave $DESTDIR$XYMONHOME/etc as an absolute link to where the
# configuration goes once installed -- /etc/xymon on Debian and with the
# RPM -- and a packager may link any directory of the stage the same way.
# Every path the install writes to is followed inside DESTDIR: an absolute
# link taken from DESTDIR, a relative one from where it lies, a .. stopping
# at DESTDIR, a chain of links each in turn, a link higher up the path as
# well as at its end. A link in a plugin's directory's place, where a file
# is set aside, or at the stage's plugins/ is removed, not followed; a
# command is written in place of a link; no virtualenv is made or used. The
# plugin's messages name the installed system's paths, not the stage's.
#
# The build host's directories are a scratch directory here, $host, which
# the staged links name by its absolute path, as /etc/xymon would be named.
# It is compared by content before and after each case.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
host=$work/host
stage=$work/stage
home=/usr/lib/xymon/server

mkdir -p "$host/etc" "$host/man" "$host/libexec" "$host/bin"
echo "the host's" > "$host/etc/xymonserver.cfg"
echo "the host's" > "$host/victim"
snap() { (cd "$host" && find . | sort && find . -type f -exec cksum {} + | sort); }
snap > "$work/host.before"
# check LABEL -- the host's directory is as it was.
check() {
	snap > "$work/host.after"
	cmp -s "$work/host.before" "$work/host.after" || fail "[S21] $1: wrote outside DESTDIR: $(diff "$work/host.before" "$work/host.after")"
}
# fresh -- an empty stage with Xymon's server tree in it.
fresh() { rm -rf "$stage"; mkdir -p "$stage$home"; }
# run ACTION SIDE [NAME=value...] -- xymon-plugin ACTION-SIDE xymonapi under DESTDIR.
run() {
	a=$1 s=$2; shift 2
	# install where installed already is an update.
	v=$a; [ "$v" = uninstall ] && v=remove
	go() { g=$1; shift; "$ROOT/xymon-plugin" "$g" "--$s" xymonapi XYMONHOME="$home" PREFIX=/opt/x MANDIR=/usr/share/man DESTDIR="$stage" "$@" \
		</dev/null >"$work/run.log" 2>&1; }
	if ! go "$v" "$@"; then
		{ [ "$v" = install ] && grep -q 'is installed already' "$work/run.log" && go update "$@"; } \
			|| fail "$a-$s under DESTDIR failed: $(tail -n 5 "$work/run.log")"
	fi
}
cycle() {   # cycle LABEL -- install, enable, disable, uninstall on the server
	for a in install enable disable uninstall; do run "$a" server; check "$a-server, $1"; done
}

# etc an absolute link, as Xymon's install makes it.
fresh; mkdir -p "$stage$host/etc"; ln -s "$host/etc" "$stage$home/etc"
run install server
# Its messages are for the installed system: its paths, not the stage's.
assert_contains "passwords: $home/etc/xymonpasswd," "$(cat "$work/run.log")" "[S21] a message names the path as installed"
assert_not_contains "$stage" "$(grep 'xymonpasswd' "$work/run.log")" "[S21] not the stage's"
run enable server
check "etc an absolute link"
assert_equal "$home/ext/xymonapi/tasks.cfg" "$(readlink "$stage$host/etc/tasks.d/xymonapi.cfg")" \
	"[S21] the task link lies where etc's link points inside DESTDIR, naming the task as installed"
cycle "etc an absolute link"

# etc a relative link climbing above DESTDIR: .. stops at it.
fresh; ln -s "../../../../../../../../../../../..$host/etc" "$stage$home/etc"
cycle "etc a relative link climbing out"
run install server; run enable server
[ -L "$stage$host/etc/tasks.d/xymonapi.cfg" ] || fail "[S21] a relative link climbing out is not followed inside DESTDIR"

# A chain: etc to /stage-etc, which in the stage links to the host's.
fresh; mkdir -p "$stage/stage-etc"; ln -s /stage-etc "$stage$home/etc"
rm -rf "$stage/stage-etc"; ln -s "$host/etc" "$stage/stage-etc"
cycle "a chain of absolute links"

# A link higher up the path: /usr itself.
rm -rf "$stage"; mkdir -p "$stage" "$stage$host/usr$home"
ln -s "$host/usr" "$stage/usr"
cycle "/usr an absolute link"

# ext an absolute link.
fresh; mkdir -p "$stage$host/ext"; ln -s "$host/ext" "$stage$home/ext"
cycle "ext an absolute link"

# MANDIR an absolute link.
fresh; mkdir -p "$stage/usr/share"; ln -s "$host/man" "$stage/usr/share/man"
run install server; check "install-server, MANDIR an absolute link"
[ -L "$stage$host/man/man8/xymonapi.8" ] || fail "[S21] the manual page is not where MANDIR's link points inside DESTDIR"
cycle "MANDIR an absolute link"

# A plugin's directory a link to a host directory holding a task file and
# a snippet: an update neither reads nor moves through it.
fresh; run install server
mkdir -p "$host/plugdir"; echo "host task" > "$host/plugdir/tasks.cfg"; echo "host snippet" > "$host/plugdir/xymonapi-apache.conf"
snap > "$work/host.before"
rm -rf "$stage$home/ext/xymonapi"; ln -s "$host/plugdir" "$stage$home/ext/xymonapi"
run install server; check "install-server, the plugin's directory a link"
[ -d "$stage$home/ext/xymonapi" ] && [ ! -L "$stage$home/ext/xymonapi" ] || fail "[S21] the plugin's directory is still a link"
# And a link where the task file is set aside.
ln -s "$host/plugdir" "$stage$home/ext/.xymonapi.tasks.cfg"
run install server; check "install-server, the set-aside task file a link"

# The stage /plugins serves, its plugins/ a link: an uninstall removes
# nothing through it.
fresh; run install server
mkdir -p "$host/plugins/xymonapi"; echo "host" > "$host/plugins/xymonapi/keep"
snap > "$work/host.before"
rm -rf "$stage$home/ext/xymon-plugins-dist/plugins"; ln -s "$host/plugins" "$stage$home/ext/xymon-plugins-dist/plugins"
run uninstall server; check "uninstall-server, the stage's plugins/ a link"

# Your own side: libexec and bin absolute links, and the command already
# there a link to a host file.
fresh; mkdir -p "$stage/opt/x"
ln -s "$host/libexec" "$stage/opt/x/libexec"
mkdir -p "$stage/opt/x/bin"; ln -s "$host/victim" "$stage/opt/x/bin/xymonapi-connect"
run install tools; check "install-tools, libexec a link and the command a link to a host file"
assert_file_exists "$stage$host/libexec/xymon-plugins/xymonapi/VERSION"
[ -f "$stage/opt/x/bin/xymonapi-connect" ] && [ ! -L "$stage/opt/x/bin/xymonapi-connect" ] \
	|| fail "[S21] the command was not written in place of the link"
run uninstall tools; check "uninstall-tools, libexec a link"
fresh; mkdir -p "$stage/opt/x"; ln -s "$host/bin" "$stage/opt/x/bin"
run install tools; check "install-tools, bin an absolute link"

# No virtualenv is made or used under DESTDIR, a link there or not.
fresh; run install server
ln -s "$host" "$stage$home/ext/venv"
rc=0; "$ROOT/xymon-plugin" update --server --venv XYMONHOME="$home" DESTDIR="$stage" </dev/null >"$work/venv.log" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "update --server --venv under DESTDIR failed: $(tail -n 3 "$work/venv.log")"
assert_contains "Under DESTDIR no virtualenv is made or used" "$(cat "$work/venv.log")" "[S21] under DESTDIR --venv makes no virtualenv, and says so"
check "update --server --venv under DESTDIR"

# A directory at tasks.d/NAME is no task link: enable refuses it.
fresh; run install server
mkdir -p "$stage$home/etc/tasks.d/xymonapi.cfg"
rc=0; "$ROOT/xymon-plugin" enable --server xymonapi XYMONHOME="$home" DESTDIR="$stage" </dev/null >"$work/en.log" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "enable-server over a directory at tasks.d/xymonapi succeeded"
assert_contains "is a directory" "$(cat "$work/en.log")" "and says why"

pass "under DESTDIR nothing is written outside it: absolute, relative, chained and higher links to etc, ext, MANDIR, libexec and bin are followed inside DESTDIR; links at a plugin directory, a set-aside file or the stage's plugins/ are removed, not followed; a command replaces a link; no virtualenv is made"
