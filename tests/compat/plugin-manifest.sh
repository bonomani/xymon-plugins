#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-manifest.sh
#
# An install records what it wrote (S29). After an install and an update of
# each part, MANIFEST in the plugin's directory has one line for each file
# and link the install wrote, and none for anything else: every file of the
# directory by its path from it, with its cksum and size, the task file and
# the snippets marked admin; outside it, by their paths as installed, the
# copy /plugins serves, the command, and the manual page's link with its
# target. The task link and a SELinux module loaded are states and stay
# out. Under DESTDIR the paths are the installed system's. Fields are
# separated by tabs.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
home=$work/server
server_tree "$home"
person=$work/home
mkdir -p "$person"
export HOME="$person" XDG_CONFIG_HOME="$person/.config" PREFIX="$person/.local" MANDIR="$work/man"
export XYMON_PLUGINS_TREES_ONLY=1 XYMON_PLUGINS_TREES="$home"
TAB=$(printf '\t')

x() { "$ROOT/xymon-plugin" "$@" </dev/null >"$work/x.log" 2>&1 || fail "xymon-plugin $* failed: $(tail -n 5 "$work/x.log")"; }

# expect DIR LINES... -- every line of DIR/MANIFEST is one of what DIR and
# the places outside hold, and each of those has its line.
expect() {
	m=$1/MANIFEST; shift
	assert_file_exists "$m"
	printf '%s\n' "$@" | LC_ALL=C sort > "$work/want"
	LC_ALL=C sort "$m" > "$work/got"
	diff "$work/want" "$work/got" > "$work/diff" || fail "[S29] $m differs from what was written: $(cat "$work/diff")"
}
# line PATH NAME [admin] -- the file line expected for PATH, named NAME.
line() { printf 'file\t%s\t%s%s\n' "$(cksum < "$1")" "$2" "${3:+$TAB$3}"; }

# The server part: xymonapi, its task on, so a link the manifest must leave out.
x install --server xymonapi XYMONHOME="$home"
x enable --server xymonapi XYMONHOME="$home"
for step in install update; do
	[ "$step" = update ] && x update --server xymonapi XYMONHOME="$home"
	ext=$home/ext/xymonapi
	want=()
	while IFS= read -r f; do
		case $f in
			tasks.cfg|xymonapi-apache.conf|xymonapi-nginx.conf|xymonapi-lighttpd.conf) want+=("$(line "$ext/$f" "$f" admin)") ;;
			*) want+=("$(line "$ext/$f" "$f")") ;;
		esac
	done < <(cd "$ext" && find . -type f ! -name MANIFEST | sed 's|^\./||')
	for f in $(cd "$home/ext/xymon-plugins-dist/plugins/xymonapi" && ls); do
		want+=("$(line "$home/ext/xymon-plugins-dist/plugins/xymonapi/$f" "$home/ext/xymon-plugins-dist/plugins/xymonapi/$f")")
	done
	want+=("$(printf 'link\t%s\t%s' "$MANDIR/man8/xymonapi.8" "$home/ext/xymonapi/xymonapi.8")")
	expect "$ext" "${want[@]}"
done
assert_contains "${TAB}tasks.cfg${TAB}admin" "$(cat "$home/ext/xymonapi/MANIFEST")" "[S29] the task file is marked the administrator's"
assert_not_contains "tasks.d" "$(cat "$home/ext/xymonapi/MANIFEST")" "[S29] the task link, a state, is not in it"
[ -L "$home/etc/tasks.d/xymonapi.cfg" ] || fail "the task was not on"

# The same code updated again: MANIFEST, the same lines, is left as it is,
# so that what watches it -- the API, by its inode -- goes on (S29). From
# a copy whose app.py differs, it is written anew.
ino() { ls -i "$1" | awk '{ print $1 }'; }
before=$(ino "$home/ext/xymonapi/MANIFEST")
x update --server xymonapi XYMONHOME="$home"
[ "$(ino "$home/ext/xymonapi/MANIFEST")" = "$before" ] || fail "[S29] an update to the same code wrote MANIFEST anew: what watches it restarts for nothing"
alt=$work/alt; mkdir "$alt"
cp -R "$ROOT/xymon-plugin" "$ROOT/LICENSE" "$ROOT/plugins" "$alt/"
echo "# changed" >> "$alt/plugins/xymonapi/app.py"
"$alt/xymon-plugin" update --server xymonapi XYMONHOME="$home" </dev/null >"$work/x.log" 2>&1 || fail "the update from the copy failed: $(tail -n 5 "$work/x.log")"
[ "$(ino "$home/ext/xymonapi/MANIFEST")" != "$before" ] || fail "[S29] an update to other code left MANIFEST as it was: what watches it runs the old code"
assert_contains "$(cksum < "$alt/plugins/xymonapi/app.py")${TAB}app.py" "$(cat "$home/ext/xymonapi/MANIFEST")" "[S29] and it records the new app.py"
x update --server xymonapi XYMONHOME="$home"
# A virtualenv made by the update: the lines are the same, the modules may
# not be, so MANIFEST is written anew. A stand-in Python, with every module,
# that makes one -- none there before: where a Python here has the modules,
# the install made one already.
cat > "$work/mkpy" <<'SH'
#!/bin/sh
case $* in
*sys.executable*) echo "$0" ;;
"-m venv --system-site-packages "*) mkdir -p "$4/bin" && cp "$0" "$4/bin/python3" && : > "$4/pyvenv.cfg" ;;
esac
exit 0
SH
chmod 755 "$work/mkpy"
rm -rf "$home/ext/venv"
before=$(ino "$home/ext/xymonapi/MANIFEST")
x update --server xymonapi XYMONHOME="$home" PYTHON="$work/mkpy"
[ -x "$home/ext/venv/bin/python3" ] || fail "the stand-in Python made no virtualenv: $(tail -n 5 "$work/x.log")"
[ "$(ino "$home/ext/xymonapi/MANIFEST")" != "$before" ] || fail "[S29] an update that made a virtualenv left MANIFEST as it was: what watches it runs the old modules"
rm -rf "$home/ext/venv"

