#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-own-client.sh
#
# A client part goes into a server's own client tree too (S36): named by
# its server, XYMONHOME=<server> --client, the tree its xymonserver.cfg
# names as XYMONCLIENTHOME, a variable in it read through the server's
# xymoncmd. The part's files go in that tree's ext/, @XYMONHOME@ that
# tree; its task, installed off, is linked from the server's tasks.d/ as
# NAME-client.cfg, beside a server part's NAME-server.cfg, its log in the
# server's logs; the server's tasks.cfg, not the client's
# clientlaunch.cfg, is the one read and touched. status and verify read
# the tree. Refused, nothing changed: the client tree named directly
# (giving the server's form), an XYMONCLIENTHOME naming nothing, a missing
# directory, one without a client's marks, or the server's own tree; a
# tree with no ext/ (giving the commands), whose read verbs find it empty;
# an ext/ owned by neither the server's ext/ owner nor root; and
# xymon-plugin, whose server copy manages that tree.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
work=$(cd "$work" && pwd -P)
unset MAN SUDO_USER
export HOME="$work/home" XDG_CONFIG_HOME="$work/cfg" XYMON_PLUGINS_TREES_ONLY=1 XYMON_PLUGINS_TREES=
mkdir -p "$HOME" "$work/man"

# A server and its own client tree, as Xymon's install lays them out.
s=$work/xymon/server c=$work/xymon/client
server_tree "$s"
mkdir -p "$s/ext" "$s/etc/tasks.d" "$c/bin" "$c/etc" "$c/ext"
printf 'XYMONCLIENTHOME="%s"\n' "$c" >> "$s/etc/xymonserver.cfg"
printf 'directory %s/etc/tasks.d\n' "$s" > "$s/etc/tasks.cfg"
: > "$c/bin/xymonclient.sh"; : > "$c/etc/xymonclient.cfg"
printf 'optional directory %s/etc/clientlaunch.d\n' "$c" > "$c/etc/clientlaunch.cfg"
cp "$s/etc/xymonserver.cfg" "$work/xymonserver.cfg"

# A checkout with two plugins of the test's own: oc, a client part with
# its task; both, a server part and a client part, each with its task.
r=$work/repo
mkdir -p "$r"
cp -R "$ROOT/xymon-plugin" "$ROOT/LICENSE" "$ROOT/plugins" "$r/"
mkdir -p "$r/plugins/oc" "$r/plugins/both"
printf 'name: oc\nversion: 1.0.0\nsummary: a test\nclient-files: check.sh\nclient-task: oc.tasks\n' > "$r/plugins/oc/PLUGIN"
printf '#!/bin/sh\nexit 0\n' > "$r/plugins/oc/check.sh"
printf '[oc-client]\n\tENVFILE @XYMONHOME@/etc/xymonclient.cfg\n\tCMD @XYMONHOME@/ext/oc/check.sh\n\tLOGFILE @LOGDIR@/oc-client.log\n\tINTERVAL 5m\n' > "$r/plugins/oc/oc.tasks"
printf 'name: both\nversion: 1.0.0\nsummary: a test\nserver-files: s.sh\nserver-task: s.tasks\nclient-files: c.sh\nclient-task: c.tasks\n' > "$r/plugins/both/PLUGIN"
printf '#!/bin/sh\nexit 0\n' > "$r/plugins/both/s.sh"; cp "$r/plugins/both/s.sh" "$r/plugins/both/c.sh"
mkdir -p "$r/plugins/dep"
printf 'name: dep\nversion: 1.0.0\nsummary: a test\nclient-files: d.sh\nclient-needs: xymon-plugin\n' > "$r/plugins/dep/PLUGIN"
printf '#!/bin/sh\nexit 0\n' > "$r/plugins/dep/d.sh"
printf '[both-server]\n\tCMD @XYMONHOME@/ext/both/s.sh\n\tINTERVAL 5m\n' > "$r/plugins/both/s.tasks"
printf '[both-client]\n\tENVFILE @XYMONHOME@/etc/xymonclient.cfg\n\tCMD @XYMONHOME@/ext/both/c.sh\n\tLOGFILE @LOGDIR@/both-client.log\n\tINTERVAL 5m\n' > "$r/plugins/both/c.tasks"

