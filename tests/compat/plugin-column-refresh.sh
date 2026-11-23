#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-column-refresh.sh
#
# The plugins column sent at once: with xymon-plugin's task on, an install,
# update or remove that changed the server's part, and enable of
# xymon-plugin, run the installed reporter with no wait under xymoncmd, and
# say what it sent; one that cannot send says so, and the command ends as
# it would have. Nothing is sent with the task off, by a run that changed
# nothing, under DESTDIR, by the tools, by enable of another plugin or
# disable, nor once xymon-plugin itself is removed.
#
# Xymon and GitHub are never reached: xymoncmd, xymon, curl and sleep are
# stand-ins, as in plugins/xymon-plugin/tests/xymon-plugin-report.sh.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
home=$work/server
server_tree "$home"
printf 'directory %s/etc/tasks.d\n' "$home" > "$home/etc/tasks.cfg"
want=$(sed -n 's/^version: *//p' "$ROOT/plugins/xymon-plugin/PLUGIN")
api=$(sed -n 's/^version: *//p' "$ROOT/plugins/xymonapi/PLUGIN")
# enable refuses a plugin whose Python lacks its modules: a stand-in that
# has every one.
printf '#!/bin/sh\nexit 0\n' > "$work/haspy"; chmod 755 "$work/haspy"
export XYMONAPI_PYTHON="$work/haspy"

# The stand-ins: xymoncmd sets what xymonserver.cfg says, keeps how it was
# run, and runs the command; xymon keeps each status sent, answers the
# read-back with its colour, or fails with XYMONFAIL; curl prints the
# releases in $work/tags, or fails with CURL=fail; sleep keeps a wait asked.
bin=$work/bin; mkdir -p "$bin"
printf 'XYMON="%s"\nXYMSRV="0.0.0.0"\nMACHINEDOTS="srv.example.com"\nXYMONHOME="%s"\n' "$bin/xymon" "$home" >> "$home/etc/xymonserver.cfg"
cat > "$home/bin/xymoncmd" <<'SH'
#!/bin/sh
case $1 in --env=*) f=${1#--env=}; shift ;; *) f=$(dirname "$0")/../etc/xymonserver.cfg ;; esac
set -a; eval "$(grep '^[A-Z_]*=' "$f")"; set +a
[ -z "${WORK:-}" ] || echo "WAIT=${XYMON_PLUGINS_WAIT:-unset} $*" >> "$WORK/xymoncmd"
exec "$@"
SH
cat > "$bin/xymon" <<'SH'
#!/bin/sh
[ -n "${XYMONFAIL:-}" ] && { echo "Could not connect to Xymon daemon@$1" >&2; exit 5; }
case $2 in
xymondboard*) sed -n '1s/^status+[^ ]* [^ ]* \([a-z]*\) .*/\1/p' "$WORK/sent" ;;
*) printf '%s\n' "$2" > "$WORK/sent"; echo sent >> "$WORK/sends" ;;
esac
SH
cat > "$bin/curl" <<'SH'
#!/bin/sh
[ "${CURL:-}" = fail ] && { echo "curl: (6) Could not resolve host" >&2; exit 6; }
for a; do u=$a; done
case $u in *page=1) ;; *) echo '[]'; exit 0 ;; esac
printf '['; sep=; while read -r t; do printf '%s{"tag_name": "%s"}' "$sep" "$t"; sep=,; done < "$WORK/tags"; printf ']\n'
SH
# shellcheck disable=SC2016 # expanded by the stand-in
printf '#!/bin/sh\necho "$1" >> "$WORK/slept"\n' > "$bin/sleep"
chmod 755 "$home/bin/xymoncmd" "$bin/xymon" "$bin/curl" "$bin/sleep"
export WORK=$work PATH="$bin:$PATH"
printf 'xymon-plugin/v%s\nxymonapi/v%s\n' "$want" "$api" > "$work/tags"

# run NAME ARGS... -- the installer on this server, its output in
# $work/NAME.log, its exit in RC; what was sent is counted from nothing.
run() {
	local name=$1; shift
	rm -f "$work/sent" "$work/sends" "$work/xymoncmd"; RC=0
	"$ROOT/xymon-plugin" "$@" XYMONHOME="${H:-$home}" MANDIR="$work/man" >"$work/$name.log" 2>&1 || RC=$?
}
sends() { if [ -f "$work/sends" ]; then wc -l < "$work/sends" | tr -d ' '; else echo 0; fi; }
log() { cat "$work/$1.log"; }
# none NAME WHY -- nothing sent, nor said, by the run NAME, which ended with 0.
none() {
	assert_equal 0 "$RC" "run $1 ended with 0: $(log "$1")"
	assert_equal 0 "$(sends)" "[S33] $2: nothing is sent"
	assert_not_contains "plugins column" "$(log "$1")" "[S33] $2: nothing is said of the column"
}
# once NAME WHY -- the column sent once by the run NAME, at once, under
# xymoncmd, which ended with 0, saying it.
once() {
	assert_equal 0 "$RC" "run $1 ended with 0: $(log "$1")"
	assert_equal 1 "$(sends)" "[S33] $2: the column is sent once: $(log "$1")"
	assert_contains "WAIT=0 /bin/sh $home/ext/xymon-plugin/xymon-plugin-report.sh" "$(cat "$work/xymoncmd")" "[S33] $2: by the installed reporter, under xymoncmd, with no wait"
	assert_contains "status+31h srv,example,com.plugins green " "$(first_line "$(cat "$work/sent")")" "[S33] $2: the server's status, from xymonserver.cfg"
	assert_contains "sent green" "$(log "$1")" "[S33] $2: and says what it sent"
	[ ! -e "$work/slept" ] || fail "[S33] $2: the reporter waited $(cat "$work/slept")"
}

