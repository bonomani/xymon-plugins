#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/xymonapi-install.sh
#
# ./install.sh install with XYMONHOME set puts
# the API, with its client, in $XYMONHOME/ext/xymonapi/,
# the search beside it, its manual page in man8/, and its task in
# $XYMONHOME/etc/tasks.d/xymonapi -- disabled, with ENVFILE naming that
# server's xymonserver.cfg. An install over one where the admin enabled the
# task leaves that file alone: putting DISABLED back would stop the API at
# the next upgrade, with nothing to say why. Without XYMONHOME it installs
# nothing and says so. The Apache snippet goes to $XYMONHOME/etc, kept too
# once there. ./install.sh install puts the MCP server and the search commands
# under PREFIX, with two commands in bin that run them from there, and
# xymonapi's client alone beside them, not the API. Installing
# again replaces each plugin's directory, so a file no longer shipped is
# gone, and says to restart the API; the client's virtualenv beside the
# plugins is kept. A plugin installed alone brings the plugins it needs
# beside it: xymonapi-rag on the server, the API with its client. The
# removal refuses a plugin another installed one needs, removes each
# plugin's files, manual page and task, and keeps the web server snippets
# and the data, saying so; on a laptop it says what to undo by hand.
#
# Installed into a scratch directory. No Python is needed: the API is copied,
# not run. Uses the test helpers of the Xymon tree in XYMON_SRC.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)
home=$work/server
server_tree "$home"

# The profile: unsaid, it follows the role detected from the tree XYMONHOME
# names, said in the first line; a monitored host -- etc/xymonclient.cfg, no
# server file -- is refused, since no plugin ships a client profile yet;
# said, server needs XYMONHOME; tools is your own machine wherever you are,
# a server machine included; two profiles are refused.
mkdir -p "$work/host/etc" "$work/host/bin" && : > "$work/host/etc/xymonclient.cfg" && : > "$work/host/bin/xymonclient.sh"
rc=0
"$ROOT/install.sh" install xymonapi XYMONHOME="$work/host" MANDIR="$work/man" >"$work/host.log" 2>&1 || rc=$?
assert_equal "1" "$rc" "install.sh install on a monitored host is refused"
assert_contains "This machine is a monitored host (etc/xymonclient.cfg, bin/xymonclient.sh under $work/host). No plugin ships a client profile yet" "$(cat "$work/host.log")" "saying why"
[ -e "$work/host/ext" ] && fail "a monitored host got the server profile"
# Half a tree is an error, none at all is not Xymon's: neither is guessed at.
mkdir -p "$work/half/etc" && : > "$work/half/etc/xymonserver.cfg"
rc=0
"$ROOT/install.sh" install xymonapi XYMONHOME="$work/half" MANDIR="$work/man" >"$work/half.log" 2>&1 || rc=$?
assert_equal "1" "$rc" "a tree with one of the server's two marks is refused"
assert_contains "$work/half has etc/xymonserver.cfg but not bin/xymond: half a Xymon server tree" "$(cat "$work/half.log")" "naming the mark that is missing"
# The two marks are two pieces of evidence, etc/ and bin/: a tree with every
# configuration file of a server but no program is still half a tree.
mkdir -p "$work/etconly/etc" && : > "$work/etconly/etc/xymonserver.cfg" && : > "$work/etconly/etc/tasks.cfg" && : > "$work/etconly/etc/hosts.cfg"
rc=0
"$ROOT/install.sh" install xymonapi XYMONHOME="$work/etconly" MANDIR="$work/man" >"$work/etconly.log" 2>&1 || rc=$?
assert_equal "1" "$rc" "a tree with only etc/ copied in is refused"
assert_contains "has etc/xymonserver.cfg but not bin/xymond" "$(cat "$work/etconly.log")" "since a second file under etc/ is not a second mark"
mkdir -p "$work/none"
rc=0
"$ROOT/install.sh" install xymonapi XYMONHOME="$work/none" MANDIR="$work/man" >"$work/none.log" 2>&1 || rc=$?
assert_equal "1" "$rc" "a tree with no mark at all is refused"
assert_contains "is neither a Xymon server (etc/xymonserver.cfg, bin/xymond) nor a monitored host (etc/xymonclient.cfg, bin/xymonclient.sh): say the profile" "$(cat "$work/none.log")" "and says what would tell"
"$ROOT/install.sh" install xymonapi server XYMONHOME="$work/none" MANDIR="$work/man" >"$work/none2.log" 2>&1 \
	|| fail "the server profile said on a tree with no mark failed: $(tail -n 5 "$work/none2.log")"
