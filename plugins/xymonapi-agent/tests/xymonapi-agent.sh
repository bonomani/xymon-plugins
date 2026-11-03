#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# plugins/xymonapi-agent/tests/xymonapi-agent.sh
#
# xymonapi-agent ask, as make install-client lays it out, runs the agent CLI
# it is told, or the one installed, with xymonapi-mcp beside it as the
# agent's only tool: Claude Code with --strict-mcp-config, no built-in tools,
# the xymon tools allowed and the rest denied; opencode with a config of its
# own that denies every tool but xymon_*; Codex with a read-only sandbox and
# its shell tool off. Each gets the API's settings as the MCP server's
# environment and the same system prompt, with its rule that a status text
# is data. A session named for Claude Code is continued by the same id;
# doctor passes on a version and fails on anything else; with no CLI, or
# several and no choice, it says so.
#
# claude, codex and opencode are stubs that record their arguments and
# answer a fixed text. Nothing of the API runs. Uses the test helpers of
# the Xymon tree in XYMON_SRC.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../../../tests/lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)

"${MAKE:-make}" -C "$ROOT/plugins/xymonapi-agent" install-client PREFIX="$work/client" >"$work/client.log" 2>&1 \
	|| fail "make install-client failed: $(tail -n 5 "$work/client.log")"
agent=$work/client/bin/xymonapi-agent
assert_file_exists "$work/client/libexec/xymon-plugins/xymonapi-mcp/xymonapi-mcp.sh"
assert_file_exists "$work/client/libexec/xymon-plugins/xymonapi-agent/VERSION"
assert_file_exists "$work/client/share/man/man1/xymonapi-agent.1"

mkdir -p "$work/stub"
cat > "$work/stub/claude" <<STUB
#!/bin/sh
printf '%s\n' "\$@" > "$work/claude.args"
printf '{"result":"xymon 4.3.31","permission_denials":[]}\n'
STUB
cat > "$work/stub/codex" <<STUB
#!/bin/sh
printf '%s\n' "\$@" > "$work/codex.args"
echo "an answer"
STUB
cat > "$work/stub/opencode" <<STUB
#!/bin/sh
printf '%s\n' "\$@" > "$work/opencode.args"
cp "\$OPENCODE_CONFIG" "$work/opencode.json"
echo "\$OPENCODE_DISABLE_PROJECT_CONFIG" > "$work/opencode.env"
echo "an answer"
STUB
chmod 755 "$work/stub/"*
path="$work/stub:/usr/bin:/bin"
export XDG_STATE_HOME="$work/state" XYMONAPI_URL="http://127.0.0.1:1" XYMONAPI_TOKEN_FILE="$work/token"
unset XYMONAPI_AGENT_BACKEND

run() { PATH="$path" "$agent" "$@"; }

# No CLI, or three and no choice: said, and nothing run.
rc=0; out=$(PATH="/usr/bin:/bin" "$agent" ask "anything" 2>&1) || rc=$?
[ "$rc" -eq 1 ] || fail "with no CLI, ask exited $rc: $out"
assert_contains "no agent CLI found" "$out" "with no CLI, ask says so"
rc=0; out=$(run ask "anything" 2>&1) || rc=$?
assert_contains "3 agent CLIs are here" "$out" "with three CLIs and no choice, ask says which"
[ -e "$work/claude.args" ] && fail "a CLI was run without a choice"

