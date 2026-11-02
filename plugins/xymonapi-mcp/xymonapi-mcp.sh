#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Start the MCP server for the Xymon API, xymonapi-mcp(1), on stdio. This is
# the command an AI client is configured to run.
#
# xymonapi-mcp register URL [NAME] instead registers it with Claude Code and
# Codex, after xymonapi-connect(1), beside it, has connected this machine to
# the API at URL.
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

[ "${1:-}" = register ] || exec "$PYTHON" "$here/server.py"

# register URL [NAME]
[ $# -ge 2 ] && [ $# -le 3 ] || {
	echo "usage: xymonapi-mcp register URL [NAME]" >&2
	exit 2
}
url=$2
name=${3:-xymon}
# The connection first: a token kept while it works, else a password asked
# once. Its settings, shell-quoted, on stdout; its questions on stderr.
connect=$here/../xymonapi/xymonapi-connect.sh
settings=`"$connect" "$url" "$name"` || exit $?
XYMONAPI_TOKEN_FILE=""
XYMONAPI_CA=""
eval "$settings"
cmd=`cd "$here" && pwd`/xymonapi-mcp.sh

# A virtualenv an earlier setup made, for the mcp module this server no
# longer needs.
venv=`cd "$here/.." && pwd`/venv
if [ -d "$venv" ]; then
	rm -rf "$venv"
	echo "removed $venv: the MCP server needs no Python module beyond the standard library"
fi

# The settings an AI client gives the server, as -e or --env options.
opts() {
	printf '%s\n' "$1" "XYMONAPI_URL=$XYMONAPI_URL"
	[ -n "$XYMONAPI_TOKEN_FILE" ] && printf '%s\n' "$1" "XYMONAPI_TOKEN_FILE=$XYMONAPI_TOKEN_FILE"
	[ -n "$XYMONAPI_CA" ] && printf '%s\n' "$1" "XYMONAPI_CA=$XYMONAPI_CA"
	[ -n "${XYMONAPI_PYTHON:-}" ] && printf '%s\n' "$1" "XYMONAPI_PYTHON=$XYMONAPI_PYTHON"
	return 0
}
# One option per line, read back into the arguments: a path with a space
# stays one word.
register() {
	client=$1 flag=$2; shift 2
	while IFS= read -r o; do set -- "$@" "$o"; done <<EOF
`opts "$flag"`
EOF
	if command -v "$client" >/dev/null 2>&1; then
		"$@" -- "$cmd" || exit 1
		echo "registered $name with $client"
	else
		echo "$client is not here; to register $name with it later:"
		printf ' %s' "$@" -- "$cmd"; echo
	fi
}
claude mcp remove --scope user "$name" >/dev/null 2>&1 || true
register claude -e claude mcp add --scope user "$name"
codex mcp remove "$name" >/dev/null 2>&1 || true
register codex --env codex mcp add "$name"