assert_contains "No Xymon role detected under $work/none; the profile is as said. The server profile:" "$(cat "$work/none2.log")" "said, the profile is taken as said, for packaging"
assert_file_exists "$work/none/ext/xymonapi/VERSION"
rc=0
"$ROOT/install.sh" install xymonapi server >"$work/nohome.log" 2>&1 || rc=$?
assert_equal "1" "$rc" "server said without XYMONHOME is refused"
assert_contains "the server profile needs XYMONHOME" "$(cat "$work/nohome.log")" "naming what is missing"
# The long form, PLUGIN-PROFILE, pins one plugin to one profile whatever the
# machine, and brings what it needs in that profile; with every plugin
# pinned no role is needed, so it works on a tree that is nobody's. Nothing
# named does nothing, and says how to name.
"$ROOT/install.sh" install xymonapi-mcp-tools XYMONHOME="$work/srv" PREFIX="$work/long" >"$work/long.log" 2>&1 \
	|| fail "install.sh install xymonapi-mcp-tools failed: $(tail -n 5 "$work/long.log")"
assert_contains "The tools profile:" "$(cat "$work/long.log")" "the long form names the profile"
assert_file_exists "$work/long/libexec/xymon-plugins/xymonapi-mcp/VERSION"
assert_file_exists "$work/long/libexec/xymon-plugins/xymonapi/VERSION"
[ -e "$work/srv/ext/xymonapi-mcp" ] && fail "a plugin pinned to tools on a server machine got the server profile"
"$ROOT/install.sh" install xymonapi-mcp-tools XYMONHOME="$work/host" PREFIX="$work/hostme" >"$work/hostme.log" 2>&1 \
	|| fail "install.sh install xymonapi-mcp-tools on a monitored host failed: $(tail -n 5 "$work/hostme.log")"
assert_contains "This machine is a monitored host (etc/xymonclient.cfg, bin/xymonclient.sh under $work/host). The tools profile:" "$(cat "$work/hostme.log")" "the tools profile pinned installs on a monitored host, which alone is refused"
assert_file_exists "$work/hostme/bin/xymonapi-mcp"
mkdir -p "$work/nobody"
"$ROOT/install.sh" install xymonapi-server XYMONHOME="$work/nobody" MANDIR="$work/man" >"$work/nobody.log" 2>&1 \
	|| fail "install.sh install xymonapi-server on a tree with no mark failed: $(tail -n 5 "$work/nobody.log")"
assert_file_exists "$work/nobody/ext/xymonapi/VERSION"
rc=0
"$ROOT/install.sh" install PREFIX="$work/nothing" >"$work/nothing.log" 2>&1 || rc=$?
assert_equal "1" "$rc" "install with nothing named does nothing"
assert_contains "nothing named, nothing done: name the plugins" "$(cat "$work/nothing.log")" "and says how to name them"
[ -e "$work/nothing" ] && fail "install with nothing named installed something"
rc=0
"$ROOT/install.sh" install xymonapi server tools PREFIX="$work/two" >"$work/two.log" 2>&1 || rc=$?
assert_equal "1" "$rc" "two profiles are refused"
assert_contains "two profiles given: server and tools" "$(cat "$work/two.log")" "naming both"
[ -e "$work/two" ] && fail "two profiles installed something"
server_tree "$work/srv"
"$ROOT/install.sh" install xymonapi tools XYMONHOME="$work/srv" PREFIX="$work/me" >"$work/me.log" 2>&1 \
	|| fail "install.sh install tools on a server machine failed: $(tail -n 5 "$work/me.log")"
