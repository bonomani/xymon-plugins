#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# plugins/xymonapi/tests/xymonapi-board.sh
#
# The API reports the board a running xymond holds: a status sent to xymond
# comes back from /alarms with the severity it measured and its state --
# a red one firing, a green one inactive -- with its flags, its fields, its
# labels, and an inode one for each file system in alarm; an alarm says
# when it is acknowledged, /alarms/{id} gives its text, and /health names
# the xymond it asked. An operation the API
# does not implement answers 404 rather than sample data.
#
# Skips where the API cannot run (tests/lib/xymonapi.sh). Needs a built Xymon
# server tree in XYMON_SRC, and curl.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../../../tests/lib/xymonapi.sh"

ROOT=$(find_root)

require_bin XYMOND "$XYMON_SRC/xymond/xymond"
require_bin XYMONCLIENT "$XYMON_SRC/common/xymon"
command -v curl >/dev/null 2>&1 || skip "curl is not installed"

work=$(mktempdir)

# shellcheck disable=SC2034 # read by xymond-daemon.sh and the cleanup
XYMOND_PID=""
register_cleanup 'stop_process "$API_PID" "$XYMOND_PID"'

# A DOWNTIME window from five minutes ago to thirty from now, in local
# time as xymond reads it: its end is told, the minute after.
py=${XYMONAPI_PYTHON:-python3}
# shellcheck disable=SC2046 # three words, split on purpose
set -- $("$py" -c '
import time
now = int(time.time()) // 60 * 60
end = now + 1800
hhmm = lambda t: time.strftime("%H%M", time.localtime(t))
print(hhmm(now - 300), hhmm(end), time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(end + 60)))')
dtw_window="conn:*:$1:$2:Window" dtw_until=$3
printf 'page test Test\n127.0.0.1 red.example.com # conn\n127.0.0.1 green.example.com # conn\n127.0.0.1 disk.example.com # disk\n127.0.0.1 dis.example.com # conn\n127.0.0.1 wdis.example.com # conn\n127.0.0.1 dtw.example.com # conn DOWNTIME='"$dtw_window"'\n127.0.0.1 wack.example.com # conn\n127.0.0.1 pend.example.com # conn delayred=conn:30 delayyellow=conn:30\n127.0.0.1 mod.example.com # conn\n127.0.0.1 disk2.example.com # disk\n127.0.0.1 enc.example.com # conn\n127.0.0.1 lt.example.com # conn\n127.0.0.1 enc2.example.com # procs\n127.0.0.1 crit.example.com # conn\n127.0.0.1 critold.example.com # conn\n127.0.0.1 critcolon.example.com # conn\n127.0.0.1 clr.example.com # conn\n127.0.0.1 dt.example.com # conn DOWNTIME=*:*:0000:2359:Maint\n127.0.0.1 pipe.example.com # conn\n127.0.0.1 ino.example.com # inode\n' > "$work/hosts.cfg"

mkdir -p "$work/home/etc" "$work/home/tmp" "$work/home/www"
# Xymon's own holidays.cfg, holidays as Sundays: xymond does not load it
# for a DOWNTIME, and neither does the API.
printf 'HOLIDAYLIKEWEEKDAY=0\n' > "$work/home/etc/holidays.cfg"
require_cfg XYMONSERVER_CFG "$XYMON_SRC/xymond/etcfiles/xymonserver.cfg"
sed -e 's|^XYMONHOME=.*|XYMONHOME="'"$work"'/home"|' \
    -e 's|^XYMONTMP=.*|XYMONTMP="'"$work"'/home/tmp"|' \
	"$XYMONSERVER_CFG" > "$work/xymonserver.cfg"

xymond_launch() {
	local port=$1; shift
	"$XYMOND" --no-daemon --listen="127.0.0.1:$port" \
		--hosts="$work/hosts.cfg" --env="$work/xymonserver.cfg" \
		--pidfile="$work/xymond.pid" --checkpoint-file="$work/chk.out" \
		"$@" \
		> "$work/xymond.log" 2>&1 &
	# shellcheck disable=SC2034 # read by xymond-daemon.sh and the cleanup
	XYMOND_PID=$!
}

start_xymond

