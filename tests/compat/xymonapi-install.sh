#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/xymonapi-xymon-plugin
#
# ./xymon-plugin install --server -- install, its older spelling, as well -- puts
# the API, with its client, in $XYMONHOME/ext/xymonapi/,
# the search beside it, its manual page in man8/, and its task in
# $XYMONHOME/ext/xymonapi/tasks.cfg, off -- no link from etc/tasks.d -- with
# ENVFILE naming that server's xymonserver.cfg. An install over one the admin
# edited and enabled leaves the file alone and the task on: turning it off
# would stop the API at the next upgrade, with nothing to say why. Without XYMONHOME it installs
# nothing and says so. The web server snippets go to ext/xymonapi, an
# admin's edits kept. ./xymon-plugin install --tools puts the MCP server and the search commands
# under PREFIX, with two commands in bin that run them from there, and
# xymonapi's client alone beside them, not the API. Installing
# again replaces each plugin's directory, so a file no longer shipped is
# gone; the client's virtualenv beside the
# plugins is kept. A plugin installed alone brings the plugins it needs
# beside it: xymonapi-rag on the server, the API with its client. The
# uninstall refuses a plugin another installed one needs, removes each
# plugin's files, manual page, task and snippets, and keeps the data,
# saying so; on a laptop it says what to undo by hand.
# install-client, uninstall-client and venv-client are refused, naming the
# tools action, and so is an action that names no side, naming the -server
# one; none installs anything.
#
# Installed into a scratch directory. The API is copied, not run; a Python
# (XYMONAPI_PYTHON, else python3) stands as a virtualenv's, so that the
# install keeps it. Uses the test helpers of the Xymon tree in XYMON_SRC.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
home=$work/server
server_tree "$home"

rc=0
"$ROOT/xymon-plugin" install --server --all MANDIR="$work/man" >"$work/nohome.log" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "xymon-plugin install --server without XYMONHOME succeeded"
assert_contains "XYMONHOME" "$(cat "$work/nohome.log")" "[S4] and it says what is missing"
[ -e "$work/man" ] && fail "[S4] xymon-plugin install --server without XYMONHOME installed something"

# Under a umask that would leave a new file readable by its owner alone: the
# task file must still be 644, like the others, whoever xymonlaunch runs as.
( umask 077 && "$ROOT/xymon-plugin" install --server --all XYMONHOME="$home" MANDIR="$work/man" ) >"$work/install.log" 2>&1 \
	|| fail "xymon-plugin install --server failed: $(tail -n 5 "$work/install.log")"

for f in app.py xymon.py xymonapi_client.py tokens.py openapi.yaml requirements.txt xymonapi.sh; do
	assert_file_exists "$home/ext/xymonapi/$f"
done
for f in xymonapi-rag/xymonrag.py xymonapi-rag/xymonapi-rag.sh xymonapi-rag/requirements.txt; do
	assert_file_exists "$home/ext/$f"
done
[ -x "$home/ext/xymonapi/xymonapi.sh" ] || fail "the launcher is not executable"
# xymon-plugin reads each plugin from its PLUGIN file, and names none but
# its own (plugin-generic.sh installs one no code knows).
for p in "$ROOT"/plugins/*/PLUGIN; do
	p=$(sed -n 's/^name: *//p' "$p")
	[ "$p" = xymon-plugin ] && continue
	grep -qw -- "$p" "$ROOT/xymon-plugin" && fail "[S1] xymon-plugin names the plugin $p"
done
# Each plugin records its version beside its files, X.Y.Z, the PLUGIN
# file's: from a checkout at a release tag as from any other (S2).
for p in xymonapi xymonapi-rag; do
	assert_file_exists "$home/ext/$p/VERSION"
	want=$(sed -n 's/^version: *//p' "$ROOT/plugins/$p/PLUGIN")
	assert_equal "$want" "$(cat "$home/ext/$p/VERSION")" "[S2] $p/VERSION holds its PLUGIN version"
done
assert_file_exists "$work/man/man8/xymonapi.8"