assert_contains "This machine is the Xymon server (etc/xymonserver.cfg, bin/xymond under $work/srv). The tools profile: the plugins' commands, under $work/me." "$(cat "$work/me.log")" "tools said on a server machine installs your own commands"
assert_file_exists "$work/me/libexec/xymon-plugins/xymonapi/VERSION"
[ -e "$work/srv/ext" ] && fail "the tools profile on a server machine touched the server's tree"

# A plugin declares its profiles, and the script learns them from the
# PLUGIN files: in a copy of the repository, a plugin ships a fourth,
# client4server, under ext, brought by the server role. Unsaid, the server
# role installs the server profiles and that one in one run, said first;
# said, the profile installs alone; on your own machine the plugin has
# nothing to install, and is refused by name when asked for.
repo=$work/repo
mkdir -p "$repo/plugins"
cp "$ROOT/install.sh" "$ROOT/ROLES" "$ROOT/CAPABILITIES" "$ROOT/LICENSE" "$repo/"
cp -R "$ROOT/plugins/xymonapi" "$repo/plugins/xymonapi"
mkdir -p "$repo/plugins/fourth"
printf 'hello\n' > "$repo/plugins/fourth/fourth.sh"
cat > "$repo/plugins/fourth/PLUGIN" <<'PLUGIN'
name: fourth
version: 0.0.1
summary: a plugin with a profile of its own
client4server-root: ext
client4server-roles: server
client4server-files: fourth.sh
client4server-installed: Installed the client4server profile of fourth.
client4server-removed: Removed fourth.
with_ai_tools-root: prefix
with_ai_tools-roles: tools
with_ai_tools-files: fourth.sh
with_ai_tools-removed: Removed fourth's with_ai_tools profile.
executable: fourth.sh
PLUGIN
four=$work/four
server_tree "$four"
"$repo/install.sh" install xymonapi fourth XYMONHOME="$four" MANDIR="$work/man4" >"$work/four.log" 2>&1 \
	|| fail "install.sh install with a fourth profile declared failed: $(tail -n 5 "$work/four.log")"
assert_contains "The profiles, client4server (under $four/ext), server (the plugins' tasks and the API, under $four/ext)." "$(cat "$work/four.log")" "the server role brings the declared profile, said first"
assert_file_exists "$four/ext/fourth/fourth.sh"
assert_file_exists "$four/ext/xymonapi/app.py"
[ -x "$four/ext/fourth/fourth.sh" ] || fail "the declared profile's executable is not executable"
assert_contains "Installed the client4server profile of fourth." "$(cat "$work/four.log")" "and its installed message is printed"
four2=$work/four2
server_tree "$four2"
"$repo/install.sh" install fourth client4server XYMONHOME="$four2" MANDIR="$work/man4" >"$work/four2.log" 2>&1 \
	|| fail "install.sh install fourth client4server failed: $(tail -n 5 "$work/four2.log")"
assert_file_exists "$four2/ext/fourth/fourth.sh"
[ -e "$four2/ext/xymonapi" ] && fail "the profile said alone installed another"
# A profile name may hold underscores and digits; the dash joins it to the
# plugin's name, so it holds none. Pinned long, it installs under its root.
"$repo/install.sh" install fourth-with_ai_tools PREFIX="$work/four3" >"$work/four3.log" 2>&1 \
	|| fail "install.sh install fourth-with_ai_tools failed: $(tail -n 5 "$work/four3.log")"
