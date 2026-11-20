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
# Never more than 70 calls in a run: a loop that does not stop fails, not
# hangs.
echo x >> "$WORK/curl.calls"
[ "$(wc -l < "$WORK/curl.calls")" -le 70 ] || { echo "curl: called more than 70 times" >&2; exit 99; }
for a; do u=$a; done
n=${u##*page=}
if [ -f "$WORK/pageall.json" ]; then cat "$WORK/pageall.json"
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
assert_contains "xymonapi: $api installed; $(up "$api") released: ./xymon-plugin update --tools xymonapi, from its release's archive" \
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
assert_equal 60 "$(wc -l < "$work/curl.calls" | tr -d ' ')" "after 60 pages read"
assert_not_contains "installed" "$(out)" "listing nothing"
rm -f "$work/pageall.json"

# Neither reaching GitHub: said, 1, nothing listed.
GH=fail CURL=fail run
assert_equal 1 "$RC" "[S32] GitHub not reached: 1"
assert_contains "cannot read https://api.github.com/repos/xymon-monitoring/xymon-plugins/releases" "$(cat "$work/err")" "[S32] and says why"
assert_contains "Could not resolve host" "$(cat "$work/err")" "with curl's own words"
assert_not_contains "installed" "$(out)" "listing nothing"

# A VERSION changed by hand: said, not compared.
v=$prefix/libexec/xymon-plugins/xymonapi-rag/VERSION
cp "$v" "$work/VERSION.kept"
printf 'not a version\033[31m\n' > "$v"
tags "xymonapi/v$api" "xymonapi-rag/v$rag"
run
assert_contains "xymonapi-rag: its VERSION holds no version: ./xymon-plugin verify --tools says more" "$(out)" "a VERSION holding no version is said"
assert_not_contains "$(printf '\033')" "$(out)" "and what it holds is not echoed"
assert_equal 0 "$RC" "a VERSION holding no version: 0"
printf 'xymonapi/v%s\n' "$rag" > "$v"
run
assert_contains "xymonapi-rag: its VERSION holds no version" "$(out)" "another plugin's tag is no version of this one"
cp "$work/VERSION.kept" "$v"

# It changes nothing: the install is as it was.
"$ROOT/xymon-plugin" verify --tools PREFIX="$prefix" >"$work/verify.log" 2>&1 || fail "[S32] verify after outdated: $(tail -n 5 "$work/verify.log")"

pass "[S32] outdated says each plugin's version against its latest release -- up to date (0), newer released (6) with the update, newer than any, none released, a VERSION holding none -- through gh asked of github.com, else curl page after page; 1 when GitHub is not reached; changing nothing"