# Your tools: xymonapi-mcp, with a command and a manual page.
for step in install update; do
	x "$step" --tools xymonapi-mcp
	dir=$PREFIX/libexec/xymon-plugins/xymonapi-mcp
	want=()
	while IFS= read -r f; do want+=("$(line "$dir/$f" "$f")"); done \
		< <(cd "$dir" && find . -type f ! -name MANIFEST | sed 's|^\./||')
	want+=("$(line "$PREFIX/bin/xymonapi-mcp" "$PREFIX/bin/xymonapi-mcp")")
	want+=("$(printf 'link\t%s\t%s' "$PREFIX/share/man/man1/xymonapi-mcp.1" "$dir/xymonapi-mcp.1")")
	expect "$dir" "${want[@]}"
done

# xymonapi-mcp watches its MANIFEST too: the same code, left as it is.
before=$(ino "$dir/MANIFEST")
x update --tools xymonapi-mcp
[ "$(ino "$dir/MANIFEST")" = "$before" ] || fail "[S29] an update of the tools to the same code wrote MANIFEST anew"

# Under DESTDIR: the paths are the installed system's, not the stage's.
stage=$work/stage
mkdir -p "$stage/usr/lib/xymon/server"
"$ROOT/xymon-plugin" install --server xymonapi XYMONHOME=/usr/lib/xymon/server MANDIR=/usr/share/man DESTDIR="$stage" \
	</dev/null >"$work/x.log" 2>&1 || fail "install under DESTDIR failed: $(tail -n 5 "$work/x.log")"
m=$(cat "$stage/usr/lib/xymon/server/ext/xymonapi/MANIFEST")
assert_contains "${TAB}/usr/lib/xymon/server/ext/xymon-plugins-dist/plugins/xymonapi/PLUGIN" "$m" "[S29] under DESTDIR, a path outside is the installed one"
assert_contains "link${TAB}/usr/share/man/man8/xymonapi.8${TAB}/usr/lib/xymon/server/ext/xymonapi/xymonapi.8" "$m" "[S29] and the manual page's link too"
assert_not_contains "$stage" "$m" "[S29] the stage is named nowhere"

# MANIFEST is the command's last step, after every plugin it installs and
# the virtualenv they share (S29): xymonapi-rag installed, xymonapi with it
# as it needs it, a Python that records whether either's MANIFEST is there
# each time the install runs it -- for xymonapi, then for xymonapi-rag,
# looking for modules or making the virtualenv -- never finds one.
real=${XYMONAPI_PYTHON:-python3}
if command -v "$real" >/dev/null 2>&1; then
	home2=$work/server2; server_tree "$home2"
	cat > "$work/py" <<SH
#!/bin/sh
echo "\$*" >> "$work/py.ran"
for m in "$home2/ext/xymonapi/MANIFEST" "$home2/ext/xymonapi-rag/MANIFEST"; do
	[ -e "\$m" ] && echo "\$m: \$*" >> "$work/py.early"
done
exec "$(command -v "$real")" "\$@"
SH
	chmod 755 "$work/py"
	XYMON_PLUGINS_TREES="$home2" PYTHON="$work/py" x install --server xymonapi-rag XYMONHOME="$home2"
	[ -s "$work/py.ran" ] || fail "the install never ran the Python PYTHON names: $(tail -n 5 "$work/x.log")"
	[ -e "$work/py.early" ] && fail "[S29] a MANIFEST was written before the command's end: Python ran after it -- $(head -n 1 "$work/py.early")"
	assert_file_exists "$home2/ext/xymonapi/MANIFEST"
	assert_file_exists "$home2/ext/xymonapi-rag/MANIFEST"
fi

pass "an install and an update write MANIFEST, left as it is when its lines are the same: each file of the plugin's directory with its cksum, the task file and snippets marked admin, and outside it the staged copy, the command and the manual page's link, as installed; no task link"