assert_contains "The with_ai_tools profile:" "$(cat "$work/four3.log")" "a profile with underscores in its name is a profile"
assert_file_exists "$work/four3/libexec/xymon-plugins/fourth/fourth.sh"
rc=0
"$repo/install.sh" install fourth PREFIX="$work/four4" >"$work/four4.log" 2>&1 || rc=$?
assert_equal "0" "$rc" "the tools role brings with_ai_tools, which names it in its roles"
assert_file_exists "$work/four4/libexec/xymon-plugins/fourth/fourth.sh"
"$repo/install.sh" remove fourth XYMONHOME="$four" MANDIR="$work/man4" >"$work/four-rm.log" 2>&1 \
	|| fail "install.sh remove fourth failed: $(tail -n 5 "$work/four-rm.log")"
[ -e "$four/ext/fourth" ] && fail "remove left the declared profile's directory"
assert_contains "Removed fourth." "$(cat "$work/four-rm.log")" "and says so"

# Capabilities and roles. roles prints each capability with its evidence
# and each role of ROLES with yes or what it lacks; a capability no mark
# shows is declared and forgotten; a plugin whose profiles are for roles the
# machine lacks is not installed by the short form, and says what is
# lacking; the bare profile word installs it all the same.
PATH=/usr/bin:/bin XDG_CONFIG_HOME="$work/cfg" "$ROOT/install.sh" roles >"$work/roles.log" 2>&1 \
	|| fail "install.sh roles failed: $(tail -n 5 "$work/roles.log")"
assert_contains "own_account    no XYMONHOME in the environment" "$(cat "$work/roles.log")" "roles prints the capability with its evidence"
assert_contains "tools          yes: own_account" "$(cat "$work/roles.log")" "and a role held"
assert_contains "ai_workstation no: lacks ai_cli" "$(cat "$work/roles.log")" "and what a role lacks"
# The probes are the lines of CAPABILITIES: a variable set is the llm's
# evidence, a program on PATH the ai_cli's, with its path.
PATH=/usr/bin:/bin XDG_CONFIG_HOME="$work/cfg" OPENAI_BASE_URL=https://llm.example.ch/v1 "$ROOT/install.sh" roles >"$work/roles-env.log" 2>&1 \
	|| fail "install.sh roles with OPENAI_BASE_URL failed: $(tail -n 5 "$work/roles-env.log")"
assert_contains "llm            OPENAI_BASE_URL=https://llm.example.ch/v1" "$(cat "$work/roles-env.log")" "an env probe of CAPABILITIES gives the capability its evidence"
ai_cli_on_path "$work/ai"
PATH="$work/ai:/usr/bin:/bin" XDG_CONFIG_HOME="$work/cfg" "$ROOT/install.sh" roles >"$work/roles-ai.log" 2>&1 \
	|| fail "install.sh roles with an AI CLI failed: $(tail -n 5 "$work/roles-ai.log")"
assert_contains "ai_cli         claude at $work/ai/claude" "$(cat "$work/roles-ai.log")" "a command probe names the program and its path"
PATH=/usr/bin:/bin XDG_CONFIG_HOME="$work/cfg" "$ROOT/install.sh" capability ai_cli >"$work/cap.log" 2>&1 \
	|| fail "install.sh capability ai_cli failed: $(tail -n 5 "$work/cap.log")"
assert_contains "Declared ai_cli, set by you on" "$(cat "$work/cap.log")" "a capability is declared"
assert_contains "ai_workstation yes: own_account, ai_cli" "$(cat "$work/cap.log")" "and the role it completes holds"
assert_file_exists "$work/cfg/xymon-plugins/capabilities"
PATH=/usr/bin:/bin XDG_CONFIG_HOME="$work/cfg" "$ROOT/install.sh" capability ai_cli off >"$work/capoff.log" 2>&1 \
	|| fail "install.sh capability ai_cli off failed: $(tail -n 5 "$work/capoff.log")"
