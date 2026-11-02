#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Connect this machine to the Xymon API: xymonapi-connect(1). It runs
# xymonapi_client.py beside it, which needs Python 3.9 or later and nothing
# else.

# The Python to run with: XYMONAPI_PYTHON when set; else the virtualenv
# beside the plugins, ../venv, which make venv (venv-client elsewhere) makes
# with their modules; else
# python3 on PATH, which may lack them -- asked about first when a person is
# at the terminal, said on stderr when none is (a task, an AI client).
here=`dirname "$0"`
venv=`cd "$here/.." && pwd`/venv
if [ -n "${XYMONAPI_PYTHON:-}" ]; then
	PYTHON=$XYMONAPI_PYTHON
elif [ -x "$venv/bin/python3" ]; then
	PYTHON=$venv/bin/python3
elif [ -t 0 ] && [ -t 2 ]; then
	PYTHON=python3
	printf 'xymonapi-connect: no virtualenv at %s (make venv, or venv-client, makes one); run with %s, %s? [y/N] ' \
		"$venv" "`command -v python3 || echo python3`" "`python3 -V 2>&1`" >&2
	read -r yn
	case $yn in [yY]*) ;; *) exit 77 ;; esac
else
	PYTHON=python3
	echo "xymonapi-connect: no virtualenv at $venv; running with python3 on PATH" >&2
fi

command -v "$PYTHON" >/dev/null 2>&1 || {
	echo "xymonapi-connect: $PYTHON not found; it needs Python 3.9 or later" >&2
	exit 77
}
"$PYTHON" -c 'import sys; sys.exit(sys.version_info < (3, 9))' || {
	echo "xymonapi-connect: `$PYTHON -V 2>&1` is too old; it needs Python 3.9 or later" >&2
	exit 77
}
exec "$PYTHON" "$here/xymonapi_client.py" connect "$@"
