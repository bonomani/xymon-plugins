#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-outdated.sh
#
# [S32] outdated says, of each plugin installed, its version against its
# latest published release: up to date, a newer one released with the
# update that takes it, installed newer than any, none released, or a
# VERSION holding no version. It changes nothing; it reads the releases
# with gh when gh answers -- an empty answer being one -- else with curl,
# page after page, 60 at most; when none reaches GitHub, or past 60 pages,
# it says why and ends with 1; otherwise 6 when it said of a plugin that a
# newer release exists, 0 when it said of none. The
# network is never reached: gh and curl are stand-ins first on PATH,
# answering as GitHub's API would, and saying how they were called.

set -euo pipefail
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
prefix=$work/prefix
"$ROOT/xymon-plugin" install --tools xymonapi xymonapi-rag PREFIX="$prefix" >"$work/install.log" 2>&1 \
	|| fail "xymon-plugin install --tools failed: $(tail -n 5 "$work/install.log")"
api=$(sed -n 's/^version: *//p' "$ROOT/plugins/xymonapi/PLUGIN")
rag=$(sed -n 's/^version: *//p' "$ROOT/plugins/xymonapi-rag/PLUGIN")
# A version one above in its last number; one below in its first, which is
# never 0 for xymonapi.
up() { echo "$1" | awk -F. -v OFS=. '{ $NF = $NF + 1; print }'; }
down() { echo "$1" | awk -F. -v OFS=. '{ $1 = $1 - 1; print }'; }