assert_contains "ai_workstation no: lacks ai_cli" "$(cat "$work/capoff.log")" "and forgotten"
rc=0
PATH=/usr/bin:/bin XDG_CONFIG_HOME="$work/cfg" "$ROOT/install.sh" install xymonapi-agent PREFIX="$work/noai" >"$work/noai.log" 2>&1 || rc=$?
assert_equal "1" "$rc" "the agent is not installed where no AI CLI is"
assert_contains "xymonapi-agent: nothing to install for the roles this machine holds (tools): its server profile is for ai_server, which this machine lacks (xymon_server, ai_cli, llm); its tools profile is for ai_workstation, which this machine lacks (ai_cli). Pin a profile, as xymonapi-agent-server, to install it anyway." "$(cat "$work/noai.log")" "saying which role each profile is for and what is lacking"
[ -e "$work/noai" ] && fail "the agent was installed where no AI CLI is"
# A Xymon server on the machine is a capability of the machine, found in
# the trees it has whatever the account's environment: in your own shell
# the server role holds, its profile is the Xymon user's and is said and
# left to that user, and your own commands install.
server_tree "$work/machine"
PATH=/usr/bin:/bin XDG_CONFIG_HOME="$work/cfg" XYMON_PLUGINS_TREES="$work/machine" "$ROOT/install.sh" install xymonapi PREFIX="$work/mine" >"$work/mine.log" 2>&1 \
	|| fail "install.sh install xymonapi as yourself on a server machine failed: $(tail -n 5 "$work/mine.log")"
assert_contains "This machine is the Xymon server (etc/xymonserver.cfg, bin/xymond under $work/machine). The profiles, server" "$(cat "$work/mine.log")" "the server is found on the machine; its tree is yours, so its profile is too"
assert_contains "XYMONHOME=$work/machine taken from the server, which is yours ($work/machine is owned by $(id -un), which you are)." "$(cat "$work/mine.log")" "and XYMONHOME is taken from the tree, saying why"
assert_file_exists "$work/mine/bin/xymonapi-connect"
assert_file_exists "$work/machine/ext/xymonapi/VERSION"
assert_contains "xymon_user     $work/machine is owned by $(id -un), which you are" "$(PATH=/usr/bin:/bin XDG_CONFIG_HOME="$work/cfg" XYMON_PLUGINS_TREES="$work/machine" "$ROOT/install.sh" roles 2>&1)" "roles shows whose server it is"
ai_cli_on_path "$work/ai"
PATH="$work/ai:/usr/bin:/bin" XDG_CONFIG_HOME="$work/cfg" "$ROOT/install.sh" install xymonapi-agent PREFIX="$work/ai-me" >"$work/ai-me.log" 2>&1 \
	|| fail "install.sh install xymonapi-agent with an AI CLI failed: $(tail -n 5 "$work/ai-me.log")"
assert_contains "Roles: tools, ai_workstation" "$(cat "$work/ai-me.log")" "with an AI CLI the machine holds ai_workstation"
assert_file_exists "$work/ai-me/bin/xymonapi-agent"

# Under a umask that would leave a new file readable by its owner alone: the
# task file must still be 644, like the others, whoever xymonlaunch runs as.
( umask 077 && "$ROOT/install.sh" install server XYMONHOME="$home" MANDIR="$work/man" ) >"$work/install.log" 2>&1 \
	|| fail "install.sh install failed: $(tail -n 5 "$work/install.log")"
assert_contains "This machine is the Xymon server (etc/xymonserver.cfg, bin/xymond under $home). The server profile:" "$(cat "$work/install.log")" "the role is detected and said first"

for f in app.py xymon.py xymonapi_client.py tokens.py openapi.yaml requirements.txt xymonapi.sh; do
	assert_file_exists "$home/ext/xymonapi/$f"
done
for f in xymonapi-rag/xymonrag.py xymonapi-rag/xymonapi-rag.sh xymonapi-rag/requirements.txt; do
	assert_file_exists "$home/ext/$f"