send() { "$XYMONCLIENT" "127.0.0.1:$PORT" "$1" || fail "xymond rejected: $1"; }
send "status red,example,com.conn red down"
send "status green,example,com.conn green up"
send "status disk,example,com.disk yellow Filesystems NOT ok
/var at 91% - 2.1G of 24G free
/boot ok"
# An acknowledgement names the status by the cookie xymond gave it.
sleep 0.4
cookie=$("$XYMONCLIENT" "127.0.0.1:$PORT" "xymondboard host=disk.example.com test=disk fields=cookie")
[ -n "$cookie" ] || fail "xymond gave the yellow status no cookie"
send "xymondack $cookie 60 cleaning old kernels, back in an hour"
# Acknowledged from the web page: its words, then who and from where
# (web/acknowledge.c).
send "status wack,example,com.conn red down"
cookie=$("$XYMONCLIENT" "127.0.0.1:$PORT" "xymondboard host=wack.example.com test=conn fields=cookie")
[ -n "$cookie" ] || fail "xymond gave the red status no cookie"
send "xymondack $cookie 60 rebooting it 
Acked by: bruno (10.0.0.9)"
send "status dis,example,com.conn red down"
send "disable dis,example,com.conn 7200 maintenance window"
# A disable as the web page sends it (web/enadis.c), who and from where
# in a form of its own.
send "status wdis,example,com.conn red down"
send "disable wdis,example,com.conn 7200 
Disabled by: bruno @ 10.0.0.9
Reason: disk being replaced
"
# Clear as xymonnet sends it, for a host it could not reach: xymond chose
# nothing, so no colour of the test's own is behind it.
send "status clr,example,com.conn clear Thu Nov 19 18:56:26 2026: no answer"
# xymonnet's clear behind a host it cannot reach: red's conn is red.
send "status red,example,com.ssh clear Ping failed, or dialup host"
send "status dtw,example,com.conn red down"
# A change to red deferred: delayred with delayyellow keeps it green.
send "status pend,example,com.conn green up"
send "status pend,example,com.conn red down"
# A modifier turns a green conn red, as a DS rule's RRD handler does.
send "status mod,example,com.conn green up"
send "modify mod,example,com.conn red apitest response too slow"
send "status mod,example,com.conn green up"
# Red in a DOWNTIME window, all day: xymond records it blue, no disable set.
send "status dt,example,com.conn red down"
# A first line holding a "|", which the board does not encode in line1.
send "status pipe,example,com.conn red port 80 | port 443 down
second line"
# The inode status xymond's client analysis writes: one ID= line for each
# file system in alarm.
send "status ino,example,com.inode red Filesystems NOT ok
&red <!-- ID=/var --> /var (95% used) has reached the PANIC level (90%)
&yellow <!-- ID=/home --> /home (75% used) has reached the WARNING level (70%)
&red <!-- ID=/mnt/nfs --> /mnt/nfs is unreachable (not measured)
/ ok"
# A host whose name begins with another's, with a status of its own.
send "status disk2,example,com.disk green Filesystems all ok"
# Characters xymondboard encodes on its way out: | tab \ and a literal \n.
send "status enc,example,com.conn green C:\\temp | cpu	load \\n not a newline"
# A lifetime with a unit and a group, both legal on the command line.
send "status+5h/group:ops lt,example,com.conn green up for 5h"
# An acknowledgement that has already run out: 0 minutes.
cookie=$("$XYMONCLIENT" "127.0.0.1:$PORT" "xymondboard host=red.example.com test=conn fields=cookie")
[ -n "$cookie" ] || fail "xymond gave the red status no cookie"
send "xymondack $cookie 0 already over"
# Acknowledged from the critical-systems view: ackinfo puts it in acklist,
# HOST.TEST, level, seconds, who and words on lines of their own
# (web/ackinfo.c), and leaves acktime at 0. One for an hour; one for a
# second, which has run out by the time it is asked for.
send "status crit,example,com.conn red down"
send "status critold,example,com.conn red down"
send "status critcolon,example,com.conn red down"
send "ackinfo crit.example.com.conn
1
3600
alice
on it from the critical view"
# Acknowledged by a name holding a colon: who and the words come whole, as
# the colon cannot be told from the one between them (#89).
send "ackinfo critcolon.example.com.conn
1
3600
dom:alice
by with a colon"
send "ackinfo critold.example.com.conn
1
1
bob
was on it"
sleep 1.2

# A status with a secret in it, as a process list shows a command line.
send "status enc2,example,com.procs green up
root  1234  mysqld --password=hunter2 --port=3306
Token: abc"
sleep 0.4

