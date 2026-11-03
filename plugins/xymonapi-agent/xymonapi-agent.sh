#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Run xymonapi-agent(1): ask an AI agent CLI a question about Xymon, with
# xymonapi-mcp, beside this plugin, as its only tool.
#
# It needs Python 3.9 or later and nothing else of its own; the agent CLI is
# the user's. As the other launchers do, exit 77 when it cannot run here and
# say why on stderr.

here=`dirname "$0"`
venv=`cd "$here/.." && pwd`/venv
if [ -n "${XYMONAPI_PYTHON:-}" ]; then
	PYTHON=$XYMONAPI_PYTHON
elif [ -x "$venv/bin/python3" ]; then
	PYTHON=$venv/bin/python3
else
	PYTHON=python3
fi

command -v "$PYTHON" >/dev/null 2>&1 || {
	echo "xymonapi-agent: $PYTHON not found; it needs Python 3.9 or later" >&2
	exit 77
}
"$PYTHON" -c 'import sys; sys.exit(sys.version_info < (3, 9))' || {
	echo "xymonapi-agent: `$PYTHON -V 2>&1` is too old; it needs Python 3.9 or later" >&2
	exit 77
}
exec "$PYTHON" "$here/xymonagent.py" "$@"