done
[ -x "$home/ext/xymonapi/xymonapi.sh" ] || fail "the launcher is not executable"
# Each plugin records its version beside its files: its release tag when
# the checkout is at one, else the version in its PLUGIN file.
for p in xymonapi xymonapi-rag; do
	assert_file_exists "$home/ext/$p/VERSION"
	want=$(git -C "$ROOT" describe --exact-match --tags --match "$p/v*" 2>/dev/null || sed -n 's/^version: *//p' "$ROOT/plugins/$p/PLUGIN")
	assert_equal "$want" "$(cat "$home/ext/$p/VERSION")" "$p/VERSION holds its tag or its PLUGIN version"
done
assert_file_exists "$work/man/man8/xymonapi.8"

task=$home/etc/tasks.d/xymonapi
assert_file_exists "$task"
grep -q '^[[:space:]]*DISABLED$' "$task" || fail "the task is not shipped DISABLED: $(cat "$task")"
grep -q "^[[:space:]]*ENVFILE $home/etc/xymonserver.cfg\$" "$task" \
	|| fail "ENVFILE does not name this server's xymonserver.cfg: $(grep ENVFILE "$task")"
grep -q '@XYMONHOME@' "$task" && fail "@XYMONHOME@ was left unreplaced in $task"
mode=$(ls -l "$task" | cut -c1-10)
assert_equal "-rw-r--r--" "$mode" "the task file's mode under umask 077"

# An update replaces each plugin's directory: a file the new version no
# longer ships does not stay behind, and the install says to restart the API.
echo 'stale' > "$home/ext/xymonapi/gone.py"
echo 'stale' > "$home/ext/xymonapi-rag/gone.py"
"$ROOT/install.sh" install server XYMONHOME="$home" MANDIR="$work/man" >"$work/update.log" 2>&1 \
	|| fail "installing over an install failed: $(tail -n 5 "$work/update.log")"
[ -e "$home/ext/xymonapi/gone.py" ] && fail "a file no longer shipped stayed in ext/xymonapi after an update"
[ -e "$home/ext/xymonapi-rag/gone.py" ] && fail "a file no longer shipped stayed in ext/xymonapi-rag after an update"
assert_file_exists "$home/ext/xymonapi/app.py"
# The install stops a running API itself (xymonapi-auth.sh): with none
# running here it stops nothing, and asks no step of the admin.
assert_not_contains "Stopped" "$(cat "$work/update.log")" "with no API running, the install stops nothing"
assert_not_contains "pkill" "$(cat "$work/update.log")" "and asks no pkill of the admin"

# The admin enables the API, and the next install must not undo it.
grep -v '^[[:space:]]*DISABLED$' "$task" > "$work/enabled"
cp "$work/enabled" "$task"
"$ROOT/install.sh" install server XYMONHOME="$home" MANDIR="$work/man" >"$work/reinstall.log" 2>&1 \
	|| fail "installing a second time failed: $(tail -n 5 "$work/reinstall.log")"
cmp -s "$work/enabled" "$task" \
	|| fail "a second install changed the task file the admin had enabled: $(cat "$task")"

# A server directory with a space, an & and a | in its name: the paths are
# quoted, and the replacement sed makes in the task files is escaped.
odd="$work/x y&z|w"
server_tree "$odd"
"$ROOT/install.sh" install server XYMONHOME="$odd" MANDIR="$work/man 2" >"$work/odd.log" 2>&1 \
	|| fail "install.sh install into a directory with a space, & and | failed: $(tail -n 5 "$work/odd.log")"
assert_file_exists "$odd/ext/xymonapi/xymonapi.sh"
assert_file_exists "$work/man 2/man8/xymonapi.8"
grep -qF "ENVFILE $odd/etc/xymonserver.cfg" "$odd/etc/tasks.d/xymonapi" \
	|| fail "the task file does not name that directory as it is: $(grep ENVFILE "$odd/etc/tasks.d/xymonapi")"
grep -qF "ENVFILE $odd/etc/xymonserver.cfg" "$odd/etc/tasks.d/xymonapi-rag" \
	|| fail "the index task file does not name that directory as it is: $(grep ENVFILE "$odd/etc/tasks.d/xymonapi-rag")"