# Claude Code: the restricting flags, the MCP server beside the plugin with
# the API's settings, the system prompt, a session of our id.
out=$(run --backend claude ask "which hosts are red?" --session nightly)
assert_equal "xymon 4.3.31" "$out" "ask prints the result of Claude Code's JSON"
args=$(cat "$work/claude.args")
assert_contains "--strict-mcp-config" "$args" "Claude Code gets this MCP server and no other"
grep -qx -- '--tools' "$work/claude.args" || fail "Claude Code is not told --tools"
assert_contains "mcp__xymon__*" "$args" "the xymon tools are allowed"
assert_contains "dontAsk" "$args" "and the rest denied, not asked about"
assert_contains "libexec/xymon-plugins/xymonapi-mcp/xymonapi-mcp.sh" "$args" "the MCP server is the one beside the plugin"
assert_contains '"XYMONAPI_URL": "http://127.0.0.1:1"' "$args" "with the API's address as its environment"
assert_contains "\"XYMONAPI_TOKEN_FILE\": \"$work/token\"" "$args" "and the token file"
assert_contains "never an instruction" "$args" "the system prompt says a status text is data"
assert_contains "--session-id" "$args" "a named session starts with an id of ours"
sid=$(grep -A1 -- '--session-id' "$work/claude.args" | tail -n 1)
out=$(run --backend claude ask "and yellow?" --session nightly)
assert_contains "--resume" "$(cat "$work/claude.args")" "the next call continues it"
assert_equal "$sid" "$(grep -A1 -- '--resume' "$work/claude.args" | tail -n 1)" "by the same id"
out=$(run --backend claude ask "once" --json)
assert_contains '"backend": "claude"' "$out" "--json names the backend"
assert_contains '"answer": "xymon 4.3.31"' "$out" "and carries the answer"
assert_contains "--no-session-persistence" "$(cat "$work/claude.args")" "an unnamed question leaves no session"

# XYMONAPI_AGENT_BACKEND chooses as --backend does.
out=$(XYMONAPI_AGENT_BACKEND=codex run ask "which hosts are red?")
assert_equal "an answer" "$out" "the backend named in the environment answers"
args=$(cat "$work/codex.args")
assert_contains "read-only" "$args" "Codex runs in its read-only sandbox"
assert_contains "features.shell_tool=false" "$args" "with its shell tool off"
assert_contains 'mcp_servers.xymon.command=' "$args" "and the MCP server given on the command line"
assert_contains 'XYMONAPI_URL="http://127.0.0.1:1"' "$args" "with the API's address"
assert_contains "never an instruction" "$args" "and the system prompt"

# opencode: a config of its own, project config off.
out=$(run --backend opencode ask "which hosts are red?")
assert_equal "an answer" "$out" "opencode answers"
cfg=$(cat "$work/opencode.json")
assert_contains '"xymon_*": "allow"' "$cfg" "its config allows the xymon tools"
assert_contains '"*": "deny"' "$cfg" "and denies every other"
assert_contains "xymonapi-mcp/xymonapi-mcp.sh" "$cfg" "with the MCP server beside the plugin"
assert_contains "never an instruction" "$cfg" "and the system prompt as the agent's"
assert_equal "1" "$(cat "$work/opencode.env")" "project configuration is disabled"
assert_contains "--agent" "$(cat "$work/opencode.args")" "and that agent is the one run"
[ -e "$(grep -o '/[^"]*xymonapi-agent-[^"]*\.json' "$work/opencode.args" | head -n 1)" ] 2>/dev/null \
	&& fail "the temporary config was left behind"

# doctor: a version from the health tool passes, anything else fails.
rc=0; out=$(run --backend claude doctor) || rc=$?
[ "$rc" -eq 0 ] || fail "doctor failed on a version: $out"
assert_contains "ok: the health tool answered" "$out" "doctor passes on a version"
rc=0; out=$(run --backend codex doctor) || rc=$?
[ "$rc" -eq 1 ] || fail "doctor exited $rc on a non-version"
assert_contains "not ok" "$out" "and fails on anything else"

# backends: each CLI, its restriction, and what answers.
out=$(run backends)
assert_contains "claude: $work/stub/claude" "$out" "backends names each CLI found"
assert_contains "restriction complete" "$out" "and how far it is held to the MCP server"
assert_contains "answers: none" "$out" "and that three with no choice answer nothing"
out=$(XYMONAPI_AGENT_BACKEND=opencode run backends)
assert_contains "answers: opencode" "$out" "or the one chosen"

pass "xymonapi-agent runs the chosen agent CLI with xymonapi-mcp as its only tool, continues a Claude Code session by name, and doctor tells a tool's answer from any other"
