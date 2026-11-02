#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Start the MCP server for the Xymon API, xymonapi-mcp(1), on stdio. This is
# the command an AI client is configured to run.
# It needs Python 3.10 or later and nothing else: the standard library speaks
# the protocol.
#
# As xymonapi.sh does, exit 77 when it cannot run here -- no Python 3.10 --
# and say why on stderr, which the client logs: stdout carries the protocol
# and nothing else.

PYTHON=${XYMONAPI_PYTHON:-python3}
here=`dirname "$0"`

command -v "$PYTHON" >/dev/null 2>&1 || {
	echo "xymonapi-mcp: $PYTHON not found; it needs Python 3.10 or later" >&2
	exit 77
}
"$PYTHON" -c 'import sys; sys.exit(sys.version_info < (3, 10))' || {
	echo "xymonapi-mcp: `$PYTHON -V 2>&1` is too old; it needs Python 3.10 or later" >&2
	exit 77
}

exec "$PYTHON" "$here/server.py"