assert_file_exists "$home/etc/xymonapi-apache.conf"
grep -q 'ProxyPass ' "$home/etc/xymonapi-apache.conf" || fail "the Apache snippet has no ProxyPass"
grep -q 'proxy_pass ' "$home/etc/xymonapi-nginx.conf" || fail "the nginx snippet has no proxy_pass"
grep -q 'proxy.server' "$home/etc/xymonapi-lighttpd.conf" || fail "the lighttpd snippet has no proxy.server"
assert_contains 'Installed. Enable the API' "$(cat "$work/install.log")" "the install says what to do next"
echo "# mine" > "$home/etc/xymonapi-apache.conf"
"$ROOT/install.sh" install server XYMONHOME="$home" MANDIR="$work/man" >/dev/null 2>&1 || fail "a third install failed"
assert_equal "# mine" "$(cat "$home/etc/xymonapi-apache.conf")" "an edited Apache snippet is kept"

# One plugin alone brings what it needs beside it: on the server,
# xymonapi-rag needs the API that serves its index, and its client it reads
# the API with.
alone=$work/alone
server_tree "$alone"
"$ROOT/install.sh" install xymonapi-rag XYMONHOME="$alone" MANDIR="$work/man-alone" >"$work/alone.log" 2>&1 \
	|| fail "install.sh install of xymonapi-rag alone failed: $(tail -n 5 "$work/alone.log")"
for p in xymonapi xymonapi-rag; do
	assert_file_exists "$alone/ext/$p/VERSION"
done

# The tools side: no Xymon here, PREFIX with a space in its name.
prefix="$work/client prefix"
"$ROOT/install.sh" install tools PREFIX="$prefix" >"$work/client.log" 2>&1 \
	|| fail "install.sh install failed: $(tail -n 5 "$work/client.log")"
# An update replaces the plugin's directory there too, and leaves the
# virtualenv an earlier setup made beside the plugins alone.
mkdir -p "$prefix/libexec/xymon-plugins/venv" && : > "$prefix/libexec/xymon-plugins/venv/kept"
: > "$prefix/libexec/xymon-plugins/xymonapi-rag/gone.py"
"$ROOT/install.sh" install tools PREFIX="$prefix" >"$work/client2.log" 2>&1 \
	|| fail "install.sh install a second time failed: $(tail -n 5 "$work/client2.log")"
[ -e "$prefix/libexec/xymon-plugins/xymonapi-rag/gone.py" ] && fail "a file no longer shipped stayed in the client's xymonapi-rag"
assert_file_exists "$prefix/libexec/xymon-plugins/venv/kept"
for f in xymonapi-mcp/server.py xymonapi-mcp/xymonapi-mcp.sh xymonapi/xymonapi_client.py xymonapi/xymonapi-connect.sh \
         xymonapi-rag/xymonrag.py xymonapi-rag/xymonapi-rag.sh xymonapi-rag/requirements.txt xymonapi-mcp/VERSION xymonapi-rag/VERSION; do
	assert_file_exists "$prefix/libexec/xymon-plugins/$f"
done
assert_file_exists "$prefix/share/man/man1/xymonapi-mcp.1"
assert_file_exists "$prefix/share/man/man1/xymonapi-rag.1"
assert_file_exists "$prefix/share/man/man1/xymonapi-connect.1"
[ -x "$prefix/bin/xymonapi-connect" ] || fail "bin/xymonapi-connect is not executable"
[ -x "$prefix/bin/xymonapi-mcp" ] || fail "bin/xymonapi-mcp is not executable"
[ -x "$prefix/bin/xymonapi-rag" ] || fail "bin/xymonapi-rag is not executable"
grep -qF "\"$prefix/libexec/xymon-plugins/xymonapi-rag/xymonapi-rag.sh\"" "$prefix/bin/xymonapi-rag" \
	|| fail "bin/xymonapi-rag does not run the installed launcher, quoted: $(cat "$prefix/bin/xymonapi-rag")"
