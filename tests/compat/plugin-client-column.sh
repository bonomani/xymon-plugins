#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-client-column.sh
#
# The plugins column of a standalone client (S33, S35): xymon-plugin's
# client part installs the reporter and its task, off; the task runs it
# with --client under xymonclient.cfg, outdated --client asked, the name
# xymonlaunch gives written in $XYMONTMP/xymon-plugin.host. enable
# --client xymon-plugin sends the column at once under xymoncmd, with the
# name that file holds, or before any run the one in runclient.sh's
# clientlaunch.NAME.pid; with neither, nothing is sent, said. With XYMSRV
# 0.0.0.0, the status goes to each server XYMSERVERS names, each read back:
# one that did not keep it ends the run with 1; one that refuses to show
# its board is said, and does not; none named, nothing is sent.
#
# Xymon and GitHub are never reached: xymoncmd, xymon, curl and sleep are
# stand-ins, as in tests/compat/plugin-column-refresh.sh.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
work=$(cd "$work" && pwd -P)
unset MAN SUDO_USER
export HOME="$work/home" XDG_CONFIG_HOME="$work/cfg" XYMON_PLUGINS_TREES_ONLY=1 XYMON_PLUGINS_TREES=
mkdir -p "$HOME" "$work/man"
want=$(sed -n 's/^version: *//p' "$ROOT/plugins/xymon-plugin/PLUGIN")

# A client's tree, sending to two servers.
c=$work/client bin=$work/bin
mkdir -p "$c/bin" "$c/etc" "$c/ext" "$c/logs" "$c/tmp" "$bin"
: > "$c/bin/xymonclient.sh"
printf 'XYMONHOME="%s"\nXYMON="%s"\nXYMSRV="0.0.0.0"\nXYMSERVERS="192.0.2.1 192.0.2.2"\n' "$c" "$bin/xymon" > "$c/etc/xymonclient.cfg"
printf 'optional directory %s/etc/clientlaunch.d\n' "$c" > "$c/etc/clientlaunch.cfg"

# The stand-ins: xymoncmd sets what the file it is given says, keeps how
# it was run, XYMONTMP by default under XYMONHOME as Xymon's own, and runs
# the command; xymon keeps each status sent with the
# server it went to, answers a read-back with its colour, nothing for a
# server in XYMONDROP, and nothing at all for one in XYMONREFUSE; curl
# prints the releases in $work/tags; sleep keeps a wait asked.
cat > "$c/bin/xymoncmd" <<'SH'
#!/bin/sh
case $1 in --env=*) f=${1#--env=}; shift ;; esac
set -a; eval "$(grep '^[A-Z_]*=' "$f")"; : "${XYMONTMP:=$XYMONHOME/tmp}"; set +a
echo "WAIT=${XYMON_PLUGINS_WAIT:-unset} MACHINEDOTS=${MACHINEDOTS:-} $*" >> "$WORK/xymoncmd"
exec "$@"
SH
cat > "$bin/xymon" <<'SH'
#!/bin/sh
case " ${XYMONREFUSE:-} " in *" $1 "*) case $2 in xymondboard*) exit 0 ;; esac ;; esac
case $2 in
xymondboard*test=plugins*)
	case " ${XYMONDROP:-} " in *" $1 "*) exit 0 ;; esac
	sed -n '1s/^status+[^ ]* [^ ]* \([a-z]*\) .*/\1/p' "$WORK/sent" ;;
xymondboard*) echo some.host ;;
*) printf '%s\n' "$2" > "$WORK/sent"; echo "$1 $(printf '%s' "$2" | sed -n '1s/^status+[^ ]* \([^ ]*\) .*/\1/p')" >> "$WORK/sends" ;;
esac
SH
cat > "$bin/curl" <<'SH'
#!/bin/sh
for a; do u=$a; done
case $u in *page=1) ;; *) echo '[]'; exit 0 ;; esac
printf '['; sep=; while read -r t; do printf '%s{"tag_name": "%s"}' "$sep" "$t"; sep=,; done < "$WORK/tags"; printf ']\n'
SH
# shellcheck disable=SC2016 # expanded by the stand-in
printf '#!/bin/sh\necho "$1" >> "$WORK/slept"\n' > "$bin/sleep"
chmod 755 "$c/bin/xymoncmd" "$bin/xymon" "$bin/curl" "$bin/sleep"
export WORK=$work PATH="$bin:$PATH"
printf 'xymon-plugin/v%s\n' "$want" > "$work/tags"