# XYMONAPI_HIDE: what its expressions match is [hidden] in every text.
printf '# secrets on command lines\npassword=\\S+\n\nToken: \\w+\n' > "$work/hide"
export XYMON="$XYMONCLIENT" XYMSRV="127.0.0.1:$PORT" XYMONAPI_HIDE="$work/hide" XYMONHOME="$work/home"
start_api

health=$(api_get /health)
assert_contains '"xymond":{"alive":true' "$health" "/health while xymond runs"
assert_contains '"answer":"xymond' "$health" "/health gives the xymond it asked, as it answered"
assert_contains '"api":{"version":' "$health" "/health gives the API's version under api"

# detail HOST TEST -- the alarm of HOST's TEST, by its id, text included.
id_re='"id":"([0-9a-f]+)"'
detail() {
	local list
	list=$(api_get "/alarms?host=$1&test=$2")
	[[ $list =~ $id_re ]] || { printf '{}'; return 0; }
	api_get "/alarms/${BASH_REMATCH[1]}"
}
red=$(api_get '/alarms?host=red.example.com&test=conn')
assert_contains '"host":"red.example.com","test":"conn"' "$red" "/alarms for the red host"
assert_contains '"severity":"critical","state":"firing"' "$red" "a red status is critical, firing"

green=$(api_get '/alarms?host=green.example.com&test=conn')
assert_contains '"severity":"cleared","state":"inactive"' "$green" "a green status is cleared, inactive"
assert_contains '"state":"firing"' "$(api_get '/alarms?state=firing')" "state=firing gives what needs acting on"
assert_not_contains '"host":"green.example.com"' "$(api_get '/alarms?state=firing')" "and not the green"

# /alarms says when an alarm is acknowledged, in the same shape as /alarms/{id}:
# a page drawing the board picks its icon by it. Both ways, xymondack's
# acktime and the critical-systems view's acklist, running and run out.
acked=$(api_get '/alarms?host=disk.example.com&test=disk')
assert_contains '"acknowledged":{"until":"' "$acked" "/alarms gives an acknowledgement made with xymondack, with its end time"
assert_contains 'cleaning old kernels' "$acked" "and its words"
ackof() { printf '%s' "$1" | grep -o '"acknowledged":{[^}]*}'; }
assert_not_contains '"since"' "$(ackof "$acked")" "and no start: xymondack keeps none"
assert_not_contains '"ackedBy":' "$acked" "and no one, sent with xymon(1)"
assert_contains '"ackedBy":"bruno","from":"10.0.0.9","text":"rebooting it"' "$(api_get '/alarms?host=wack.example.com&test=conn')" \
	"the web page's acknowledgement: who, from where, and the words alone"
crit=$(api_get '/alarms?host=crit.example.com&test=conn')
assert_contains '"acknowledged":{"until":"' "$crit" "/alarms gives one from the critical-systems view, in acklist alone"
assert_contains '"text":"alice:on it from the critical view"' "$crit" "with who acknowledged and the words, whole"
assert_contains '"since":"20' "$(ackof "$crit")" "and when it was made, which acklist keeps"
assert_contains '"text":"dom:alice:by with a colon"' "$(api_get '/alarms?host=critcolon.example.com&test=conn')" \
	"a name holding a colon does not shift the words: who and the words come whole"
