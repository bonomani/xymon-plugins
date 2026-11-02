#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/xymonapi-python.sh
#
# Which Python a launcher runs with, on either side: XYMONAPI_PYTHON when it
# is set; else the virtualenv beside the installed plugins, venv/, which make
# venv-client makes; else the python3 on PATH, said on stderr when no
# terminal is there to ask. The same order in xymonapi-mcp, xymonapi-rag and
# xymonapi-connect, which exec the Python they chose on their own module.
# make venv-client makes the virtualenv with PYTHON, and leaves one that is
# there alone.
#
# The confirmation a launcher asks on a terminal before falling back to PATH
# is not run here: the test has no terminal, and that branch is read.
# Needs make and a Python 3.9 or later with the venv module in
# XYMONAPI_PYTHON, or python3.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
make=${MAKE:-make}
real=${XYMONAPI_PYTHON:-python3}
command -v "$real" >/dev/null 2>&1 || skip "$real is not installed"

# The three client-side plugins, as make install-client lays them out.
prefix=$work/prefix
for p in xymonapi-mcp xymonapi-rag; do
	"$make" -C "$ROOT/plugins/$p" install-client PREFIX="$prefix" >"$work/install.log" 2>&1 \
		|| fail "make install-client of $p failed: $(tail -n 5 "$work/install.log")"
done
lib=$prefix/libexec/xymon-plugins

# A python3 that records who ran it and with what, and passes for 3.9: the
# version check is a -c script that exits 0.
fake() {
	mkdir -p "$1"
	printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "%s/python.log"\nexit 0\n' "$2" "$work" > "$1/python3"
	chmod 755 "$1/python3"
}
fake "$lib/venv/bin" venv
fake "$work/path" path
fake "$work/named" named
run() { # LAUNCHER ARGS... -- stdin is no terminal, so nothing is asked.
	# XYMONAPI_PYTHON is PY, or unset: the suite's own setting must not
	# decide the test.
	: > "$work/python.log"; : > "$work/err"
	[ -x "$prefix/bin/$1" ] || fail "no launcher $prefix/bin/$1"
	XYMONAPI_PYTHON="${PY:-}" PATH="$work/path:$PATH" "$prefix/bin/$@" < /dev/null > /dev/null 2> "$work/err" || true
}

# The virtualenv beside the plugins, before the python3 on PATH, silently.
for cmd in "xymonapi-mcp" "xymonapi-rag search x" "xymonapi-connect http://127.0.0.1:1"; do
	# shellcheck disable=SC2086 # the command's words are meant to split
	run $cmd
	case $cmd in
		xymonapi-mcp) module=xymonapi-mcp/server.py ;;
		xymonapi-rag*) module=xymonapi-rag/xymonrag.py ;;
		*) module=xymonapi/xymonapi_client.py ;;
	esac
	assert_contains "venv $lib/$module" "$(cat "$work/python.log")" "${cmd%% *} runs its module with the virtualenv beside the plugins"
	assert_not_contains "path " "$(cat "$work/python.log")" "and does not consult the python3 on PATH"
	assert_equal "" "$(cat "$work/err")" "with nothing said"
done

# XYMONAPI_PYTHON names another: that one, and the virtualenv is left out.
PY="$work/named/python3" run xymonapi-mcp
assert_contains "named $lib/xymonapi-mcp/server.py" "$(cat "$work/python.log")" "XYMONAPI_PYTHON wins over the virtualenv"
assert_not_contains "venv " "$(cat "$work/python.log")" "which is not run"

# No virtualenv, no terminal: the python3 on PATH, and a line on stderr.
rm -rf "$lib/venv"
run xymonapi-mcp
assert_contains "path $lib/xymonapi-mcp/server.py" "$(cat "$work/python.log")" "without a virtualenv the python3 on PATH runs it"
assert_contains "xymonapi-mcp: no virtualenv at $lib/venv; running with python3 on PATH" "$(cat "$work/err")" "and stderr says so"

# make venv-client makes the virtualenv with PYTHON, where only plugins
# without modules are installed, so that nothing is fetched; run again, it
# keeps the one there.
"$make" -C "$ROOT/plugins/xymonapi-mcp" venv-client PREFIX="$prefix" PYTHON="$real" >"$work/venv.log" 2>&1 \
	|| fail "make venv-client failed: $(tail -n 5 "$work/venv.log")"
[ -x "$lib/venv/bin/python3" ] || fail "make venv-client made no $lib/venv/bin/python3"
assert_contains "run with $lib/venv/bin/python3" "$(cat "$work/venv.log")" "make venv-client says what the plugins now run with"
: > "$lib/venv/kept"
"$make" -C "$ROOT" venv-client PREFIX="$prefix" PYTHON="$real" >"$work/venv2.log" 2>&1 \
	|| fail "make venv-client at the top failed: $(tail -n 5 "$work/venv2.log")"
assert_file_exists "$lib/venv/kept"
run xymonapi-mcp
assert_equal "" "$(cat "$work/err")" "and the launcher takes it without a word"

# The hint after an install that needs modules, when there is no virtualenv.
rm -rf "$lib/venv"
"$make" -C "$ROOT/plugins/xymonapi-rag" install-client PREFIX="$prefix" >"$work/install2.log" 2>&1 \
	|| fail "make install-client failed: $(tail -n 5 "$work/install2.log")"
assert_contains "No virtualenv at $lib/venv: make venv" "$(cat "$work/install2.log")" "installing a plugin that needs modules says how to make the virtualenv"

pass "a launcher runs with XYMONAPI_PYTHON, else the virtualenv beside the plugins, else the python3 on PATH and says so; make venv-client makes that virtualenv and keeps one that is there"