task=$home/ext/xymonapi/tasks.cfg
assert_file_exists "$task"
if [ -e "$home/etc/tasks.d/xymonapi.cfg" ] || [ -L "$home/etc/tasks.d/xymonapi.cfg" ]; then fail "[S5] the install turned the task on: etc/tasks.d/xymonapi.cfg is there"; fi
grep -q 'DISABLED' "$task" && fail "[S5] the task file carries DISABLED, which the link replaces: $(cat "$task")"
grep -q "^[[:space:]]*ENVFILE $home/etc/xymonserver.cfg\$" "$task" \
	|| fail "ENVFILE does not name this server's xymonserver.cfg: $(grep ENVFILE "$task")"
grep -q '@XYMONHOME@' "$task" && fail "@XYMONHOME@ was left unreplaced in $task"
mode=$(ls -lL "$task" | cut -c1-10)
assert_equal "-rw-r--r--" "$mode" "the task file's mode under umask 077"
# And every directory it made, readable and searchable by every user, as
# the Xymon user reads PLUGIN and VERSION and the web server /plugins.
closed=$(find "$home/ext" "$work/man" -type d ! -perm -0055)
assert_equal "" "$closed" "the directories made under umask 077 are readable by every user"

# An update replaces each plugin's directory: a file the new version no
# longer ships does not stay behind.
echo 'stale' > "$home/ext/xymonapi/gone.py"
echo 'stale' > "$home/ext/xymonapi-rag/gone.py"
# What an install made under umask 077 by an older installer left closed --
# ext/ and tasks.d/, a plugin's directory, /plugins' stage, a virtualenv --
# is opened again; a link in the virtualenv is not followed out of it. The
# virtualenv is one whose Python runs, so that the install keeps it.
mkdir -p "$home/ext/venv/bin" "$home/ext/venv/lib"
: > "$home/ext/venv/pyvenv.cfg"
ln -s "$(command -v "${XYMONAPI_PYTHON:-python3}")" "$home/ext/venv/bin/python3"
: > "$work/private"; chmod 600 "$work/private"
ln -s "$work/private" "$home/ext/venv/lib/outside"
# A hard link to it too, which a chmod would change for both names; and a
# setgid directory, as a group-shared tree has, closed like the rest.
ln "$work/private" "$home/ext/venv/lib/hard"
mkdir -p "$home/ext/venv/shared"; chmod 2700 "$home/ext/venv/shared"
# And what its owner may not use itself, or that is no file: left as it is.
mkdir -p "$home/ext/venv/odd/d0400"; chmod u=r,go= "$home/ext/venv/odd/d0400"
: > "$home/ext/venv/odd/f0010"; chmod u=,g=x,o= "$home/ext/venv/odd/f0010"
mkfifo "$home/ext/venv/odd/fifo"; chmod 600 "$home/ext/venv/odd/fifo"
chmod 700 "$home/ext/xymonapi" "$home/ext/xymon-plugins-dist" "$home/ext/xymon-plugins-dist/plugins" \
	"$home/ext/venv/lib" "$home/ext/venv/bin" "$home/ext/venv" "$home/ext" "$home/etc/tasks.d"
"$ROOT/xymon-plugin" update --server XYMONHOME="$home" MANDIR="$work/man" >"$work/update.log" 2>&1 \
	|| fail "installing over an install failed: $(tail -n 5 "$work/update.log")"
[ -d "$home/ext/venv/lib" ] || fail "the virtualenv, whose Python runs, was not kept: $(cat "$work/update.log")"
closed=$(find "$home/ext" "$home/etc/tasks.d" -type d ! -perm -0055 ! -path "$home/ext/venv/odd/d0400")
assert_equal "" "$closed" "an update opens what an install under umask 077 left closed"
odd=$(find "$home/ext/venv/odd/d0400" "$home/ext/venv/odd/f0010" "$home/ext/venv/odd/fifo" -prune \( -perm -0004 -o -perm -0001 \))
assert_equal "" "$odd" "what its owner may not use itself, and a fifo, are left closed"
[ -n "$(find "$work/private" -perm 0600)" ] || fail "a link in the virtualenv was followed or changed: $work/private is no longer 600"
[ -n "$(find "$home/ext/venv/shared" -prune -perm -2055)" ] || fail "a setgid directory was left closed"