# x ARG... -- the checkout's installer, off a terminal.
x() { rc=0; out=$("$r/xymon-plugin" "$@" MANDIR="$work/man" </dev/null 2>&1) || rc=$?; }
ok() { [ "$rc" -eq 0 ] || fail "$1 failed ($rc): $out"; }
refused() { [ "$rc" -ne 0 ] || fail "$1 was taken: $out"; }
dump() { "$XYMON_SRC/common/xymonlaunch" --config="$s/etc/tasks.cfg" --dump 2>/dev/null | grep '^\[' || true; }
link=$s/etc/tasks.d/oc-client.cfg

# Installed off, in the client tree, named by its server.
x install --client oc XYMONHOME="$s"; ok "install --client named by the server"
assert_contains "Target: $c (named by XYMONHOME, the client tree of the Xymon server $s), part: client" "$out" "[S36] the target is the server's client tree, said"
assert_file_exists "$c/ext/oc/tasks.cfg"
assert_contains "CMD $c/ext/oc/check.sh" "$(cat "$c/ext/oc/tasks.cfg")" "[S36] @XYMONHOME@ is the client tree"
assert_contains "LOGFILE \$XYMONSERVERLOGS/oc-client.log" "$(cat "$c/ext/oc/tasks.cfg")" "[S36] the log goes to the server's logs"
{ [ -e "$link" ] || [ -L "$link" ]; } && fail "[S36] the install made a link"
assert_contains "enable --client --xymon-home $s oc turns it on" "$out" "[S36] and gives the command, with the server"

# enable: the link from the server's tasks.d/, the server's tasks.cfg read
# and touched, the client's clientlaunch.d/ untouched.
touch -t 200001010000 "$s/etc/tasks.cfg"; : > "$work/ref"; touch -t 200101010000 "$work/ref"
x enable --client oc XYMONHOME="$s"; ok "enable --client"
assert_equal "$c/ext/oc/tasks.cfg" "$(readlink "$link")" "[S36] the link in the server's tasks.d/ names the task file in the client tree"
[ -n "$(find "$s/etc/tasks.cfg" -newer "$work/ref")" ] || fail "[S36] enable did not touch the server's tasks.cfg"
[ ! -e "$c/etc/clientlaunch.d" ] || fail "[S36] enable made the client's clientlaunch.d/"
assert_contains "[oc-client]" "$(dump)" "[S36] the server's xymonlaunch has the task"
x status --client XYMONHOME="$s"; ok "status --client"
assert_contains "oc: 1.0.0 installed, on" "$out" "[S36] status reads the tree"
x verify --client XYMONHOME="$s"; ok "verify --client"
assert_contains "ok: oc" "$out" "[S36] verify reads the tree"

# Both parts of one plugin: each its tree, each its task, side by side.
x install --server both XYMONHOME="$s"; ok "install --server both"
x install --client both XYMONHOME="$s"; ok "install --client both"
x enable --server both XYMONHOME="$s"; ok "enable --server both"
x enable --client both XYMONHOME="$s"; ok "enable --client both"
assert_equal "$s/ext/both/tasks.cfg" "$(readlink "$s/etc/tasks.d/both-server.cfg")" "[S36] the server part's link"
assert_equal "$c/ext/both/tasks.cfg" "$(readlink "$s/etc/tasks.d/both-client.cfg")" "[S36] the client part's link beside it"
d=$(dump)
assert_contains "[both-server]" "$d" "[S36] xymonlaunch has the server part's task"
assert_contains "[both-client]" "$d" "[S36] and the client part's, apart"
x remove --client both XYMONHOME="$s"; ok "remove --client both"
[ -L "$s/etc/tasks.d/both-server.cfg" ] || fail "[S36] remove --client took the server part's link"
{ [ -e "$s/etc/tasks.d/both-client.cfg" ] || [ -L "$s/etc/tasks.d/both-client.cfg" ]; } && fail "[S36] remove --client left the client part's link"
[ -d "$s/ext/both" ] || fail "[S36] remove --client took the server part"

# disable and remove of oc.
x disable --client oc XYMONHOME="$s"; ok "disable --client"
{ [ -e "$link" ] || [ -L "$link" ]; } && fail "[S36] disable left the link"
x remove --client oc XYMONHOME="$s"; ok "remove --client"
[ ! -e "$c/ext/oc" ] || fail "[S36] remove left the directory"

# The client tree named directly: refused, the server's form given.
x install --client oc XYMONHOME="$c"; refused "install --client named by the client tree"
assert_contains "is the client tree of the Xymon server $s: name the server, ./xymon-plugin install --client --xymon-home $s" "$out" "[S36] and gives the server's form"