[ -e "$prefix/libexec/xymon-plugins/xymonapi/app.py" ] && fail "install installed the API"
# The installed xymonapi-rag runs: --help needs Python alone, and finds
# xymonapi_client.py in xymonapi/ beside it, as in the repository.
if command -v "${XYMONAPI_PYTHON:-python3}" >/dev/null 2>&1; then
	XYMONAPI_PYTHON="${XYMONAPI_PYTHON:-python3}" "$prefix/bin/xymonapi-rag" --help > "$work/help.out" 2>&1 \
		|| fail "the installed xymonapi-rag --help failed: $(cat "$work/help.out")"
	assert_contains 'search' "$(cat "$work/help.out")" "and names its commands"
fi

# Removing: a plugin another installed one needs is refused, naming it;
# the whole side removes each plugin's files, manual page and task, keeps
# the web server snippets and the data, and says so. On a laptop it also
# says what register did besides.
for p in xymonapi; do
	rc=0
	"$ROOT/install.sh" remove "$p" XYMONHOME="$home" MANDIR="$work/man" >"$work/un-$p.log" 2>&1 || rc=$?
	[ "$rc" -ne 0 ] || fail "removing $p while xymonapi-mcp and xymonapi-rag need it succeeded"
	# Any of those installed that need it; the first, by name, is xymonapi-mcp.
	assert_contains "$p is needed by xymonapi-mcp" "$(cat "$work/un-$p.log")" "and says which plugin needs $p"
	assert_file_exists "$home/ext/$p/VERSION"
done
"$ROOT/install.sh" remove server XYMONHOME="$home" MANDIR="$work/man" >"$work/remove.log" 2>&1 \
	|| fail "install.sh remove failed: $(tail -n 5 "$work/remove.log")"
for f in ext/xymonapi ext/xymonapi-mcp ext/xymonapi-rag etc/tasks.d/xymonapi etc/tasks.d/xymonapi-rag; do
	[ -e "$home/$f" ] && fail "install.sh remove left $f"
done
[ -e "$work/man/man8/xymonapi.8" ] && fail "install.sh remove left the manual page xymonapi.8"
[ -e "$work/man/man1/xymonapi-rag.1" ] && fail "install.sh remove left the manual page xymonapi-rag.1"
assert_file_exists "$home/etc/xymonapi-apache.conf"
assert_contains "take its Include out of the web server first" "$(cat "$work/remove.log")" "remove says the snippets are kept, and how to remove them"
assert_contains "XYMONAPI_TOKENS" "$(cat "$work/remove.log")" "and that the tokens file is kept"

rc=0
"$ROOT/install.sh" remove xymonapi PREFIX="$prefix" >"$work/unc-api.log" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "remove of xymonapi's client while xymonapi-mcp needs it succeeded"
assert_contains "needed by xymonapi-mcp" "$(cat "$work/unc-api.log")" "and says which plugin needs it"
"$ROOT/install.sh" remove tools PREFIX="$prefix" >"$work/unclient.log" 2>&1 \
	|| fail "install.sh remove failed: $(tail -n 5 "$work/unclient.log")"
[ -e "$prefix/libexec/xymon-plugins" ] && fail "install.sh remove left $prefix/libexec/xymon-plugins: $(ls -A "$prefix/libexec/xymon-plugins")"
for f in bin/xymonapi-mcp bin/xymonapi-rag share/man/man1/xymonapi-mcp.1 share/man/man1/xymonapi-rag.1; do
	[ -e "$prefix/$f" ] && fail "install.sh remove left $f"
done
assert_contains "claude mcp remove" "$(cat "$work/unclient.log")" "remove says what register did besides"

pass "./install.sh install puts the server profiles in ext/ with disabled tasks and the Apache snippet, keeps what the admin edited, takes odd directory names, replaces each plugin's directory on update, and brings a profile a plugin declares; the tools profile lays out your own commands; the profile is a word or PROFILE=NAME, else the detected role's; remove takes them out, refusing one another needs"