# Where a chmod would fail -- what another user owns -- an open tree is not
# touched, so nothing is said; a closed one is said, with its owner. A
# chmod that refuses go+r and go+rx alone stands for that other owner.
# BusyBox's find runs its own chmod, not the one first on PATH: there this
# part cannot run.
findhelp=$(find --help 2>&1 || true)
case $findhelp in
*BusyBox*) ;;
*)
	mkdir -p "$work/stub"
	real_chmod=$(command -v chmod)
	printf '#!/bin/sh\ncase " $* " in *" go+r"*) exit 1 ;; esac\nexec %s "$@"\n' "$real_chmod" > "$work/stub/chmod"
	"$real_chmod" 755 "$work/stub/chmod"
	PATH="$work/stub:$PATH" "$ROOT/xymon-plugin" update --server XYMONHOME="$home" MANDIR="$work/man" >"$work/update.log" 2>&1 \
		|| fail "an update with chmod refusing go+r failed: $(tail -n 5 "$work/update.log")"
	assert_not_contains "could not open" "$(cat "$work/update.log")" "an open tree that could not be changed is left, and nothing said"
	chmod 700 "$home/ext/xymon-plugins-dist/plugins"
	PATH="$work/stub:$PATH" "$ROOT/xymon-plugin" update --server XYMONHOME="$home" MANDIR="$work/man" >"$work/update.log" 2>&1 \
		|| fail "an update with chmod refusing go+r failed: $(tail -n 5 "$work/update.log")"
	assert_contains "could not open all of $home/ext/xymon-plugins-dist to every user: run the update as its owner, $(id -un), to open it" \
		"$(cat "$work/update.log")" "a closed one that could not be opened is said, with its owner"
	[ -n "$(find "$home/ext/xymon-plugins-dist/plugins" -prune -perm 0700)" ] || fail "the stage was opened though chmod refused"
	chmod 755 "$home/ext/xymon-plugins-dist/plugins"
	;;
esac
rm -rf "$home/ext/venv"
[ -e "$home/ext/xymonapi/gone.py" ] && fail "[S7] a file no longer shipped stayed in ext/xymonapi after an update"
[ -e "$home/ext/xymonapi-rag/gone.py" ] && fail "a file no longer shipped stayed in ext/xymonapi-rag after an update"
assert_file_exists "$home/ext/xymonapi/app.py"
# The install stops a running API itself (xymonapi-auth.sh): with none
# running here it stops nothing, and asks no step of the admin.
assert_not_contains "Stopped" "$(cat "$work/update.log")" "with no API running, the install stops nothing"
assert_not_contains "pkill" "$(cat "$work/update.log")" "and asks no pkill of the admin"

# The admin enables the API, and the next install must not undo it.
echo '# mine' >> "$task"
cp "$task" "$work/enabled"
"$ROOT/xymon-plugin" enable --server xymonapi XYMONHOME="$home" >/dev/null 2>&1 || fail "enable-server xymonapi failed"
"$ROOT/xymon-plugin" install --server --all XYMONHOME="$home" MANDIR="$work/man" >"$work/reinstall.log" 2>&1 \
	|| fail "installing a second time failed: $(tail -n 5 "$work/reinstall.log")"
cmp -s "$work/enabled" "$task" \
	|| fail "[S7] a second install changed the task file the admin had enabled: $(cat "$task")"
[ -L "$home/etc/tasks.d/xymonapi.cfg" ] || fail "[S7] a second install turned off the task the admin had enabled"

# A server directory with a space, an & and a | in its name: the paths are
# quoted, and the replacement sed makes in the task files is escaped.
odd="$work/x y&z|w"
server_tree "$odd"
"$ROOT/xymon-plugin" install --server --all XYMONHOME="$odd" MANDIR="$work/man 2" >"$work/odd.log" 2>&1 \
	|| fail "xymon-plugin install --server into a directory with a space, & and | failed: $(tail -n 5 "$work/odd.log")"