# xymon-plugin: its client part does not go there. Named, refused before
# anything changes, another plugin named with it untouched; a copy left
# is said with the commands that remove it, which do; not named, passed
# over, said once.
for v in install update remove enable disable; do
	x $v --client xymon-plugin XYMONHOME="$s"; refused "$v --client xymon-plugin on a server"
	assert_contains "xymon-plugin's client part does not go in the client tree of the Xymon server $s" "$out" "[S36] $v of xymon-plugin: refused, saying why"
	assert_not_contains "./xymon-plugin install --client" "$out" "[S36] $v of xymon-plugin: no command given that is refused too"
done
x install --client oc xymon-plugin XYMONHOME="$s"; refused "install --client oc xymon-plugin on a server"
[ ! -e "$c/ext/oc" ] || fail "[S36] oc named with xymon-plugin was installed before the refusal"
mkdir -p "$c/ext/xymon-plugin" "$c/etc/clientlaunch.d" "$work/man/man8"
cp "$ROOT/plugins/xymon-plugin/PLUGIN" "$c/ext/xymon-plugin/PLUGIN"; echo xymon-plugin/v0.0.1 > "$c/ext/xymon-plugin/VERSION"
: > "$c/ext/xymon-plugin/tasks.cfg"; : > "$c/ext/xymon-plugin/xymon-plugin.8"
ln -s "$c/ext/xymon-plugin/tasks.cfg" "$c/etc/clientlaunch.d/xymon-plugin-client.cfg"
ln -s "$c/ext/xymon-plugin/xymon-plugin.8" "$work/man/man8/xymon-plugin.8"
x remove --client xymon-plugin XYMONHOME="$s"; refused "remove --client xymon-plugin on a server"
assert_contains "rm -rf $c/ext/xymon-plugin $c/etc/clientlaunch.d/xymon-plugin-client.cfg" "$out" "[S36] a copy left: the directory's removal given, and its link in clientlaunch.d/"
assert_contains "./xymon-plugin clean --client --xymon-home $s xymon-plugin" "$out" "[S36] and clean for what it left elsewhere"
rm -rf "$c/ext/xymon-plugin" "$c/etc/clientlaunch.d/xymon-plugin-client.cfg"
x clean --client xymon-plugin XYMONHOME="$s" --yes; ok "clean --client xymon-plugin, the copy removed"
[ ! -L "$work/man/man8/xymon-plugin.8" ] || fail "[S36] clean left the copy's manual page link"
x install --client dep XYMONHOME="$s"; ok "install --client of a plugin needing xymon-plugin, on a server"
assert_contains "xymon-plugin is passed over: the server's copy stands for its client part" "$out" "[S36] a need on xymon-plugin met by the server's copy, said"
assert_file_exists "$c/ext/dep/VERSION"
[ ! -e "$c/ext/xymon-plugin" ] || fail "[S36] the need installed xymon-plugin's client part in the server's client tree"
x remove --client dep XYMONHOME="$s"; ok "remove --client dep"
x install --client --all XYMONHOME="$s"; ok "install --client --all on a server"
assert_equal 1 "$(printf '%s\n' "$out" | grep -c 'xymon-plugin is passed over')" "[S36] --all: xymon-plugin passed over, said once"
x remove --client --all XYMONHOME="$s"; ok "remove --client --all on a server"
rmdir "$c/etc/clientlaunch.d"

