#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# xymon-plugin-report.sh -- the plugins column, xymon-plugin(8): run once a
# day by xymonlaunch, as the task ext/xymon-plugin/tasks.cfg (off once
# installed: ./xymon-plugin enable --server xymon-plugin), it waits a time
# drawn at random, up to 6 hours -- so that the servers that run it do not
# all ask GitHub at once -- then runs the installer beside it, outdated
# --server, and sends this host's status "plugins", valid 31 hours:
#
#   0  green: no newer release of a plugin installed is published
#   6  yellow: a newer release is published
#   7  yellow: a plugin's VERSION cannot be compared
#   1  nothing sent: GitHub not reached, or the installer could not run;
#      the status already there stays, and goes purple once 31 hours have
#      passed since it was sent
#   any other: yellow, saying so
#
# outdated's lines follow the first line of the status, which is for
# MACHINEDOTS, the server's name in xymonserver.cfg; read back, a status
# xymond did not keep is said. It needs the Xymon server's environment
# xymonlaunch gives (ENVFILE xymonserver.cfg): XYMON, XYMSRV, XYMONHOME,
# MACHINEDOTS. What it does goes to its log, one line a
# run. XYMON_PLUGINS_WAIT, the longest wait in seconds, for the tests.

here=$(cd "$(dirname "$0")" && pwd)
log() { printf '%s xymon-plugin-report: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

for v in XYMON XYMSRV XYMONHOME MACHINEDOTS; do
	eval "val=\${$v:-}"
	if [ -z "$val" ]; then log "$v is not set: run as the task, with ENVFILE xymonserver.cfg"; exit 1; fi
done
# The server's name as xymonserver.cfg gives it, MACHINEDOTS -- the one
# hosts.cfg knows it by, and its own columns go under -- not MACHINE,
# which may be the system's name instead (Homebrew's Xymon: localhost
# against bcs-Mac-mini,local), under which xymond would keep nothing.
host=$(printf '%s' "$MACHINEDOTS" | tr . ,)

# The wait: 0 to max seconds, from /dev/urandom where it is, else from the
# host, the PID and the time.
# Once waited, this script runs again from its file -- see below -- told
# how long it waited: it does not wait again.
max=${XYMON_PLUGINS_WAIT:-21600}
case $max in ''|*[!0-9]*) max=21600 ;; esac
r=$(od -An -N2 -tu2 /dev/urandom 2>/dev/null | tr -d ' ')
case $r in ''|*[!0-9]*) r=$(printf '%s %s %s' "$MACHINEDOTS" "$$" "$(date)" | cksum | cut -d' ' -f1) ;; esac
wait_s=$((r % (max + 1)))
case ${XYMON_PLUGINS_WAITED:-} in ''|*[!0-9]*) ;; *) wait_s=$XYMON_PLUGINS_WAITED waited=1 ;; esac
# Stopped while waiting -- xymonlaunch's MAXTIME, a reload, disable --
# its own sleep goes with it, not left running: the PID $! gave, of a
# child not reaped yet, so it cannot be another process's.
if [ "$wait_s" -gt 0 ] && [ -z "${waited:-}" ]; then
	sleep "$wait_s" &
	s_pid=$!
	trap 'kill "$s_pid" 2>/dev/null; exit 143' TERM INT
	wait "$s_pid"
	trap - TERM INT
	# An update during the wait, hours long, replaced this file: the code
	# that sends is the one installed now, run in this process's place,
	# its PID kept for xymonlaunch, no signal sent (S33). Gone, the plugin
	# removed, this one goes on.
	if [ -f "$0" ]; then XYMON_PLUGINS_WAITED=$wait_s exec /bin/sh "$0"; fi
fi

# Not gh, which no time bounds: MAXTIME stops this script, not what it
# started, and a gh that hangs would stay. curl, bounded, sends GH_TOKEN
# when it is set.
out=$(XYMON_PLUGINS_NO_GH=1 "$here/xymon-plugin" outdated --server 2>&1)
rc=$?
case $rc in
	0) color=green summary="no newer release is published" ;;
	6) color=yellow summary="a newer release is published" ;;
	7) color=yellow summary="a plugin's VERSION cannot be compared" ;;
	1)
		log "waited ${wait_s}s; outdated ended with 1, nothing sent: $(printf '%s' "$out" | tr '\n' ' ')"
		exit 0 ;;
	*) color=yellow summary="outdated ended with $rc" ;;
esac
if ! "$XYMON" "$XYMSRV" "status+31h $host.plugins $color $(date) $summary

$out"; then
	log "waited ${wait_s}s; outdated ended with $rc; could not send $color to $XYMSRV"
	exit 1
fi
# xymon ends with 0 even where xymond keeps nothing -- a host hosts.cfg
# does not name: read it back.
if ! kept=$("$XYMON" "$XYMSRV" "xymondboard host=$MACHINEDOTS test=plugins fields=color" 2>&1); then
	log "waited ${wait_s}s; outdated ended with $rc; sent $color, which could not be read back: $kept"
	exit 0
fi
if [ "$kept" != "$color" ]; then
	log "waited ${wait_s}s; outdated ended with $rc; sent $color for $MACHINEDOTS, which xymond did not keep: is $MACHINEDOTS in hosts.cfg?"
	exit 1
fi
log "waited ${wait_s}s; outdated ended with $rc; sent $color"
exit 0