assert_file_exists "$odd/ext/xymonapi/xymonapi.sh"
assert_file_exists "$work/man 2/man8/xymonapi.8"
grep -qF "ENVFILE $odd/etc/xymonserver.cfg" "$odd/ext/xymonapi/tasks.cfg" \
	|| fail "the task file does not name that directory as it is: $(grep ENVFILE "$odd/ext/xymonapi/tasks.cfg")"
grep -qF "ENVFILE $odd/etc/xymonserver.cfg" "$odd/ext/xymonapi-rag/tasks.cfg" \
	|| fail "the index task file does not name that directory as it is: $(grep ENVFILE "$odd/ext/xymonapi-rag/tasks.cfg")"

assert_file_exists "$home/ext/xymonapi/xymonapi-apache.conf"
grep -q 'ProxyPass ' "$home/ext/xymonapi/xymonapi-apache.conf" || fail "[S16] the Apache snippet has no ProxyPass"
grep -q 'proxy_pass ' "$home/ext/xymonapi/xymonapi-nginx.conf" || fail "[S16] the nginx snippet has no proxy_pass"
grep -q 'proxy.server' "$home/ext/xymonapi/xymonapi-lighttpd.conf" || fail "[S16] the lighttpd snippet has no proxy.server"
assert_contains "xymonapi's task is off: XYMONHOME=$home ./xymon-plugin enable --server xymonapi turns it on" "$(cat "$work/install.log")" "[S5] the install says what to do next"
echo "# mine" > "$home/ext/xymonapi/xymonapi-apache.conf"
"$ROOT/xymon-plugin" install --server --all XYMONHOME="$home" MANDIR="$work/man" >/dev/null 2>&1 || fail "a third install failed"
assert_equal "# mine" "$(cat "$home/ext/xymonapi/xymonapi-apache.conf")" "[S7] an edited Apache snippet is kept"

# One plugin alone brings what it needs beside it: on the server,
# xymonapi-rag needs the API that serves its index, and its client it reads
# the API with.
alone=$work/alone
server_tree "$alone"
"$ROOT/xymon-plugin" install --server xymonapi-rag XYMONHOME="$alone" MANDIR="$work/man-alone" >"$work/alone.log" 2>&1 \
	|| fail "xymon-plugin install --server of xymonapi-rag alone failed: $(tail -n 5 "$work/alone.log")"
for p in xymonapi xymonapi-rag; do
	[ -f "$alone/ext/$p/VERSION" ] || fail "[S3] installing xymonapi-rag alone did not install $p, which it needs"
done

# Needs are read part by part: a server install reads server-needs:, the
# same part of the plugin named unless NAME:part names another. A part the
# install cannot hold, and a part that is none, are refused before anything
# changes. A copy of the checkout plays each.
needs_case() { # LINE LOG -- install-server xymonapi-agent with LINE as its server-needs:
	r=$work/needs-$2; rm -rf "$r"; mkdir -p "$r"
	cp -R "$ROOT/xymon-plugin" "$ROOT/LICENSE" "$ROOT/plugins" "$r/"
	sed "s|^server-needs: .*|server-needs: $1|" "$ROOT/plugins/xymonapi-agent/PLUGIN" > "$r/plugins/xymonapi-agent/PLUGIN"
	h=$work/needs-home-$2; server_tree "$h"
	rc=0; "$r/xymon-plugin" install --server xymonapi-agent XYMONHOME="$h" MANDIR="$work/man-$2" </dev/null >"$work/needs-$2.log" 2>&1 || rc=$?
}
needs_case "xymonapi-mcp:server" explicit
[ "$rc" -eq 0 ] || fail "[S3] server-needs: naming the server part explicitly failed: $(tail -n 3 "$work/needs-explicit.log")"
[ -f "$h/ext/xymonapi-mcp/VERSION" ] || fail "[S3] and did not install the part it names"
needs_case "xymonapi-mcp:tools" cross
[ "$rc" -ne 0 ] || fail "[S3] a server part needing a tools part, which a server install cannot hold, was installed"
assert_contains "cannot hold" "$(cat "$work/needs-cross.log")" "[S3] and the refusal says why"
[ -e "$h/ext/xymonapi-agent" ] && fail "[S3] the refused plugin was installed anyway"
needs_case "xymonapi-mcp:nopart" nopart
[ "$rc" -ne 0 ] || fail "[S3] a need naming no part was taken"
assert_contains "is no part" "$(cat "$work/needs-nopart.log")" "[S3] and the refusal says so"

