#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Connect this machine to the Xymon API: xymonapi-connect(1). It runs
# xymonapi_client.py beside it, which needs Python 3.9 or later and nothing
# else.

PYTHON=${XYMONAPI_PYTHON:-python3}
here=`dirname "$0"`

command -v "$PYTHON" >/dev/null 2>&1 || {
	echo "xymonapi-connect: $PYTHON not found; it needs Python 3.9 or later" >&2
	exit 77
}
"$PYTHON" -c 'import sys; sys.exit(sys.version_info < (3, 9))' || {
	echo "xymonapi-connect: `$PYTHON -V 2>&1` is too old; it needs Python 3.9 or later" >&2
	exit 77
}
exec "$PYTHON" "$here/xymonapi_client.py" connect "$@"
