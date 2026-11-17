#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/plugin-broken-python.sh
#
# A Python that is none -- here an empty executable file, as a broken
# install leaves one, which runs as an empty script and exits 0 to every
# check -- is not taken for one. An install given it makes no virtualenv
# and says it found no Python with the modules, instead of "Made venv from
# ... ()" with nothing made; venv-server given it stops and says it made no
# virtualenv. One that has the modules but cannot make a virtualenv, as on
# Debian without python3-venv, does not stop the install: it says so.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
server_tree "$work/server"
mkdir -p "$work/bad"
: > "$work/bad/python3.12"
chmod 755 "$work/bad/python3.12"

rc=0
"$ROOT/xymon-plugin" install --server xymonapi XYMONHOME="$work/server" MANDIR="$work/man" PYTHON="$work/bad/python3.12" \
	</dev/null > "$work/install.log" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "install-server failed: $(tail -n 5 "$work/install.log")"
assert_not_contains "Made $work/server/ext/venv" "$(cat "$work/install.log")" "an empty file is not taken for a Python"
assert_contains "No virtualenv at $work/server/ext/venv" "$(cat "$work/install.log")" "the install says it found none"
[ -e "$work/server/ext/venv" ] && fail "a virtualenv directory was left from the empty file"

rc=0
"$ROOT/xymon-plugin" update --server --venv XYMONHOME="$work/server" MANDIR="$work/man" PYTHON="$work/bad/python3.12" </dev/null > "$work/venv.log" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "update --venv with an empty file for a Python stopped the update: $(cat "$work/venv.log")"
assert_contains "No virtualenv at $work/server/ext/venv" "$(cat "$work/venv.log")" "update --venv says no Python here has the modules, and makes none"
[ -e "$work/server/ext/venv" ] && fail "update --venv left a virtualenv from an empty file"

# A Python with the modules whose venv fails.
printf '#!/bin/sh\ncase "$*" in *"-m venv"*) echo "ensurepip is not available" >&2; exit 1 ;; *executable*) echo "$0" ;; esac\nexit 0\n' > "$work/bad/python3"
chmod 755 "$work/bad/python3"
rc=0
"$ROOT/xymon-plugin" update --server xymonapi XYMONHOME="$work/server" MANDIR="$work/man" PYTHON="$work/bad/python3" \
	</dev/null > "$work/install2.log" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "install-server stopped where a virtualenv could not be made: $(tail -n 3 "$work/install2.log")"
assert_contains "Could not make a virtualenv at $work/server/ext/venv with $work/bad/python3" "$(cat "$work/install2.log")" "a venv that cannot be made is said, and the install goes on"

# A virtualenv whose Python does not run is made anew when its modules are
# asked for, said; and pip failing is said, not a silent exit. A stand-in
# Python, lacking the modules, makes one whose pip fails, so nothing is
# fetched.
real=$(command -v python3)
mkdir -p "$work/stand"
cat > "$work/stand/python3" <<EOF
#!/bin/sh
if [ "\$1" = -m ] && [ "\$2" = venv ]; then mkdir -p "\$3/bin" && cp "\$0" "\$3/bin/python3"; exit; fi
if [ "\$1" = -m ] && [ "\$2" = pip ]; then echo "pip: no network here" >&2; exit 3; fi
case "\$2" in *sys.executable*) echo "\$0"; exit ;; esac
exec "$real" -S "\$@"
EOF
chmod 755 "$work/stand/python3"
rm -rf "$work/server/ext/venv"; mkdir -p "$work/server/ext/venv/bin"
printf '#!/bin/sh\nexit 1\n' > "$work/server/ext/venv/bin/python3"; chmod 755 "$work/server/ext/venv/bin/python3"
: > "$work/server/ext/venv/pyvenv.cfg"
rc=0
XYMONAPI_PYTHON= "$ROOT/xymon-plugin" update --server --venv xymonapi XYMONHOME="$work/server" MANDIR="$work/man" PYTHON="$work/stand/python3" \
	</dev/null > "$work/remake.log" 2>&1 || rc=$?
assert_contains "The virtualenv $work/server/ext/venv has no Python that runs: it is made anew." "$(cat "$work/remake.log")" "[S26] a virtualenv whose Python does not run is made anew, said"
[ "$rc" -ne 0 ] || fail "[S26] pip failing was taken for success: $(cat "$work/remake.log")"
assert_contains "pip could not install the modules of" "$(cat "$work/remake.log")" "[S26] and pip failing is said, not a silent exit"
assert_contains "pip: no network here" "$(cat "$work/remake.log")" "[S26] with what pip said"

# And made from a Python that has the modules, nothing fetched, when one
# is there: as on a first install.
have=${XYMONAPI_PYTHON:-python3}
"$have" -c 'import fastapi, uvicorn, yaml' 2>/dev/null || skip "no Python here with xymonapi's modules"
rm -rf "$work/server/ext/venv"; mkdir -p "$work/server/ext/venv/bin"
printf '#!/bin/sh\nexit 1\n' > "$work/server/ext/venv/bin/python3"; chmod 755 "$work/server/ext/venv/bin/python3"
: > "$work/server/ext/venv/pyvenv.cfg"
rc=0
XYMONAPI_PYTHON= "$ROOT/xymon-plugin" update --server xymonapi XYMONHOME="$work/server" MANDIR="$work/man" PYTHON="$have" \
	</dev/null > "$work/remake2.log" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "[S26] the update failed: $(tail -n 3 "$work/remake2.log")"
assert_contains "has no Python that runs: it is made anew." "$(cat "$work/remake2.log")" "[S26] the broken virtualenv is said"
assert_contains "which has the modules this plugin needs" "$(cat "$work/remake2.log")" "[S26] and made from a Python that has them, nothing fetched"
"$work/server/ext/venv/bin/python3" -c 'import sys' || fail "[S26] the virtualenv made anew has no Python that runs"
assert_not_contains "from PyPI" "$(cat "$work/remake2.log")" "[S26] nothing offered to fetch"

pass "an empty file is not taken for a Python: no virtualenv is claimed, and venv-server says it made none, and an install whose Python cannot make one goes on"