# xymon-plugin's verbs. An old action is refused, naming the new form; a
# client part on a server's tree, naming --server. Off a terminal, a verb
# that changes something needs its part named; install and remove need a
# plugin named, or --all; install refuses a plugin installed, update one
# that is not; enable refuses the tools, which have no task; one part at a
# time. Nothing is installed by any of these.
refused() { # WANT ARG... -- xymon-plugin ARG... fails, saying WANT
	w=$1; shift
	rc=0; "$ROOT/xymon-plugin" "$@" XYMONHOME="$home" PREFIX="$work/refused" MANDIR="$work/refused" </dev/null >"$work/refused.log" 2>&1 || rc=$?
	[ "$rc" -ne 0 ] || fail "xymon-plugin $* was not refused"
	assert_contains "$w" "$(cat "$work/refused.log")" "[S24] xymon-plugin $*: refused, saying so"
}
r() { refused "$@"; }
r "install-server is now: ./xymon-plugin install --server" install-server xymonapi
r "uninstall-tools is now: ./xymon-plugin remove --tools" uninstall-tools xymonapi
r "install-client is now: ./xymon-plugin install --client" install-client xymonapi
r "a server's tree takes the server part, --server" install --client xymon-plugin
r "names no part" install xymonapi
r "name the plugins to install, or --all" install --server
r "name the plugins to remove, or --all" remove --tools
r "is installed already" install --server xymonapi
r "is not installed: ./xymon-plugin install --tools xymonapi-agent" update --tools xymonapi-agent
r "the tools have no task" enable --tools xymonapi
r "one part at a time" install --server --tools xymonapi
r "./xymon-plugin install --tools xymonapi" install --server --tools xymonapi
r "status, with none, covers the server part and the tools" status --server --tools
r "--all, or plugins named: not both" install --server --all xymonapi
[ -e "$work/refused" ] && fail "[S24] a refused verb installed something"
# Run as root, the tools are refused without PREFIX or DESTDIR: they would
# go in root's home. The lanes run as root; elsewhere this is not checked.
if [ "$(id -u)" -eq 0 ]; then
	rc=0; "$ROOT/xymon-plugin" install --tools xymonapi </dev/null >"$work/root.log" 2>&1 || rc=$?
	[ "$rc" -ne 0 ] || fail "[S24] install --tools as root, with no PREFIX, was not refused"
	assert_contains "not root's" "$(cat "$work/root.log")" "[S24] and says why"
fi
# A plugin needed and installed already is passed over, said, and the one
# named installed: xymonapi-mcp on the tree xymonapi-rag brought xymonapi to.
"$ROOT/xymon-plugin" install --server xymonapi-mcp XYMONHOME="$alone" MANDIR="$work/man-alone" </dev/null >"$work/skip.log" 2>&1 \
	|| fail "install --server xymonapi-mcp beside an installed xymonapi failed: $(tail -n 3 "$work/skip.log")"
assert_contains "xymonapi is installed already" "$(cat "$work/skip.log")" "[S24] a plugin needed and installed is passed over, said"
[ -f "$alone/ext/xymonapi-mcp/VERSION" ] || fail "[S24] and the plugin named is installed"

# The tools side: no Xymon here, PREFIX with a space in its name.
prefix="$work/client prefix"
"$ROOT/xymon-plugin" install --tools --all PREFIX="$prefix" >"$work/client.log" 2>&1 \
	|| fail "[S4] xymon-plugin install --tools failed: $(tail -n 5 "$work/client.log")"
