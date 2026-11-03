#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/xymonapi-python.sh
#
# Which Python a launcher runs with, on either side: XYMONAPI_PYTHON when it
# is set; else the virtualenv beside the installed plugins, venv/; else the
# python3 on PATH, said on stderr when no terminal is there to ask. The same
# order in xymonapi-mcp, xymonapi-rag and xymonapi-connect, which exec the
# Python they chose on their own module.
# How the virtualenv comes to be: an install that needs modules makes it from
# the Python PYTHON= names when that one has them, with --system-site-packages
# and fetching nothing; says which Python make venv would use when none has;
# and says which modules a virtualenv already there lacks. make venv-client
# makes it with PYTHON, and leaves one that is there alone.
#
# The confirmation a launcher asks on a terminal before falling back to PATH
# is not run here: the test has no terminal, and that branch is read. The
# search for a Python when PYTHON= is not given is not run either: what it
# finds depends on the machine.
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

# Two Pythons that are not: one passing every check, as one that has the
# modules would, recording who ran it and with what; one failing the module
# check alone, as one without them would.
fake() { # DIR NAME
	mkdir -p "$1"
	# Never through a link: a venv's python3 is one, to the interpreter
	# itself, and writing through it would replace that interpreter.
	rm -f "$1/python3"
	printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "%s/python.log"\nexit 0\n' "$2" "$work" > "$1/python3"
	chmod 755 "$1/python3"
}
fake "$work/has" has
mkdir -p "$work/lacks"
# Asked which modules are missing, it names them all; asked whether any is,
# it says yes.
printf '#!/bin/sh\ncase "$*" in *"print("*) echo "fastembed numpy" ;; *find_spec*) exit 1 ;; esac\nexit 0\n' > "$work/lacks/python3"
chmod 755 "$work/lacks/python3"

# The three client-side plugins, as make install-client lays them out, on a
# machine whose Python lacks the modules: no virtualenv is made, and the
# install says what make venv would use.
prefix=$work/prefix
lib=$prefix/libexec/xymon-plugins
for p in xymonapi-mcp xymonapi-rag; do
	"$make" -C "$ROOT/plugins/$p" install-client PREFIX="$prefix" PYTHON="$work/lacks/python3" >"$work/install-$p.log" 2>&1 \
		|| fail "make install-client of $p failed: $(tail -n 5 "$work/install-$p.log")"
done
[ -e "$lib/venv" ] && fail "a virtualenv was made with no Python that has the modules"
assert_contains "no Python with the modules this plugin needs (fastembed numpy): make venv (venv-client elsewhere) PYTHON=$work/lacks/python3" \
	"$(cat "$work/install-xymonapi-rag.log")" "installing a plugin that needs modules, with none that has them, names the Python make venv would use"
assert_not_contains "virtualenv" "$(cat "$work/install-xymonapi-mcp.log")" "a plugin that needs no modules says nothing of it"

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

# An install that needs modules, with a Python that has them: the virtualenv
# is made from it, with --system-site-packages, and nothing is fetched.
: > "$work/python.log"
"$make" -C "$ROOT/plugins/xymonapi-rag" install-client PREFIX="$prefix" PYTHON="$work/has/python3" >"$work/install2.log" 2>&1 \
	|| fail "make install-client failed: $(tail -n 5 "$work/install2.log")"
assert_contains "has -m venv --system-site-packages $lib/venv" "$(cat "$work/python.log")" "a Python with the modules makes the virtualenv, sharing its modules"
assert_not_contains "pip" "$(cat "$work/python.log")" "and nothing is installed"
assert_contains "Made $lib/venv from $work/has/python3" "$(cat "$work/install2.log")" "and the install says so"

# A virtualenv there that lacks a module: said, for make venv, and nothing
# fetched; one that has them: nothing said.
mkdir -p "$lib/venv/bin"; cp "$work/lacks/python3" "$lib/venv/bin/python3"
"$make" -C "$ROOT/plugins/xymonapi-rag" install-client PREFIX="$prefix" >"$work/install3.log" 2>&1 \
	|| fail "make install-client failed: $(tail -n 5 "$work/install3.log")"
assert_contains "The virtualenv $lib/venv lacks fastembed numpy" "$(cat "$work/install3.log")" "a virtualenv lacking the modules is said"
fake "$lib/venv/bin" venv
"$make" -C "$ROOT/plugins/xymonapi-rag" install-client PREFIX="$prefix" >"$work/install4.log" 2>&1 \
	|| fail "make install-client failed: $(tail -n 5 "$work/install4.log")"
assert_not_contains "virtualenv" "$(cat "$work/install4.log")" "and one that has them, nothing"

# make venv-client makes the virtualenv with PYTHON, where only plugins
# without modules are installed, so that nothing is fetched; run again, it
# keeps the one there; and the launcher takes it without a word.
prefix2=$work/prefix2
"$make" -C "$ROOT/plugins/xymonapi-mcp" install-client PREFIX="$prefix2" >"$work/install5.log" 2>&1 \
	|| fail "make install-client failed: $(tail -n 5 "$work/install5.log")"
"$make" -C "$ROOT/plugins/xymonapi-mcp" venv-client PREFIX="$prefix2" PYTHON="$real" >"$work/venv.log" 2>&1 \
	|| fail "make venv-client failed: $(tail -n 5 "$work/venv.log")"
[ -x "$prefix2/libexec/xymon-plugins/venv/bin/python3" ] || fail "make venv-client made no venv/bin/python3"
assert_contains "run with $prefix2/libexec/xymon-plugins/venv/bin/python3" "$(cat "$work/venv.log")" "make venv-client says what the plugins now run with"
: > "$prefix2/libexec/xymon-plugins/venv/kept"
"$make" -C "$ROOT" venv-client PREFIX="$prefix2" PYTHON="$real" >"$work/venv2.log" 2>&1 \
	|| fail "make venv-client at the top failed: $(tail -n 5 "$work/venv2.log")"
assert_file_exists "$prefix2/libexec/xymon-plugins/venv/kept"
: > "$work/err"
XYMONAPI_PYTHON="" "$prefix2/bin/xymonapi-mcp" < /dev/null > /dev/null 2> "$work/err" || true
assert_equal "" "$(cat "$work/err")" "and the launcher takes it without a word"

pass "a launcher runs with XYMONAPI_PYTHON, else the virtualenv beside the plugins, else the python3 on PATH and says so; an install makes the virtualenv from a Python that has the modules, fetching nothing, and otherwise says which make venv would use; make venv-client makes it and keeps one that is there"
