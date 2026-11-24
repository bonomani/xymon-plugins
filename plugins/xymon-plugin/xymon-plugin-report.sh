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
#
# --client: the task of a standalone client's tree, xymonclient.cfg its
# environment and MACHINEDOTS the name runclient.sh gives; outdated
# --client, and the name written in $XYMONTMP/xymon-plugin.host, for the
# installer to send under at once -- not when the installer runs it so,
# XYMON_PLUGINS_AT_ONCE set. The status goes to XYMSRV, or, where that is
# 0.0.0.0, to each server XYMSERVERS names, each read back.

here=$(cd "$(dirname "$0")" && pwd)
part=server; [ "${1:-}" != --client ] || part=client
log() { printf '%s xymon-plugin-report: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

for v in XYMON XYMSRV XYMONHOME MACHINEDOTS; do
	eval "val=\${$v:-}"
	if [ -z "$val" ]; then log "$v is not set: run as the task, with ENVFILE xymon$part.cfg"; exit 1; fi
done
# The server's name as xymonserver.cfg gives it, MACHINEDOTS -- the one
# hosts.cfg knows it by, and its own columns go under -- not MACHINE,
# which may be the system's name instead (Homebrew's Xymon: localhost
# against bcs-Mac-mini,local), under which xymond would keep nothing.
host=$(printf '%s' "$MACHINEDOTS" | tr . ,)
if [ "$part" = client ] && [ -z "${XYMON_PLUGINS_AT_ONCE:-}" ]; then
	ht=${XYMONTMP:-$XYMONHOME/tmp}/xymon-plugin.host
	{ printf '%s\n' "$MACHINEDOTS" > "$ht"; } 2>/dev/null || log "could not write $ht: the installer cannot send the column at once"
fi

# The wait: 0 to max seconds, from /dev/urandom where it is, else from the
# host, the PID and the time.
# Once waited, this script runs again from its file -- see below -- told
# how long it waited: it does not wait again.
max=${XYMON_PLUGINS_WAIT:-21600}
case $max in ''|*[!0-9]*) max=21600 ;; esac
r=$(od -An -N2 -tu2 /dev/urandom 2>/dev/null | tr -d ' ')
case $r in ''|*[!0-9]*) r=$(printf '%s %s %s' "$MACHINEDOTS" "$$" "$(date)" | cksum | cut -d' ' -f1) ;; esac
wait_s=$((r % (max + 1)))
waited=
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
	if [ -f "$0" ]; then XYMON_PLUGINS_WAITED=$wait_s exec /bin/sh "$0" "$@"; fi
fi

# Not gh, which no time bounds: MAXTIME stops this script, not what it
# started, and a gh that hangs would stay. curl, bounded, sends GH_TOKEN
# when it is set.
out=$(XYMON_PLUGINS_NO_GH=1 "$here/xymon-plugin" outdated --$part 2>&1)
rc=$?
# Each plugin's line, "  NAME: ...", gets the colour it gives, which the
# status page shows as an icon: green up to date, newer than its latest
# release, or with none published; yellow with a newer one released, or
# with a VERSION that cannot be compared. The summary counts them.
marked=$(printf '%s\n' "$out" | awk '
	/^  cannot read / { print "  &yellow " substr($0, 3); next }
	/^  [^ ]+: / {
		c = "yellow"
		if ($0 ~ /; up to date$/ || $0 ~ /; newer than its latest release, / || $0 ~ /; no release of it is published$/) c = "green"
		print "  &" c " " substr($0, 3); next
	}
	{ print }')
# names RE -- the yellow lines' plugins whose text after "NAME:" matches RE,
# one per line.
names() { printf '%s\n' "$marked" | sed -n "s/^  &yellow \([^ :]*\):$1.*/\1/p"; }
# joined LINES -- them on one line, separated by ", ".
joined() { printf '%s\n' "$1" | awk 'NF { printf "%s%s", (n++ ? ", " : ""), $0 }'; }
n=$(printf '%s\n' "$marked" | grep -c '^  &') || :
newer=$(names '.* released: '); k=$(printf '%s' "$newer" | grep -c .) || :; newer=$(joined "$newer")
bad=$(names ' [^0-9]'); m=$(printf '%s' "$bad" | grep -c .) || :; bad=$(joined "$bad")
# A directory outdated cannot read -- ext/ itself, say -- hides the plugins
# in it: said first, as it is, and then what could be read.
closed=$(joined "$(printf '%s\n' "$out" | sed -n 's/^  \(cannot read .*\)/\1/p')")
if [ "$n" = 1 ]; then of="1 plugin"; else of="$n plugins"; fi
case $rc in
	0) color=green summary="$of: no newer release is published" ;;
	6) color=yellow summary="$k of $of with a newer release published: $newer" ;;
	7) color=yellow
		if [ "$m" -gt 0 ]; then summary="$m of $of whose VERSION cannot be compared: $bad"; else summary=$closed; fi
		[ -z "$closed" ] || [ "$m" = 0 ] || summary="$closed; $summary"
		summary="$summary${newer:+; $k with a newer release published: $newer}" ;;
	1)
		log "waited ${wait_s}s; outdated ended with 1, nothing sent: $(printf '%s' "$out" | tr '\n' ' ')"
		exit 0 ;;
	*) color=yellow summary="outdated ended with $rc" ;;
esac
# Each server, read back: xymon ends with 0 even where xymond keeps
# nothing -- a host hosts.cfg does not name. xymond reads host= and test=
# as regular expressions: anchored, the dots escaped, so that web1 is not
# web10. A column read back blue is kept, disabled. A board read back empty
# for every host is one xymond refuses to show this host (--www-senders):
# said, not a failure -- nor can it be told then whether xymond kept it.
re=$(printf '%s' "$MACHINEDOTS" | sed 's/[].[^$*+?(){}|\\]/\\&/g')
servers=$XYMSRV
[ "$XYMSRV" != 0.0.0.0 ] || servers=${XYMSERVERS:-}
if [ -z "$(printf '%s' "$servers" | tr -d ' ')" ]; then
	log "waited ${wait_s}s; outdated ended with $rc; XYMSRV is 0.0.0.0 and XYMSERVERS names no server: nothing sent"
	exit 1
fi
end=0 said=
set -f
for srv in $servers; do
	to=; [ "$srv" = "$XYMSRV" ] || to=" to $srv"
	if ! "$XYMON" "$srv" "status+31h $host.plugins $color $(date) $summary

$marked"; then
		said="$said; could not send $color to $srv"; end=1; continue
	fi
	if ! kept=$("$XYMON" "$srv" "xymondboard host=^$re\$ test=^plugins\$ fields=color" 2>&1); then
		said="$said; sent $color$to, which could not be read back: $kept"; continue
	fi
	if [ -z "$kept" ]; then
		if ! b=$("$XYMON" "$srv" "xymondboard fields=hostname" 2>&1); then
			said="$said; sent $color$to, which could not be read back: $b"; continue
		fi
		if [ -z "$b" ]; then
			said="$said; sent $color$to, which xymond refuses to show to this host: not read back"; continue
		fi
	fi
	case $kept in
		"$color") said="$said; sent $color$to" ;;
		blue) said="$said; sent $color$to, kept, the column disabled" ;;
		*) said="$said; sent $color for $MACHINEDOTS$to, which xymond did not keep: is $MACHINEDOTS in hosts.cfg?"; end=1 ;;
	esac
done
set +f
log "waited ${wait_s}s; outdated ended with $rc$said"
exit $end