# The stand-ins: gh prints the tags in $work/tags, or fails with GH=fail,
# its arguments kept in $work/gh.args; curl prints the page asked
# ($work/page<N>.json, "[]" when there is none), or fails with CURL=fail.
bin=$work/bin; mkdir -p "$bin"
cat > "$bin/gh" <<'SH'
#!/bin/sh
printf '%s\n' "$*" > "$WORK/gh.args"
[ "${GH:-}" = fail ] && { echo "gh: not logged in" >&2; exit 4; }
cat "$WORK/tags"
SH
cat > "$bin/curl" <<'SH'
#!/bin/sh
[ "${CURL:-}" = fail ] && { echo "curl: (6) Could not resolve host: api.github.com" >&2; exit 6; }
printf '%s\n' "$*" > "$WORK/curl.args"
# What it reads from its standard input, with -K -: its configuration.
case " $* " in *" -K - "*) cat > "$WORK/curl.config" ;; esac
[ "${CURL:-}" = timeout ] && { echo "curl: (28) Operation timed out after 1000 milliseconds" >&2; exit 28; }
# Never more than 70 calls in a run: a loop that does not stop fails, not
# hangs.
echo x >> "$WORK/curl.calls"
[ "$(wc -l < "$WORK/curl.calls")" -le 70 ] || { echo "curl: called more than 70 times" >&2; exit 99; }
for a; do u=$a; done
n=${u##*page=}
if [ -f "$WORK/pageall.json" ] && [ "$n" -le "${PAGES:-999}" ]; then cat "$WORK/pageall.json"
elif [ -f "$WORK/page$n.json" ]; then cat "$WORK/page$n.json"; else echo '[]'; fi
SH
chmod 755 "$bin/gh" "$bin/curl"
export WORK=$work
# tags NAME/vX.Y.Z... -- what gh answers.
tags() { if [ $# -gt 0 ]; then printf '%s\n' "$@"; else :; fi > "$work/tags"; }
# page N NAME/vX.Y.Z... -- GitHub's JSON page N, as curl gets it, pretty.
page() { n=$1; shift; { echo '['; for t in "$@"; do printf '  {\n    "tag_name": "%s",\n    "body": "a, \\"tag_name\\": \\"xymonapi/v9999.0.0\\""\n  },\n' "$t"; done; echo '  {"x": 1}'; echo ']'; } > "$work/page$n.json"; }
run() { RC=0; : > "$work/curl.calls"; PATH="$bin:$PATH" "$ROOT/xymon-plugin" outdated --tools PREFIX="$prefix" >"$work/out" 2>"$work/err" || RC=$?; }
out() { cat "$work/out"; }

# Up to date, the highest not first: 0.
tags "xymonapi/v$(down "$api")" "xymonapi/v$api" "xymonapi-rag/v$rag"
run
assert_equal 0 "$RC" "[S32] all up to date: 0 ($(cat "$work/err"))"
assert_contains "xymonapi: $api installed; up to date" "$(out)" "[S32] up to date, the highest found wherever it is listed"
assert_contains "--hostname github.com" "$(cat "$work/gh.args")" "gh asked of github.com, whatever GH_HOST says"
assert_contains "--paginate" "$(cat "$work/gh.args")" "and every page"

# A newer release: 6, and the update that takes it. NEWER from outside
# changes nothing.
tags "xymonapi/v$api" "xymonapi/v$(up "$api")" "xymonapi-rag/v$rag"
run
assert_equal 6 "$RC" "[S32] a newer release: 6"
assert_contains "xymonapi: $api installed; $(up "$api") released: ./xymon-plugin update --tools xymonapi PREFIX=$prefix, from its release's archive" \
	"$(out)" "[S32] the newer one, and the update that takes it"
assert_contains "xymonapi-rag: $rag installed; up to date" "$(out)" "the others said as they are"
tags "xymonapi/v$api" "xymonapi-rag/v$rag"
RC=0; NEWER=1 PATH="$bin:$PATH" "$ROOT/xymon-plugin" outdated --tools PREFIX="$prefix" >"$work/out" 2>"$work/err" || RC=$?
assert_equal 0 "$RC" "a NEWER in the environment is no newer release"

# Installed newer than any released; none released; no release at all --
# an empty answer is one, not a failure.
tags "xymonapi/v$(down "$api")"
run
assert_equal 0 "$RC" "installed newer, none released: 0"
assert_contains "xymonapi: $api installed; newer than its latest release, $(down "$api")" "$(out)" "installed newer than any release"
assert_contains "xymonapi-rag: $rag installed; no release of it is published" "$(out)" "none released"
tags
CURL=fail run
assert_equal 0 "$RC" "[S32] a repository with no release: 0, gh's empty answer taken, curl not asked ($(cat "$work/err"))"
assert_contains "xymonapi: $api installed; no release of it is published" "$(out)" "and each said unreleased"

# gh failing: curl reads every page, a release's text not taken for a tag.
filler=""; i=0; while [ "$i" -lt 100 ]; do filler="$filler other/v1.0.$i"; i=$((i + 1)); done
# shellcheck disable=SC2086 # a hundred tags, split on purpose
page 1 $filler
page 2 "xymonapi/v$(up "$api")" "xymonapi-rag/v$rag"
GH=fail run
assert_equal 6 "$RC" "[S32] gh failing, curl reads the releases, past the first hundred ($(cat "$work/err"))"
assert_contains "$(up "$api") released" "$(out)" "the newer one, found on the second page"
# A release's text holding a newer one, its quotes escaped: no tag.
page 1 "xymonapi/v$api" "xymonapi-rag/v$rag"
rm -f "$work/page2.json"
GH=fail run
assert_equal 0 "$RC" "a release's text, its quotes escaped, is not taken for a tag: 0 ($(cat "$work/err"))"
assert_contains "xymonapi: $api installed; up to date" "$(out)" "the 9999.0.0 in a release's text not taken"
# Minified JSON, the tag first in the first object.
printf '[{"tag_name":"xymonapi/v%s","draft":false},{"tag_name":"xymonapi-rag/v%s"}]' "$api" "$rag" > "$work/page1.json"
rm -f "$work/page2.json"
GH=fail run
assert_equal 0 "$RC" "minified JSON, read: up to date ($(cat "$work/err"))"
assert_contains "xymonapi: $api installed; up to date" "$(out)" "the tag that opens the first object read"

# More than 60 full pages: said, 1, no partial list.
# shellcheck disable=SC2086 # a hundred tags, split on purpose
page all $filler
GH=fail run
assert_equal 1 "$RC" "past 6000 releases: 1"
assert_contains "more than the 6000 releases outdated reads without gh" "$(cat "$work/err")" "and says so"
assert_equal 61 "$(wc -l < "$work/curl.calls" | tr -d ' ')" "the 61st page read, and found full"
assert_not_contains "installed" "$(out)" "listing nothing"
# 6000 exactly, sixty full pages and an empty one: read, not refused.
PAGES=60 GH=fail run
assert_equal 0 "$RC" "6000 releases exactly, the 61st page empty: read ($(cat "$work/err"))"
rm -f "$work/pageall.json"

# Neither reaching GitHub: said, 1, nothing listed.
GH=fail CURL=fail run
assert_equal 1 "$RC" "[S32] GitHub not reached: 1"
assert_contains "cannot read https://api.github.com/repos/xymon-monitoring/xymon-plugins/releases" "$(cat "$work/err")" "[S32] and says why"
assert_contains "Could not resolve host" "$(cat "$work/err")" "with curl's own words"
assert_not_contains "installed" "$(out)" "listing nothing"

# A VERSION that cannot be compared: said, with why and what fixes it,
# never echoed, and 7 -- over 6, as not every plugin was compared; GitHub
# not reached is 1 over both, read first.
d=$prefix/libexec/xymon-plugins/xymonapi-rag
v=$d/VERSION
cp "$v" "$work/VERSION.kept"
tags "xymonapi/v$api" "xymonapi-rag/v$rag"
printf 'not a version\033[31m\n' > "$v"
run
assert_contains "xymonapi-rag: $v holds no version. To fix: ./xymon-plugin update --tools xymonapi-rag PREFIX=$prefix" "$(out)" "[S32] a VERSION holding no version is said, with its fix"
assert_not_contains "$(printf '\033')" "$(out)" "and what it holds is not echoed"
assert_equal 7 "$RC" "[S32] a VERSION that cannot be compared: 7"
printf 'xymonapi/v%s\n' "$rag" > "$v"
run
assert_contains "xymonapi-rag: $v holds no version" "$(out)" "another plugin's tag is no version of this one"
: > "$v"
run
assert_contains "xymonapi-rag: $v holds no version" "$(out)" "nor is an empty VERSION"
rm "$v"
run
assert_contains "xymonapi-rag: $v is missing: an install that did not end. To fix: ./xymon-plugin install --tools xymonapi-rag PREFIX=$prefix" "$(out)" "[S32] a VERSION missing is said, with its fix: install, as update takes it for no install"
assert_equal 7 "$RC" "a VERSION missing: 7"
ln -s "$work/VERSION.kept" "$v"
run
assert_contains "xymonapi-rag: $v is a link, which no install makes. To fix: ./xymon-plugin update --tools xymonapi-rag PREFIX=$prefix" "$(out)" "[S32] a VERSION that is a link is said"
rm "$v"; ln -s "$work/nowhere" "$v"
run
assert_contains "xymonapi-rag: $v is a link, which no install makes. To fix: ./xymon-plugin install --tools xymonapi-rag PREFIX=$prefix" "$(out)" "[S32] one leading nowhere: install"
rm "$v"; cp "$work/VERSION.kept" "$v"
# Over 6: a newer xymonapi released and this VERSION broken, both said.
tags "xymonapi/v$(up "$api")" "xymonapi-rag/v$rag"
: > "$v"
run
assert_equal 7 "$RC" "[S32] a newer release and a VERSION that cannot be compared: 7"
assert_contains "released: ./xymon-plugin update --tools xymonapi" "$(out)" "both said: the newer release"
assert_contains "xymonapi-rag: $v holds no version" "$(out)" "and the VERSION"
# Under 1: GitHub not reached, nothing read.
GH=fail CURL=fail run
assert_equal 1 "$RC" "[S32] GitHub not reached and a VERSION broken: 1"
assert_not_contains "holds no version" "$(out)" "nothing read"
cp "$work/VERSION.kept" "$v"
tags "xymonapi/v$api" "xymonapi-rag/v$rag"
# On the server, the command names the tree, as it is to be typed.
srv=$work/srv
server_tree "$srv"
"$ROOT/xymon-plugin" install --server xymonapi XYMONHOME="$srv" MANDIR="$work/man" >"$work/srv.log" 2>&1 \
	|| fail "install --server xymonapi failed: $(tail -n 5 "$work/srv.log")"
rm "$srv/ext/xymonapi/VERSION"
RC=0; PATH="$bin:$PATH" "$ROOT/xymon-plugin" outdated --server XYMONHOME="$srv" >"$work/out" 2>"$work/err" || RC=$?
assert_contains "To fix: XYMONHOME=$srv ./xymon-plugin install --server xymonapi" "$(out)" "[S32] on the server, the fix names the tree"
# A plugin named but not installed here: nothing said, as before.
RC=0; PATH="$bin:$PATH" "$ROOT/xymon-plugin" outdated --tools xymonapi-agent PREFIX="$prefix" >"$work/out" 2>"$work/err" || RC=$?
assert_equal 0 "$RC" "a plugin named and not installed: 0"
assert_equal "" "$(out)" "and nothing said of it"
# What this user cannot read: as root nothing is closed, so not there.
if [ "$(id -u)" -ne 0 ]; then
	me=$(id -un)
	chmod a-r "$v"
	run
	assert_contains "xymonapi-rag: cannot read $v: it is mode 200, owned by $me. To fix: chmod 644 '$v'" "$(out)" "[S32] an unreadable VERSION is said, with its owner and fix"
	assert_equal 7 "$RC" "an unreadable VERSION: 7"
	chmod u+r,go+r "$v"
	chmod a-x "$d"
	run
	assert_contains "xymonapi-rag: cannot read $v: $d is mode 644, owned by $me. To fix: chmod 755 '$d'" "$(out)" "[S32] a directory that cannot be entered is said, with its owner and fix"
	assert_equal 7 "$RC" "a directory that cannot be entered: 7"
	assert_equal 1 "$(grep -c "xymonapi-rag: cannot read" "$work/out")" "and said once"
	# And by a copy of the installer that holds no plugins, as the one
	# installed on a server: it lists what it finds, and finds that
	# directory by its name, which a release has.
	mkdir -p "$work/lone"; cp "$ROOT/plugins/xymon-plugin/xymon-plugin" "$work/lone/"
	RC=0; PATH="$bin:$PATH" "$work/lone/xymon-plugin" outdated --tools PREFIX="$prefix" >"$work/out" 2>"$work/err" || RC=$?
	assert_contains "xymonapi-rag: cannot read $v: $d is mode 644" "$(out)" "[S32] a copy holding no plugins finds a directory it cannot enter"
	assert_equal 7 "$RC" "and ends with 7"
	chmod u+x,go+x "$d"
	# Any directory it cannot enter, a release's name or not; but the
	# virtualenv, the installer's own.
	r=$prefix/libexec/xymon-plugins
	mkdir -p "$r/private" "$r/venv"; chmod a-x "$r/private" "$r/venv"
	RC=0; PATH="$bin:$PATH" "$work/lone/xymon-plugin" outdated --tools PREFIX="$prefix" >"$work/out" 2>"$work/err" || RC=$?
	assert_contains "private: cannot read $r/private/VERSION: $r/private is mode 644" "$(out)" "[S32] a directory no release names, closed, is said"
	assert_not_contains "venv" "$(out)" "the virtualenv, closed, is not taken for a plugin"
	chmod u+x,go+x "$r/private" "$r/venv"; rmdir "$r/private" "$r/venv"
	chmod a-x "$d"
	chmod u+x,go+x "$d"
	r=$prefix/libexec/xymon-plugins
	chmod a-x "$r"
	run
	assert_contains "cannot read the plugins in $r: $r is mode 644, owned by $me. To fix: chmod 755 '$r'" "$(out)" "[S32] plugins that cannot be listed are said"
	assert_equal 7 "$RC" "plugins that cannot be listed: 7"
	chmod u+x,go+x "$r"
	# Nor the directory above them.
	chmod a-x "$prefix/libexec"
	run
	assert_contains "cannot read the plugins in $r: $prefix/libexec is mode 644, owned by $me" "$(out)" "[S32] a closed directory above them is said"
	assert_equal 7 "$RC" "a closed directory above them: 7"
	chmod u+x,go+x "$prefix/libexec"
fi
run
assert_equal 0 "$RC" "all as it was: 0 ($(out))"

# Each request curl makes is bounded in time; one that runs out of it is
# GitHub not reached.
tags "xymonapi/v$api"; page 1 "xymonapi/v$api"
GH=fail XYMON_PLUGINS_TIMEOUT=1 run
assert_contains "--max-time 1" "$(cat "$work/curl.args")" "[S32] curl is given its bound"
# XYMON_PLUGINS_NO_GH: gh not asked, curl asked; GH_TOKEN, when set, given
# to curl on its standard input, never on its command line.
: > "$work/gh.args"; rm -f "$work/curl.config"
XYMON_PLUGINS_NO_GH=1 GH_TOKEN=ghp_Abc123 run
assert_equal 0 "$RC" "[S32] with XYMON_PLUGINS_NO_GH, read through curl: 0 ($(cat "$work/err"))"
[ -s "$work/gh.args" ] && fail "[S32] XYMON_PLUGINS_NO_GH, and gh was asked"
assert_contains 'Authorization: Bearer ghp_Abc123' "$(cat "$work/curl.config")" "[S32] GH_TOKEN given to curl on its standard input"
assert_not_contains 'ghp_Abc123' "$(cat "$work/curl.args")" "[S32] and not on its command line"
# One holding characters no token has is not sent, said, and not echoed.
rm -f "$work/curl.config"
XYMON_PLUGINS_NO_GH=1 GH_TOKEN='a"b c' run
assert_contains "GH_TOKEN holds a character no GitHub token has" "$(cat "$work/err")" "[S32] a GH_TOKEN that is no token is said"
assert_not_contains 'a"b c' "$(cat "$work/err") $(out)" "and not echoed"
assert_not_contains 'Authorization' "$(cat "$work/curl.config" 2>/dev/null)" "nor sent"
CURL=timeout GH=fail run
assert_equal 1 "$RC" "[S32] a curl that runs out of time is GitHub not reached: 1"
assert_contains "Operation timed out" "$(cat "$work/err")" "and says so"
rm -f "$work/page1.json"

# It changes nothing: the install is as it was.
"$ROOT/xymon-plugin" verify --tools PREFIX="$prefix" >"$work/verify.log" 2>&1 || fail "[S32] verify after outdated: $(tail -n 5 "$work/verify.log")"

pass "[S32] outdated says each plugin's version against its latest release -- up to date (0), newer released (6) with the update, newer than any, none released; a VERSION that cannot be compared (7) with why and its fix -- through gh asked of github.com, else curl page after page, each request bounded; 1 when GitHub is not reached; changing nothing"
