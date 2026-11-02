#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# plugins/xymonapi-mcp/tests/xymonapi-mcp-marketplace.sh
#
# A Claude Code marketplace installs this plugin's directory alone, so the
# API's client, xymonapi's, is in it as a symbolic link to
# ../xymonapi/xymonapi_client.py, which the marketplace copies as a file:
# the link is there, points at that file, and reads the same.
#
# Uses the test helpers of the Xymon tree in XYMON_SRC.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../../../tests/lib/xymonapi.sh"

ROOT=$(find_root)
link=$ROOT/plugins/xymonapi-mcp/xymonapi_client.py

[ -L "$link" ] || fail "plugins/xymonapi-mcp/xymonapi_client.py is not a symbolic link"
assert_equal "../xymonapi/xymonapi_client.py" "$(readlink "$link")" "it points at xymonapi's client"
cmp -s "$link" "$ROOT/plugins/xymonapi/xymonapi_client.py" || fail "the link does not read as xymonapi's client"

pass "xymonapi-mcp carries xymonapi's client as a link a marketplace copies"