# An update replaces the plugin's directory there too, and leaves the
# virtualenv an earlier setup made beside the plugins alone.
mkdir -p "$prefix/libexec/xymon-plugins/venv" && : > "$prefix/libexec/xymon-plugins/venv/kept"
: > "$prefix/libexec/xymon-plugins/xymonapi-rag/gone.py"
"$ROOT/xymon-plugin" update --tools PREFIX="$prefix" >"$work/client2.log" 2>&1 \
	|| fail "xymon-plugin install --tools a second time failed: $(tail -n 5 "$work/client2.log")"
[ -e "$prefix/libexec/xymon-plugins/xymonapi-rag/gone.py" ] && fail "a file no longer shipped stayed in the client's xymonapi-rag"
assert_contains "Updated xymonapi-rag " "$(cat "$work/client2.log")" "[S24] update says it updated, not installed"
assert_not_contains "Next" "$(cat "$work/client2.log")" "[S24] and gives no first install's help"
assert_file_exists "$prefix/libexec/xymon-plugins/venv/kept"
for f in xymonapi-mcp/server.py xymonapi-mcp/xymonapi-mcp.sh xymonapi/xymonapi_client.py xymonapi/xymonapi-connect.sh \
         xymonapi-rag/xymonrag.py xymonapi-rag/xymonapi-rag.sh xymonapi-rag/requirements.txt xymonapi-mcp/VERSION xymonapi-rag/VERSION; do
	assert_file_exists "$prefix/libexec/xymon-plugins/$f"
done
assert_file_exists "$prefix/share/man/man1/xymonapi-mcp.1"
assert_file_exists "$prefix/share/man/man1/xymonapi-rag.1"
assert_file_exists "$prefix/share/man/man1/xymonapi-connect.1"
[ -x "$prefix/bin/xymonapi-connect" ] || fail "bin/xymonapi-connect is not executable"
[ -x "$prefix/bin/xymonapi-mcp" ] || fail "bin/xymonapi-mcp is not executable"
[ -x "$prefix/bin/xymonapi-rag" ] || fail "bin/xymonapi-rag is not executable"
grep -qF "\"$prefix/libexec/xymon-plugins/xymonapi-rag/xymonapi-rag.sh\"" "$prefix/bin/xymonapi-rag" \
	|| fail "bin/xymonapi-rag does not run the installed launcher, quoted: $(cat "$prefix/bin/xymonapi-rag")"
[ -e "$prefix/libexec/xymon-plugins/xymonapi/app.py" ] && fail "[S4] install-tools installed the API"
# The installed xymonapi-rag runs: --help needs Python alone, and finds
# xymonapi_client.py in xymonapi/ beside it, as in the repository.
if command -v "${XYMONAPI_PYTHON:-python3}" >/dev/null 2>&1; then
	XYMONAPI_PYTHON="${XYMONAPI_PYTHON:-python3}" "$prefix/bin/xymonapi-rag" --help > "$work/help.out" 2>&1 \
		|| fail "the installed xymonapi-rag --help failed: $(cat "$work/help.out")"
	assert_contains 'search' "$(cat "$work/help.out")" "and names its commands"
fi

# Uninstalling: a plugin another installed one needs is refused, naming it;
# the whole side removes each plugin's files, manual page and task, keeps
# the web server snippets and the data, and says so. On a laptop it also
# says what register did besides.
for p in xymonapi; do
	rc=0
	"$ROOT/xymon-plugin" remove --server "$p" XYMONHOME="$home" MANDIR="$work/man" >"$work/un-$p.log" 2>&1 || rc=$?
	[ "$rc" -ne 0 ] || fail "[S3] uninstalling $p while xymonapi-mcp and xymonapi-rag need it succeeded"
	# Any of those installed that need it; the first, by name, is xymonapi-mcp.
	assert_contains "$p is needed by xymonapi-mcp" "$(cat "$work/un-$p.log")" "[S3] and says which plugin needs $p"
	assert_file_exists "$home/ext/$p/VERSION"