assert_not_contains '"acknowledged"' "$red" "an acknowledgement with xymondack that ran out is not given, though xymond still carries it"
assert_not_contains '"acknowledged"' "$(api_get '/alarms?host=critold.example.com&test=conn')" "nor one in acklist that ran out"
assert_not_contains '"acknowledged"' "$green" "a state nobody acknowledged has none"
assert_not_contains '"acknowledged"' "$(api_get '/alarms?host=dis.example.com&test=conn')" "nor has a disabled one, whose status says it"
ack_st=$(detail disk.example.com disk)
ack_st=${ack_st#*\"acknowledged\":}; ack_st=${ack_st%%\}*}
assert_contains "$ack_st" "$acked" "/alarms and /alarms/{id} give the same acknowledgement"

alarms=$(api_get /alarms)
assert_contains '"host":"red.example.com","test":"conn"' "$alarms" "a red status is an alarm"
assert_contains '"host":"green.example.com","test":"conn","labels":{"category":"network"},"severity":"cleared","state":"inactive"' "$alarms" "a green status is an alarm too, cleared and inactive, as TMF642 keeps one"
# alarm HOST:TEST -- that alarm in $alarms, whole: up to the next one.
alarm() { a=${alarms#*\"host\":\"${1%%:*}\",\"test\":\"${1#*:}\"}; printf '%s' "${a%%\},\{\"id\"*}"; }
assert_contains '"severity":"critical","state":"firing"' "$(alarm red.example.com:conn)" "red: critical, firing"
assert_contains '"severity":"warning","state":"firing"' "$(alarm disk.example.com:disk)" "yellow: warning, firing"
assert_contains '"severity":"critical","state":"suppressed"' "$(alarm dis.example.com:conn)" "blue over red: the red it measured, critical, and suppressed"
assert_contains '"suppressedBy":[{"kind":"disable","of":"test","until":"' "$(alarm dis.example.com:conn)" "by a disable, the test's, with its end"
assert_contains '"text":"maintenance window"' "$(alarm dis.example.com:conn)" "and its text"
assert_not_contains '"createdBy":' "$(alarm dis.example.com:conn)" "a disable sent with xymon(1) says no one"
assert_contains '"createdBy":"bruno","from":"10.0.0.9","text":"disk being replaced"' "$(alarm wdis.example.com:conn)" "the web page's: who, from where, and the reason alone"
assert_contains '"state":"suppressed"' "$(alarm dt.example.com:conn)" "red in a DOWNTIME window: suppressed"
assert_contains '"suppressedBy":[{"kind":"downtime","of":"test","text":"Maint"' "$(alarm dt.example.com:conn)" "by the DOWNTIME, its cause as xymond keeps it"
assert_not_contains '"until"' "$(alarm dt.example.com:conn)" "all day every day, it never ends"
assert_contains "\"suppressedBy\":[{\"kind\":\"downtime\",\"of\":\"test\",\"until\":\"$dtw_until\"" "$(alarm dtw.example.com:conn)" "a window read from hosts.cfg ends the minute after its end, holidays on or not"
assert_contains '"text":"Window"' "$(alarm dtw.example.com:conn)" "with its cause"
assert_contains '"severity":"critical","state":"pending"' "$(alarm pend.example.com:conn)" "a red still shown green by a change delay: critical, pending"
assert_contains '"overriddenBy":[{"kind":"modifier","text":"response too slow"' "$(alarm mod.example.com:conn)" "a modifier in force says so, with its cause"
assert_contains '"host":"mod.example.com"' "$(api_get '/alarms?overridden=true')" "overridden=true finds it"
assert_not_contains '"host":"red.example.com"' "$(api_get '/alarms?overridden=true')" "and not an alarm shown as reported"
assert_contains '"host":"disk.example.com"' "$(api_get '/alarms?state=firing&acknowledged=true')" "acknowledged=true finds the acknowledged"
assert_not_contains '"host":"disk.example.com"' "$(api_get '/alarms?state=firing&acknowledged=false')" "acknowledged=false leaves it out"
assert_contains '"host":"red.example.com","test":"conn"' "$(api_get '/alarms?state=firing&acknowledged=false')" "and keeps what nobody has in hand"
assert_contains '"labels":{"category":"filesystem"}' "$(api_get '/alarms?category=filesystem')" "category=filesystem gives the file systems"
assert_not_contains '"category":"network"' "$(api_get '/alarms?category=filesystem')" "and only them"
assert_not_contains '"suppressedBy"' "$(alarm red.example.com:conn)" "red is not suppressed"
assert_contains '"severity":"indeterminate","state":"firing"' "$(alarm clr.example.com:conn)" "a clear with nothing behind it, indeterminate"
assert_not_contains '"unreachable"' "$(alarm clr.example.com:conn)" "and not unreachable: no conn red, no colour kept behind it"
[[ $red =~ $id_re ]] || fail "the red state has no id"
conn_id=${BASH_REMATCH[1]}
assert_contains "\"unreachable\":{\"reportedBy\":[\"$conn_id\"]" "$(alarm red.example.com:ssh)" "a clear ssh on a host whose conn is red: unreachable, reported by that conn"
assert_not_contains '"unreachable"' "$(alarm red.example.com:conn)" "red is not unreachable"
disk_alarm=$(alarm disk.example.com:disk)
assert_contains '"message":"Filesystems NOT ok"' "$disk_alarm" "an alarm gives its status's first line, the colour left out"
assert_contains '"source":"127.0.0.1"' "$disk_alarm" "who sent it"
assert_contains '"updated":"' "$disk_alarm" "when it was last reported"
assert_contains '"acknowledged":{"until":"' "$disk_alarm" "its acknowledgement"
assert_contains '"text":"cleaning old kernels, back in an hour","of":"test"' "$disk_alarm" "with its words, said to be the test's"
disk_one=$(api_get '/alarms?host=disk.example.com&test=disk')
[[ $disk_one =~ $id_re ]] || fail "the disk alarm has no id"
assert_contains "\"link\":\"alarms/${BASH_REMATCH[1]}\"" "$disk_one" "a link to itself"
assert_contains '"text":"Filesystems NOT ok' "$(api_get "/alarms/${BASH_REMATCH[1]}")" "which gives its text"
assert_not_contains '"acknowledged"' "$(alarm red.example.com:conn)" "an acknowledgement run out is not given"
assert_contains '"message":"port 80 | port 443 down"' "$(alarm pipe.example.com:conn)" "a first line holding a | is given whole"
assert_contains '"message":"no answer"' "$(alarm clr.example.com:conn)" "the date a status opens with is left out of its message"
assert_contains '"severity":"critical"' "$(alarm pipe.example.com:conn)" "and the fields before it are read in their place"
assert_contains '"labels":{"category":"filesystem"}' "$disk_alarm" "disk lies in the filesystem category"
assert_contains '"labels":{"category":"network"}' "$(alarm red.example.com:conn)" "conn in network"
# inode: one alarm for each file system its status names.
ino() { printf '%s' "$alarms" | sed 's/},{"id"/}\n{"id"/g' | grep -F "\"instance\":\"$1\""; }
inos=$(printf '%s' "$alarms" | sed 's/},{"id"/}\n{"id"/g' | grep -F '"host":"ino.example.com","test":"inode"')
assert_equal 3 "$(printf '%s\n' "$inos" | wc -l | tr -d ' ')" "an inode alarm, one for each file system in alarm"
assert_equal 3 "$(printf '%s\n' "$inos" | grep -o '"id":"[0-9a-f]\{16\}"' | sort -u | wc -l | tr -d ' ')" "each its own id, opaque: not host:test, which the three share"
assert_contains '"severity":"critical"' "$(ino /var)" "/var: critical"
assert_contains '"message":"/var (95% used) has reached the PANIC level (90%)"' "$(ino /var)" "its own line"
assert_contains '"metric":"pct","measure":{"value":95,"unit":"%","critical":90}' "$(ino /var)" "its pct and the panic level crossed"
assert_contains '"severity":"warning"' "$(ino /home)" "/home: warning, from its own line"
assert_contains '"measure":{"value":75,"unit":"%","warning":70' "$(ino /home)" "and the warning level crossed"
assert_contains '"measure":{"state":"unreachable"' "$(ino /mnt/nfs)" "/mnt/nfs: unreachable, a state"
assert_not_contains '"instance":"/"' "$alarms" "a file system that is ok is no alarm"
assert_not_contains '"instance"' "$disk_alarm" "disk names no instance: its lines have no ID="

# /alarms/{id}: the text behind a colour, with what was done about it.
st=$(detail disk.example.com disk)
assert_contains '"severity":"warning","state":"firing"' "$st" "/alarms/{id} gives the alarm"
assert_contains '"text":"Filesystems NOT ok' "$st" "and the status text, without the command line that set it"
assert_contains '/var at 91%' "$st" "newlines unescaped"
assert_contains '2.1G of 24G free\n/boot ok' "$st" "line by line"
assert_contains '"acknowledged":{' "$st" "an acknowledged status says so"
assert_contains 'cleaning old kernels' "$st" "with the acknowledgement's words"
assert_not_contains '"suppressedBy"' "$st" "and is not suppressed"
dis=$(detail dis.example.com conn)
assert_contains '"suppressedBy":[{"kind":"disable"' "$dis" "a disabled test says so"
assert_contains 'maintenance window' "$dis" "with the reason given"
assert_contains '"state":"suppressed"' "$dis" "and its state is suppressed, as the board shows it blue"
hosts=$(api_get '/hosts')
assert_contains '{"host":"red.example.com"}' "$hosts" "/hosts gives each host by its name"
assert_equal 1 "$(printf '%s' "$hosts" | grep -o '"host":"red.example.com"' | wc -l | tr -d ' ')" "once, though it has several tests"
wdis=$(detail wdis.example.com conn)
assert_contains '"createdBy":"bruno","from":"10.0.0.9","text":"disk being replaced"' "$wdis" "/alarms/{id} reads the web page's disable as /alarms does"
assert_equal "404" "$(api_code '/alarms/0123456789abcdef')" "/alarms/{id} of no alarm"
assert_equal "404" "$(api_code '/alarms/not-an-id')" "nor of a word that is no id"
# xymondboard matches host= and test= as unanchored regular expressions;
# the API must not pass on another host's status as this one's.
assert_contains '"text":"Filesystems NOT ok' "$(detail disk.example.com disk)" "disk.example.com gets its own text, not disk2's"
assert_contains '"text":"Filesystems all ok"' "$(detail disk2.example.com disk)" "and disk2.example.com its own"
assert_contains '{"items":[]}' "$(api_get '/alarms?host=disk.example&test=disk')" "a host name that is the start of a real one finds none"
assert_contains '{"items":[]}' "$(api_get '/alarms?host=disk.example.com&test=dis')" "a test name that is the start of a real one finds none"
assert_contains '{"items":[]}' "$(api_get '/alarms?host=d.sk.example.com&test=disk')" "a dot is a dot, not any character"
enc=$(detail enc.example.com conn)
assert_contains '"text":"C:\\temp | cpu\tload \\n not a newline"' "$enc" "a pipe, a tab, a backslash and a literal \\n are decoded as xymondboard encoded them"
assert_contains '"text":"up for 5h"' "$(detail lt.example.com conn)" "the command line is left out when it has a lifetime with a unit and a group"
assert_not_contains '"acknowledged"' "$(detail red.example.com conn)" "an acknowledgement that ran out is not reported, though xymond still carries it"
crit=$(detail crit.example.com conn)
assert_contains '"acknowledged":{' "$crit" "an acknowledgement from the critical-systems view, in acklist alone, says so"
assert_contains 'on it from the critical view' "$crit" "with its words"
assert_not_contains '"acknowledged"' "$(detail critold.example.com conn)" "one in acklist that ran out is not reported"

hid=$(detail enc2.example.com procs)
assert_contains 'mysqld --[hidden] --port=3306' "$hid" "XYMONAPI_HIDE blanks a password on a command line"
assert_contains '[hidden]' "$hid" "and a token"
assert_not_contains 'hunter2' "$hid" "the password is gone"
assert_not_contains 'abc' "$hid" "and so is the token"
assert_contains 'Filesystems NOT ok' "$(detail disk.example.com disk)" "other texts are untouched"
assert_contains 'cleaning old kernels' "$(detail disk.example.com disk)" "an acknowledgement too"
# A file of expressions that is not one stops the API: silently hiding
# nothing would be worse.
stop_process "$API_PID"; API_PID=""
printf 'password=(\n' > "$work/badhide"
rc=0
XYMONAPI_HIDE="$work/badhide" XYMONAPI_LISTEN="127.0.0.1:$API_PORT" "$ROOT/plugins/xymonapi/xymonapi.sh" > "$work/badhide.log" 2>&1 || rc=$?
assert_equal "1" "$rc" "the API with an expression that is not one"
assert_contains 'XYMONAPI_HIDE' "$(cat "$work/badhide.log")" "and says which setting"
assert_contains 'line 1' "$(cat "$work/badhide.log")" "and which line"
rc=0
XYMONAPI_HIDE="$work/no-such-file" XYMONAPI_LISTEN="127.0.0.1:$API_PORT" "$ROOT/plugins/xymonapi/xymonapi.sh" > "$work/nohide.log" 2>&1 || rc=$?
assert_equal "1" "$rc" "the API with a hide file it cannot read"
assert_contains 'cannot read XYMONAPI_HIDE' "$(cat "$work/nohide.log")" "and says so"
unset XYMONAPI_HIDE
start_api

assert_equal "404" "$(api_code /views)" "an operation the API does not implement"

pass "the API reports xymond's board: its alarms, green ones too, each with its severity, state and flags, one with its text and acknowledgement, and health"