# x ARG... -- the checkout's installer on the client, off a terminal.
x() { rm -f "$work/sends" "$work/xymoncmd"; rc=0; out=$("$ROOT/xymon-plugin" "$@" XYMONHOME="$c" MANDIR="$work/man" </dev/null 2>&1) || rc=$?; }
ok() { [ "$rc" -eq 0 ] || fail "$1 failed ($rc): $out"; }
sends() { cat "$work/sends" 2>/dev/null || :; }
# task [VAR=VALUE...] -- the reporter as the task runs it, under the
# client's environment and the name runclient.sh gives.
task() {
	rm -f "$work/sends"; rc=0
	# shellcheck disable=SC2016 # expanded by the inner shell
	out=$(env MACHINEDOTS=task.example.com XYMONTMP="$c/tmp" "$@" sh -c '
		set -a; eval "$(grep "^[A-Z_]*=" "$0")"; set +a
		XYMON_PLUGINS_WAIT=0 exec "$1" --client' "$c/etc/xymonclient.cfg" "$c/ext/xymon-plugin/xymon-plugin-report.sh" 2>&1) || rc=$?
}

# Installed off: the reporter and the task, under xymonclient.cfg.
x install --client xymon-plugin; ok "install --client xymon-plugin"
tf=$c/ext/xymon-plugin/tasks.cfg
[ -x "$c/ext/xymon-plugin/xymon-plugin-report.sh" ] || fail "[S33] the client part has no reporter"
assert_contains "ENVFILE $c/etc/xymonclient.cfg" "$(cat "$tf")" "[S33] the task under the client's environment"
assert_contains "CMD $c/ext/xymon-plugin/xymon-plugin-report.sh --client" "$(cat "$tf")" "[S33] the reporter with --client"
assert_not_contains "NEEDS" "$(cat "$tf")" "[S33] no xymond to wait for on a client"
assert_contains "LOGFILE \$XYMONCLIENTLOGS/xymon-plugin.log" "$(cat "$tf")" "[S33] its log among the client's"
[ -z "$(sends)" ] || fail "[S33] the install of a task off sent: $(sends)"

# enable, the task never run, no pid file: nothing sent, said.
x enable --client xymon-plugin; ok "enable --client xymon-plugin"
[ -z "$(sends)" ] || fail "[S33] sent with no name to send under: $(sends)"
assert_contains "The plugins column is not sent: its task has not run yet" "$out" "[S33] and says why"

# runclient.sh's pid file names the host: enable, on already, sends at once
# to each server, under xymoncmd, with no wait.
: > "$c/logs/clientlaunch.pid.example.com.pid"
x enable --client xymon-plugin; ok "enable --client xymon-plugin, on already"
assert_contains "The plugins column, sent now for pid.example.com:" "$out" "[S33] sent under the pid file's name"
assert_equal "192.0.2.1 pid,example,com.plugins
192.0.2.2 pid,example,com.plugins" "$(sends)" "[S33] once to each server XYMSERVERS names"
assert_contains "WAIT=0 MACHINEDOTS=pid.example.com /bin/sh $c/ext/xymon-plugin/xymon-plugin-report.sh --client" "$(cat "$work/xymoncmd")" "[S33] the installed reporter, --client, under xymoncmd, no wait"
assert_contains "sent green to 192.0.2.1; sent green to 192.0.2.2" "$out" "[S33] and says what it sent, each server"
[ ! -e "$work/slept" ] || fail "[S33] the column sent at once waited"

# The task: outdated --client, the name it was given written for the
# installer, which sends under it from then on.
task; [ "$rc" -eq 0 ] || fail "[S33] the task failed ($rc): $out"
assert_equal "task.example.com" "$(cat "$c/tmp/xymon-plugin.host")" "[S33] the task writes the name it sent under"
assert_contains "192.0.2.1 task,example,com.plugins" "$(sends)" "[S33] the task sends for its host"
assert_contains "xymon-plugin: $want installed; up to date" "$(cat "$work/sent")" "[S33] outdated --client's lines"
x enable --client xymon-plugin; ok "enable --client xymon-plugin, after a run"
assert_contains "The plugins column, sent now for task.example.com:" "$out" "[S33] the name the task wrote, before the pid file's"
x update --client xymon-plugin; ok "update --client xymon-plugin"
assert_equal "192.0.2.1 task,example,com.plugins
192.0.2.2 task,example,com.plugins" "$(sends)" "[S33] an update --client that changed the tree sends the column at once"
x disable --client xymon-plugin; ok "disable --client xymon-plugin"
[ -z "$(sends)" ] || fail "[S33] disable sent: $(sends)"
x update --client xymon-plugin; ok "update --client xymon-plugin, the task off"
[ -z "$(sends)" ] || fail "[S33] an update with the task off sent: $(sends)"
x enable --client xymon-plugin; ok "enable --client xymon-plugin, again"

# A server that did not keep it: said, ends the run with 1; one that
# refuses to show its board: said, not a failure; no server named.
task XYMONDROP=192.0.2.2
assert_equal 1 "$rc" "[S33] a server that did not keep the status ends the task with 1: $out"
assert_contains "sent green to 192.0.2.1; sent green for task.example.com to 192.0.2.2, which xymond did not keep: is task.example.com in hosts.cfg?" "$out" "[S33] and says which"
task XYMONREFUSE=192.0.2.2
assert_equal 0 "$rc" "[S33] a server that refuses to show its board does not fail the task: $out"
assert_contains "sent green to 192.0.2.2, which xymond refuses to show to this host: not read back" "$out" "[S33] and says so"
printf 'XYMSERVERS=""\n' >> "$c/etc/xymonclient.cfg"
task
assert_equal 1 "$rc" "[S33] XYMSRV 0.0.0.0 with no XYMSERVERS ends the task with 1: $out"
assert_contains "XYMSRV is 0.0.0.0 and XYMSERVERS names no server: nothing sent" "$out" "[S33] and says so"
[ -z "$(sends)" ] || fail "[S33] sent with no server named: $(sends)"

pass "a client's plugins column: the reporter and its task installed off under xymonclient.cfg with --client; sent at once by enable under the name the task wrote, or runclient.sh's pid file, or not, said; the task writing its name; each server of XYMSERVERS sent to and read back, one not keeping it a failure, one refusing to show its board said"