done
"$ROOT/xymon-plugin" remove --server --all XYMONHOME="$home" MANDIR="$work/man" >"$work/uninstall.log" 2>&1 \
	|| fail "xymon-plugin remove --server failed: $(tail -n 5 "$work/uninstall.log")"
for f in ext/xymonapi ext/xymonapi-mcp ext/xymonapi-rag etc/tasks.d/xymonapi.cfg etc/tasks.d/xymonapi-rag.cfg; do
	if [ -e "$home/$f" ] || [ -L "$home/$f" ]; then fail "[S8] xymon-plugin remove --server left $f"; fi
done
{ [ -e "$work/man/man8/xymonapi.8" ] || [ -L "$work/man/man8/xymonapi.8" ]; } && fail "[S8] xymon-plugin remove --server left the manual page xymonapi.8"
[ -e "$home/ext/xymon-plugins-dist" ] && fail "[S8] remove --server --all left the stage served at /plugins, with no plugin in it"
{ [ -e "$work/man/man1/xymonapi-rag.1" ] || [ -L "$work/man/man1/xymonapi-rag.1" ]; } && fail "xymon-plugin remove --server left the manual page xymonapi-rag.1"
assert_contains "web server snippets went with ext/xymonapi" "$(cat "$work/uninstall.log")" "[S16] uninstall says the snippets went with the plugin"
assert_contains "XYMONAPI_TOKENS" "$(cat "$work/uninstall.log")" "[S10] and that the tokens file is kept"

rc=0
"$ROOT/xymon-plugin" remove --tools xymonapi PREFIX="$prefix" >"$work/unc-api.log" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "uninstall-tools of xymonapi's client while xymonapi-mcp needs it succeeded"
assert_contains "needed by xymonapi-mcp" "$(cat "$work/unc-api.log")" "and says which plugin needs it"
"$ROOT/xymon-plugin" remove --tools --all PREFIX="$prefix" >"$work/unclient.log" 2>&1 \
	|| fail "xymon-plugin remove --tools failed: $(tail -n 5 "$work/unclient.log")"
[ -e "$prefix/libexec/xymon-plugins" ] && fail "xymon-plugin remove --tools left $prefix/libexec/xymon-plugins: $(ls -A "$prefix/libexec/xymon-plugins")"
for f in bin/xymonapi-mcp bin/xymonapi-rag share/man/man1/xymonapi-mcp.1 share/man/man1/xymonapi-rag.1; do
	[ -e "$prefix/$f" ] && fail "xymon-plugin remove --tools left $f"
done
assert_contains "claude mcp remove" "$(cat "$work/unclient.log")" "uninstall-tools says what register did besides"

# An install looks for no process (S7): one whose command line names the
# API's program, as the API's does, gets no signal: it notes a SIGTERM. It
# is this test's own child, stopped after with SIGKILL, which it cannot
# note, by the PID the shell gave it.
"${XYMONAPI_PYTHON:-python3}" -c 'import signal, sys, time
signal.signal(signal.SIGTERM, lambda *a: (open(sys.argv[1], "w").close(), sys.exit(0)))
time.sleep(300)' "$work/decoy.term" "$home/ext/xymonapi/app.py" &
decoy=$!
"$ROOT/xymon-plugin" install --server xymonapi XYMONHOME="$home" MANDIR="$work/man" >"$work/update2.log" 2>&1 \
	|| { kill -9 "$decoy"; fail "the install failed: $(tail -n 5 "$work/update2.log")"; }
sleep 1
kill -9 "$decoy" 2>/dev/null || :; wait "$decoy" 2>/dev/null || :
[ -e "$work/decoy.term" ] && fail "[S7] the install sent SIGTERM to a process that names the API's program"
assert_not_contains "signal to stop" "$(cat "$work/update2.log")" "[S7] and says it sent no signal"

pass "./xymon-plugin install --server puts the server plugins in ext/ with tasks off and its web server snippets, keeps what the admin edited, takes odd directory names, replaces each plugin's directory on update; install-tools lays out the client side; uninstall removes them, refusing one another needs"