run i1 install --server xymon-plugin
none i1 "the task off, an install"
run en enable --server xymon-plugin
once en "enable xymon-plugin"
run en2 enable --server xymon-plugin
once en2 "enable of xymon-plugin on already: the way to have the column sent now"

run ia install --server xymonapi
once ia "an install of another plugin"
assert_contains "&green xymonapi: $api installed" "$(cat "$work/sent")" "[S33] the status names the plugin just installed"
run ena enable --server xymonapi
none ena "enable of another plugin"
run dis disable --server xymonapi
none dis "disable"

# An update: the column has the version it put in place.
printf 'xymon-plugin/v0.0.1\n' > "$home/ext/xymon-plugin/VERSION"
run up update --server xymon-plugin
once up "an update"
assert_contains "&green xymon-plugin: $want installed; up to date" "$(cat "$work/sent")" "[S33] the status has the version the update installed"
assert_not_contains "0.0.1" "$(cat "$work/sent")" "[S33] not the one before it"

run upr update --server xymonapi-rag
[ "$RC" -ne 0 ] || fail "update of a plugin not installed was not refused"
assert_equal 0 "$(sends)" "[S33] an update refused: nothing is sent"
run rma remove --server xymonapi-rag
none rma "a remove of a plugin not installed"

# Sending fails, or GitHub is not reached: said, the command's exit unchanged.
XYMONFAIL=1 run xf update --server xymonapi
assert_equal 0 "$RC" "[S33] a send that fails leaves the command's exit alone: $(log xf)"
assert_contains "could not send green" "$(log xf)" "[S33] a send that fails is said"
CURL=fail run cf update --server xymonapi
assert_equal 0 "$RC" "[S33] GitHub not reached leaves the command's exit alone: $(log cf)"
assert_equal 0 "$(sends)" "[S33] GitHub not reached: nothing is sent"
assert_contains "nothing sent: " "$(log cf)" "[S33] GitHub not reached is said"
# The reporter gone, or xymoncmd: said, nothing sent.
mv "$home/ext/xymon-plugin/xymon-plugin-report.sh" "$work/report.sh"
run gone update --server xymonapi
assert_equal 0 "$RC" "[S33] the reporter gone leaves the command's exit alone: $(log gone)"
assert_contains "The plugins column is not sent: $home/ext/xymon-plugin/xymon-plugin-report.sh is gone" "$(log gone)" "[S33] the reporter gone is said"
mv "$work/report.sh" "$home/ext/xymon-plugin/xymon-plugin-report.sh"
mv "$home/bin/xymoncmd" "$work/xymoncmd.sh"
run nocmd update --server xymonapi
assert_equal 0 "$RC" "[S33] xymoncmd missing leaves the command's exit alone: $(log nocmd)"
assert_equal 0 "$(sends)" "[S33] xymoncmd missing: nothing is sent"
assert_contains "The plugins column is not sent: no $home/bin/xymoncmd" "$(log nocmd)" "[S33] xymoncmd missing is said"
mv "$work/xymoncmd.sh" "$home/bin/xymoncmd"

run rm remove --server xymonapi
once rm "a remove of another plugin"

# --all with every plugin installed changes nothing.
run all install --server --all
[ "$(sends)" = 1 ] || fail "[S33] install --all of the plugins not installed sent $(sends) statuses: $(log all)"
run all2 install --server --all
none all2 "install --all, every plugin installed already"

# The task off.
run off disable --server xymon-plugin
none off "disable of xymon-plugin"
run uoff update --server xymonapi
none uoff "the task off, an update"
run on enable --server xymon-plugin
once on "enable xymon-plugin again"

# The tools, XYMONHOME this server's all the same: not its part.
run tools install --tools xymonapi PREFIX="$work/tools"
none tools "an install of the tools"

# Under DESTDIR, the task on there and xymoncmd at its installed place.
H=$home run d1 install --server xymon-plugin DESTDIR="$work/stage"
none d1 "under DESTDIR, an install"
H=$home run d2 enable --server xymon-plugin DESTDIR="$work/stage"
[ -L "$work/stage$home/etc/tasks.d/xymon-plugin.cfg" ] || fail "enable under DESTDIR made no link: $(log d2)"
none d2 "under DESTDIR, enable xymon-plugin"
H=$home run d3 update --server xymon-plugin DESTDIR="$work/stage"
none d3 "under DESTDIR, an update"

# xymon-plugin itself removed: its task with it, nothing sent.
for n in xymonapi-agent xymonapi-mcp xymonapi-rag xymonapi; do
	run "rm-$n" remove --server "$n"
done
run rmself remove --server xymon-plugin
none rmself "xymon-plugin itself removed"

pass "the plugins column is sent at once, under xymoncmd and with no wait, after an install, update or remove that changed the server's part and after enable of xymon-plugin, its task on; said when it cannot be, the command's exit unchanged; nothing sent with the task off, under DESTDIR, by a run that changed nothing, by enable of another plugin or disable, or once xymon-plugin is removed"