# XYMONCLIENTHOME: a variable, read through the server's xymoncmd; naming
# nothing, a missing directory, no client's marks, the server's own tree.
cat > "$s/bin/xymoncmd" <<'SH'
#!/bin/sh
case $1 in --env=*) f=${1#--env=}; shift ;; esac
set -a; XYMONTOPDIR=${f%/server/etc/xymonserver.cfg}; eval "$(grep '^[A-Z_]*=' "$f")"; set +a
exec "$@"
SH
chmod 755 "$s/bin/xymoncmd"
sed "s|^XYMONCLIENTHOME=.*|XYMONCLIENTHOME=\"\$XYMONTOPDIR/client\"|" "$work/xymonserver.cfg" > "$s/etc/xymonserver.cfg"
x install --client oc XYMONHOME="$s"; ok "install --client, XYMONCLIENTHOME a variable"
assert_file_exists "$c/ext/oc/tasks.cfg"
x remove --client oc XYMONHOME="$s"; ok "remove --client, XYMONCLIENTHOME a variable"
case_refused() {   # case_refused LINE WHY EXPECTED
	{ grep -v '^XYMONCLIENTHOME=' "$work/xymonserver.cfg"; [ -z "$1" ] || printf '%s\n' "$1"; } > "$s/etc/xymonserver.cfg"
	x install --client oc XYMONHOME="$s"; refused "install --client, $2"
	assert_contains "$3" "$out" "[S36] $2: refused, saying what was read"
	[ ! -e "$c/ext/oc" ] || fail "[S36] $2: installed all the same"
}
case_refused "" "no XYMONCLIENTHOME" "names no XYMONCLIENTHOME it can read"
case_refused "XYMONCLIENTHOME=\"client\"" "a relative path" "XYMONCLIENTHOME, client, is not an absolute path"
case_refused "XYMONCLIENTHOME=\"$work/none\"" "a missing directory" "$work/none, is not there"
mkdir -p "$work/plain"
case_refused "XYMONCLIENTHOME=\"$work/plain\"" "no client's marks" "is no Xymon client's tree"
case_refused "XYMONCLIENTHOME=\"$s\"" "the server's own tree" "is the server's own tree"
cp "$work/xymonserver.cfg" "$s/etc/xymonserver.cfg"

# A trailing / and a link: the tree taken resolved, as nothing written
# names it otherwise.
ln -s "$c" "$work/clientlink"
for v in "$c/" "$work/clientlink"; do
	{ grep -v '^XYMONCLIENTHOME=' "$work/xymonserver.cfg"; printf 'XYMONCLIENTHOME="%s"\n' "$v"; } > "$s/etc/xymonserver.cfg"
	x install --client oc XYMONHOME="$s"; ok "install --client, XYMONCLIENTHOME $v"
	assert_contains "CMD $c/ext/oc/check.sh" "$(cat "$c/ext/oc/tasks.cfg")" "[S36] XYMONCLIENTHOME $v: the tree as resolved in the task file"
	x enable --client oc XYMONHOME="$s"; ok "enable --client, XYMONCLIENTHOME $v"
	assert_equal "$c/ext/oc/tasks.cfg" "$(readlink "$link")" "[S36] XYMONCLIENTHOME $v: the link names the tree as resolved"
	cp "$work/xymonserver.cfg" "$s/etc/xymonserver.cfg"
	x remove --client oc XYMONHOME="$s"; ok "remove --client, XYMONCLIENTHOME respelt"
	{ [ -e "$link" ] || [ -L "$link" ]; } && fail "[S36] XYMONCLIENTHOME $v, respelt: remove left the link"
done

# No ext/: refused, the commands given; the read verbs find it empty.
mv "$c/ext" "$work/ext.away"
x install --client oc XYMONHOME="$s"; refused "install --client, no ext/"
assert_contains "$c has no directory ext/" "$out" "[S36] no ext/: refused, saying so"
assert_contains "mkdir $c/ext && chown" "$out" "[S36] and gives the commands"
x status --client XYMONHOME="$s"; ok "status --client, no ext/"
x verify --client XYMONHOME="$s"; ok "verify --client, no ext/"
mv "$work/ext.away" "$c/ext"

# An ext/ owned by another: refused, the chown given. The owner is read
# through ls, here a stand-in, as a test is not root.
mkdir -p "$work/bin"
cat > "$work/bin/ls" <<SH
#!/bin/sh
for a; do last=\$a; done
if [ "\$last" = "$c/ext" ]; then $(command -v ls) "\$@" | awk '{ \$3 = "4242"; print }'; else exec $(command -v ls) "\$@"; fi
SH
chmod 755 "$work/bin/ls"
op=$PATH; PATH=$work/bin:$PATH
x install --client oc XYMONHOME="$s"
PATH=$op
refused "install --client, ext/ another's"
assert_contains "neither the server's ext/ owner" "$out" "[S36] an ext/ owned by another: refused, saying why"
assert_contains "chown" "$out" "[S36] and gives the chown"
[ ! -e "$c/ext/oc" ] || fail "[S36] ext/ another's: installed all the same"

pass "a client part in a server's own client tree, named by its server: files in that tree, its task linked from the server's tasks.d/ as NAME-client.cfg beside NAME-server.cfg, the server's tasks.cfg read and touched, its log in the server's; status and verify read it; refused, saying what was read: the client tree named directly, XYMONCLIENTHOME naming nothing, a missing or unmarked tree or the server's own, no ext/ (read verbs finding it empty), an ext/ another's, xymon-plugin"
