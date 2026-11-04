#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Install, update and remove the plugins, on the Xymon server or on another
# machine, with nothing but a POSIX shell and the usual tools: no make.
#
#   ./install.sh                                    on a terminal: asks what to do, and does it
#   ./install.sh install [PLUGIN...] [server|client|tools]
#   ./install.sh remove [PLUGIN...] [server|client|tools]
#   ./install.sh venv [server|client|tools]         the virtualenv beside the plugins
#
# A plugin ships profiles, each the part of it for one kind of place,
# declared in its PLUGIN file as PROFILE-* keys with where it goes
# (PROFILE-root: ext, $XYMONHOME/ext; prefix, $PREFIX/libexec/xymon-plugins)
# and the roles of a machine that bring it (PROFILE-roles). The first three
# are server, the Xymon server's, the plugins' tasks and the API; client, a
# monitored host's, which nothing ships yet; tools, your own machine's, the
# plugins' commands, as yourself. A plugin may declare another, and the
# script learns the names from the files. A word among the arguments that
# is a profile name says which an action serves. Unsaid, the action serves
# every profile the machine's role brings, the role detected from the tree
# XYMONHOME names -- set by xymoncmd, the Xymon user's environment, or on
# the command line -- and the first line says the role, why, and the
# profiles. Two marks tell a role, both needed and from two places, the
# configuration under etc/ and the program under bin/: etc/xymonserver.cfg
# and bin/xymond the server, etc/xymonclient.cfg and bin/xymonclient.sh a
# monitored host, no mark in common; one mark of a pair is an error, none at
# all a tree that is not Xymon's, and neither is guessed at; no XYMONHOME is
# your own machine.
# Said, the profile is taken as said, so that a package is staged for a
# server this machine is not; a profile under ext still needs XYMONHOME. A
# plugin's directory under a root holds all its profiles there, installed
# and removed whole: one root's profiles are one user's, and one role never
# brings your own commands with the Xymon part, the two being two users.
#
# With no action at all, on a terminal, the script asks: install or remove,
# which role this machine plays, the detected one by default, and which
# plugins, Enter taking each default; it then runs the action those answers
# spell, the profile said, so the words are there to copy for next time.
# Without a terminal, no action means the usage.
#
# With no PLUGIN, every plugin of that side. A plugin that needs another
# installs it first, and a removal is refused while one installed needs
# the plugin removed. Running an install again updates: each plugin's
# directory is replaced as a whole, and the admin's task files, web server
# snippets and data are kept. Settings come from the environment, or as
# NAME=value arguments: XYMONHOME, PREFIX, MANDIR (/usr/share/man), DESTDIR,
# which stages either side for a package, and PYTHON, the Python a
# virtualenv is made with.
#
# What each plugin installs is in its plugins/NAME/PLUGIN file. On a server
# the plugins go under $XYMONHOME/ext/, one directory each, and a plugin that
# needs another finds it beside itself; elsewhere they go under
# $PREFIX/libexec/xymon-plugins/ the same way, with a command per plugin in
# $PREFIX/bin. Each records its version beside its files, in VERSION, and
# the virtualenv they share sits beside them, as venv/. Every path is
# quoted, and escaped before it reaches sed: a directory with a space, an &
# or a | in its name is a directory like any other.

ROOT=$(cd "$(dirname "$0")" && pwd)

die() { echo "install.sh: $*" >&2; exit 1; }
usage() {
	echo "usage: ./install.sh install|remove PLUGIN|PLUGIN-PROFILE|PROFILE... [NAME=value...]" >&2
	echo "       ./install.sh venv [PROFILE] [NAME=value...]" >&2
	echo "       ./install.sh                                  on a terminal: asks what to do" >&2
	echo "PROFILE is one of $(echo $(profiles) | sed 's/ /, /g'). PLUGIN-PROFILE, as xymonapi-server, pins one plugin to one profile; PLUGIN alone takes the machine's, PROFILE alone every plugin of it. Nothing named installs nothing:" >&2
	echo "etc/xymonserver.cfg and bin/xymond under XYMONHOME make the server, etc/xymonclient.cfg and bin/xymonclient.sh a monitored host, no XYMONHOME your own machine." >&2
	exit 2
}

# profiles -- the profile names the PLUGIN files declare, as NAME-root
# keys, and client, which no plugin ships yet: a word among the arguments
# that is one of them is the profile, so a plugin declaring a fourth
# changes nothing here.
profiles() {
	{ sed -n 's/^\([a-z0-9_]*\)-root: .*/\1/p' "$ROOT"/plugins/*/PLUGIN; echo client; } | sort -u
}
is_profile() { case " $(echo $(profiles)) " in *" $1 "*) return 0 ;; esac; return 1; }

# The first word that is not a NAME=value setting is the action. Of the
# others, a profile name is the profile for every plugin not pinned, and
# alone means every plugin of that profile; a PLUGIN-PROFILE word -- the
# long form, xymonapi-mcp-tools -- pins that plugin to that profile whatever
# the machine; a plugin name alone takes the machine's profiles. A word
# that is a profile name never reaches the plugins, so no plugin may be
# called like one. No action on a terminal is the dialogue, which runs once
# the helpers below are defined; no action elsewhere is the usage.
ACTION=
NAMES=
PROFILE=
PINNED=
for a in "$@"; do
	case $a in
		*=*) export "$a" ;;
		*) if [ -z "$ACTION" ]; then ACTION=$a
		   elif is_profile "$a"; then [ -z "$PROFILE" ] || [ "$PROFILE" = "$a" ] || die "two profiles given: $PROFILE and $a"; PROFILE=$a
		   else
			pinned=
			for prof in $(profiles); do
				case $a in *-$prof) [ -f "$ROOT/plugins/${a%-$prof}/PLUGIN" ] && pinned="${a%-$prof}:$prof" ;; esac
			done
			if [ -n "$pinned" ]; then PINNED="$PINNED $pinned"; NAMES="$NAMES ${pinned%%:*}"
			else NAMES="$NAMES $a"; fi
		   fi ;;
	esac
done
DIALOGUE=
if [ -z "$ACTION" ]; then
	[ -t 0 ] && [ -t 1 ] || usage
	DIALOGUE=1
fi

XYMONHOME=${XYMONHOME:-}
DESTDIR=${DESTDIR:-}
MANDIR=${MANDIR:-/usr/share/man}
PREFIX=${PREFIX:-$HOME/.local}
# PYTHON given is also the one an install makes the virtualenv from, in
# place of its search for one.
PYTHON_GIVEN=${PYTHON:-}
PYTHON=${PYTHON:-python3}

EXTROOT=$DESTDIR$XYMONHOME/ext
ETC=$DESTDIR$XYMONHOME/etc
TASKDIR=$ETC/tasks.d
TOOLSROOT=$DESTDIR$PREFIX/libexec/xymon-plugins
BIN=$DESTDIR$PREFIX/bin
TOOLSMAN1=$DESTDIR$PREFIX/share/man/man1
# What other machines install from, which the API serves at /plugins: each
# plugin installed on the server stages its directory here, as in the
# repository, beside this script and LICENSE.
DIST=$EXTROOT/xymon-plugins-dist

# field PLUGIN KEY -- the value of KEY in the plugin's PLUGIN file, one line
# for each time the key appears.
field() { sed -n "s/^$2: //p" "$ROOT/plugins/$1/PLUGIN"; }

# sedesc TEXT -- TEXT escaped for the right-hand side of a sed s|||.
sedesc() { printf '%s\n' "$1" | sed -e 's/[\\&|]/\\&/g'; }

# say PLUGIN KEY -- print the plugin's message KEY, its placeholders filled.
say() {
	field "$1" "$2" | sed -e "s|@ETC@|$(sedesc "$ETC")|g" -e "s|@TASKDIR@|$(sedesc "$TASKDIR")|g" \
		-e "s|@XYMONHOME@|$(sedesc "$XYMONHOME")|g"
}

# What makes a machine a Xymon server or a monitored host: two marks each,
# both needed, under the tree XYMONHOME names, and none in common, so that
# the two cannot be mistaken for each other. The two marks of a side come
# from two places, its configuration file under etc/ and its program under
# bin/, so that they are two pieces of evidence and not one seen twice: a
# tree with only its etc/ copied in, or linked, shows one mark and is
# refused. Every layout known, Debian's, the RPM's, Homebrew's and a source
# install, keeps bin/ under XYMONHOME. A tree with both pairs is the server,
# which always has a client.
SERVER_CFG=etc/xymonserver.cfg; SERVER_RUN=bin/xymond
CLIENT_CFG=etc/xymonclient.cfg; CLIENT_RUN=bin/xymonclient.sh

# marks CFG RUN -- how many of a side's two marks are there.
marks() { n=0; for m in "$@"; do [ -e "$XYMONHOME/$m" ] && n=$((n + 1)); done; echo $n; }

# detected_role -- the role this machine plays, named by the profile it
# takes: server or client when both of that role's marks are there, tools
# with no XYMONHOME; nothing when a tree has none of the marks, or one of a
# pair, which role_problem then explains.
detected_role() {
	[ -n "$XYMONHOME" ] || { echo tools; return; }
	if [ "$(marks $SERVER_CFG $SERVER_RUN)" -eq 2 ]; then echo server
	elif [ "$(marks $CLIENT_CFG $CLIENT_RUN)" -eq 2 ]; then echo client
	fi
}

# role_problem -- why no role was detected under $XYMONHOME: a pair half
# there is an error to look at, none at all is a tree that is not Xymon's.
role_problem() {
	for pair in "server:$SERVER_CFG:$SERVER_RUN" "client:$CLIENT_CFG:$CLIENT_RUN"; do
		role=${pair%%:*}; rest=${pair#*:}; cfg=${rest%%:*}; run=${rest#*:}
		if [ "$(marks $cfg $run)" -eq 1 ]; then
			[ -e "$XYMONHOME/$cfg" ] && echo "$XYMONHOME has $cfg but not $run: half a Xymon $role tree, which this script does not guess at" \
				|| echo "$XYMONHOME has $run but not $cfg: half a Xymon $role tree, which this script does not guess at"
			return
		fi
	done
	echo "$XYMONHOME is neither a Xymon server ($SERVER_CFG, $SERVER_RUN) nor a monitored host ($CLIENT_CFG, $CLIENT_RUN): say the profile, or unset XYMONHOME for your own machine"
}

# role_profiles ROLE -- the profiles the PLUGIN files give that role, as
# PROFILE-roles keys; client, which no plugin ships yet, for the client role.
role_profiles() {
	{ for f in "$ROOT"/plugins/*/PLUGIN; do
		sed -n 's/^\([a-z0-9_]*\)-roles: \(.*\)/\1 \2/p' "$f" | while read -r prof roles; do
			case " $roles " in *" $1 "*) echo "$prof" ;; esac
		done
	  done; [ "$1" != client ] || echo client; } | sort -u
}

# root_of PLUGIN PROFILE -- ext or prefix, empty for a profile the plugin
# has not. plugin_declared PLUGIN -- the profiles it declares. base_dir ROOT
# -- where that root's plugins live.
root_of() { field "$1" "$2-root"; }
plugin_declared() { sed -n 's/^\([a-z0-9_]*\)-root: .*/\1/p' "$ROOT/plugins/$1/PLUGIN"; }
base_dir() { case $1 in ext) echo "$EXTROOT" ;; prefix) echo "$TOOLSROOT" ;; esac; }
man_dir() { case $1 in ext) echo "$DESTDIR$MANDIR" ;; prefix) echo "$DESTDIR$PREFIX/share/man" ;; esac; }

# settle_profile -- PROFILES, the profiles this run serves: the one said,
# taken as said so that a package is staged for a server this machine is
# not; unsaid, every profile the detected role brings. Only what cannot be
# done without is checked: a profile under ext needs XYMONHOME. client is
# refused, since no plugin ships that profile yet. The first line says the
# role, what told it, and the profiles.
settle_profile() {
	for pin in $PINNED; do
		pl=${pin%%:*} prof=${pin#*:}
		[ -n "$(root_of "$pl" "$prof")" ] || die "$pl has no $prof profile: its profiles are $(echo $(plugin_declared "$pl"))"
	done
	ROLE=$(detected_role)
	# The profiles of the plugins not pinned: said, or the role's. With every
	# plugin pinned, none is needed, and the role may stay undetected.
	unpinned=
	for n in $NAMES; do case " $PINNED " in *" $n:"*) ;; *) unpinned=1 ;; esac; done
	[ -n "$NAMES" ] || unpinned=1
	if [ -z "$unpinned" ]; then PROFILES=
	elif [ -n "$PROFILE" ]; then PROFILES=$PROFILE
	elif [ -n "$ROLE" ]; then PROFILES=$(echo $(role_profiles "$ROLE"))
	else die "$(role_problem)"
	fi
	[ -n "$PROFILES" ] || [ -z "$unpinned" ] || die "$(role_line "$ROLE") No plugin here has a profile for that role."
	all=$PROFILES; for pin in $PINNED; do all="$all ${pin#*:}"; done
	all=$(echo $all | tr ' ' '\n' | sort -u | tr '\n' ' ')
	case " $all " in *" client "*)
		die "$(role_line client) No plugin ships a client profile yet; the plugins' commands go on your own machine: ./install.sh $ACTION ... tools" ;;
	esac
	ROOTS=
	for prof in $all; do
		for pl in $(all_plugins); do
			r=$(root_of "$pl" "$prof"); [ -n "$r" ] || continue
			case " $ROOTS " in *" $r "*) ;; *) ROOTS="$ROOTS $r" ;; esac
		done
	done
	case " $ROOTS " in *" ext "*) [ -n "$XYMONHOME" ] || die "the $(echo $all | sed 's/ /, /g') profile needs XYMONHOME, the Xymon server directory: XYMONHOME=/usr/lib/xymon/server ./install.sh $ACTION ..." ;; esac
	echo "$(role_line "$ROLE") $(profiles_phrase $all)"
}

# role_line ROLE -- the machine's role and what tells it.
role_line() {
	case $1 in
		server) echo "This machine is the Xymon server ($SERVER_CFG, $SERVER_RUN under $XYMONHOME)." ;;
		client) echo "This machine is a monitored host ($CLIENT_CFG, $CLIENT_RUN under $XYMONHOME)." ;;
		tools) echo "This is your own machine." ;;
		"") echo "No Xymon role detected under $XYMONHOME; the profile is as said." ;;
	esac
}

# profiles_phrase PROFILE... -- "the X profile" or "the X and Y profiles",
# each with where it goes.
profiles_phrase() {
	if [ $# -eq 1 ]; then printf 'The %s profile: %s.\n' "$1" "$(profile_where "$1")"
	else
		out=
		for prof in "$@"; do out="$out, $prof ($(profile_where "$prof"))"; done
		echo "The profiles${out}."
	fi
}
profile_where() {
	case $1 in
		server) echo "the plugins' tasks and the API, under $XYMONHOME/ext" ;;
		tools) echo "the plugins' commands, under $PREFIX" ;;
		*) for pl in $(all_plugins); do r=$(root_of "$pl" "$1"); [ -n "$r" ] && { echo "under $(base_dir "$r")"; return; }; done ;;
	esac
}

# Every plugin, by the directories under plugins/ that hold a PLUGIN file.
all_plugins() {
	for f in "$ROOT"/plugins/*/PLUGIN; do
		[ -e "$f" ] && basename "$(dirname "$f")"
	done
}

# known PLUGIN -- refuse a name that is not a plugin here, or that could
# name a directory other than one plugin's.
known() {
	case $1 in ""|*/*|.|..) die "not a plugin name: '$1'" ;; esac
	[ -f "$ROOT/plugins/$1/PLUGIN" ] || die "no plugin $1 here: the plugins are $(echo $(all_plugins))"
}

# depth PLUGIN -- how many plugins deep it stands on: 0 for one that needs
# none. Removing every plugin goes from the deepest up.
depth() {
	d=0
	for n in $(field "$1" needs); do
		x=$(depth "$n"); [ $((x + 1)) -gt $d ] && d=$((x + 1))
	done
	echo $d
}

# dependents PLUGIN -- the plugins that name it in their needs.
dependents() {
	for p in $(all_plugins); do
		case " $(field "$p" needs) " in *" $1 "*) echo "$p" ;; esac
	done
}

# fresh DIR -- DIR, emptied: an install replaces a plugin's directory as a
# whole, so that a file a newer version no longer ships does not stay behind
# to be imported. It holds only what the plugin ships and its VERSION.
fresh() { rm -rf "$1" && mkdir -p "$1"; }

# copy PLUGIN SIDE DIR -- the side's files into DIR, executable or not.
copy() {
	exe=" $(field "$1" executable) "
	for f in $(field "$1" "$2-files"); do
		cp -f "$ROOT/plugins/$1/$f" "$3/" || exit 1
		case $exe in *" $f "*) chmod 755 "$3/$f" ;; *) chmod 644 "$3/$f" ;; esac
	done
}

# version PLUGIN DIR -- the plugin's version, in DIR/VERSION. Installed from
# a release, the commit its tag PLUGIN/vX.Y.Z names, it is that tag, which
# git checks out: the API's, which /health gives so a laptop fetches the same
# code. From any other commit, or an archive, the version in the PLUGIN file.
version() {
	v=$(git -C "$ROOT/plugins/$1" describe --exact-match --tags --match "$1/v*" 2>/dev/null) || v=$(field "$1" version)
	printf '%s\n' "$v" > "$2/VERSION" && chmod 644 "$2/VERSION"
}

# manual PLUGIN PAGE MANROOT -- the page into its section's directory.
manual() {
	[ -n "$2" ] || return 0
	mkdir -p "$3/man${2##*.}" && cp -f "$ROOT/plugins/$1/$2" "$3/man${2##*.}/" && chmod 644 "$3/man${2##*.}/$2"
}

# dist PLUGIN -- stage the plugin's directory under $DIST/plugins, as it is
# in the repository but for its tests, with this script and LICENSE beside:
# a machine unpacking it runs ./install.sh install there, as itself, at the
# server's versions. Links are copied as links, as in the repository.
dist() {
	rm -rf "$DIST/plugins/$1"
	mkdir -p "$DIST/plugins"
	cp -R "$ROOT/plugins/$1" "$DIST/plugins/$1"
	rm -rf "$DIST/plugins/$1/tests"
	find "$DIST/plugins/$1" -name __pycache__ -prune -exec rm -rf {} +
	cp -f "$ROOT/install.sh" "$ROOT/LICENSE" "$DIST/"
}

# task PLUGIN PROFILE -- the profile's xymonlaunch task file as tasks.d/PLUGIN, @XYMONHOME@
# replaced, unless one is there already: the one an admin enabled is not put
# back to DISABLED by the next install.
task() {
	t=$(field "$1" "$2-task"); [ -n "$t" ] || return 0
	mkdir -p "$TASKDIR"
	if [ -e "$TASKDIR/$1" ]; then
		echo "keeping $TASKDIR/$1"
	else
		sed -e "s|@XYMONHOME@|$(sedesc "$XYMONHOME")|g" "$ROOT/plugins/$1/$t" > "$TASKDIR/$1" && chmod 644 "$TASKDIR/$1"
	fi
}

# conf PLUGIN PROFILE -- the profile's web server snippets into $XYMONHOME/etc unless there
# already: an admin's edits are kept, as a task file is.
conf() {
	for c in $(field "$1" "$2-conf"); do
		if [ -e "$ETC/$c" ]; then
			echo "keeping $ETC/$c"
		else
			cp "$ROOT/plugins/$1/$c" "$ETC/" && chmod 644 "$ETC/$c"
		fi
	done
}

# restart PLUGIN PROFILE -- a process that runs the profile's program from this
# install keeps the code it loaded: stop it, and xymonlaunch starts the new.
# Found by its command line, which names the program by its full path,
# escaped for pgrep's regular expressions, as a directory may hold a | or a
# dot. With DESTDIR the path is the staging one, which nothing runs from.
restart() {
	prog=$(field "$1" "$2-restart"); [ -n "$prog" ] || return 0
	if ! command -v pgrep >/dev/null 2>&1; then
		echo "An API that runs keeps the old code until it is stopped; xymonlaunch then starts the new."
		return 0
	fi
	pat=$(printf '%s/%s' "$(base_dir "$(root_of "$1" "$2")")/$1" "$prog" | sed -e 's/[][\\.*^$|+?(){}]/\\&/g')
	pids=$(echo $(pgrep -f "$pat" | grep -vx "$$"))
	[ -n "$pids" ] || return 0
	if kill $pids 2>/dev/null; then
		echo "Stopped the API that ran the old code (PID $pids): xymonlaunch starts the new one."
	else
		echo "Could not stop the API that runs the old code (PID $pids): stop it with kill $pids, and xymonlaunch starts the new one." >&2
	fi
}

# offer QUESTION -- on a terminal, ask it; true on y. Without one, false.
offer() {
	[ -t 0 ] && [ -t 1 ] || return 1
	printf '%s [y/N] ' "$1"
	read -r yn
	case $yn in [yY]*) return 0 ;; esac
	return 1
}

# ask QUESTION DEFAULT -- on a terminal, the answer to QUESTION, DEFAULT
# when Enter alone is typed.
ask() {
	printf '%s [%s] ' "$1" "$2" >&2
	read -r answer
	[ -n "$answer" ] && echo "$answer" || echo "$2"
}

# dialogue -- the questions ./install.sh asks when given no word on a
# terminal, then the action they spell, run as if its words had been typed.
# The role defaults to the detected one, and picks the profile. The plugins offered are those of that profile and,
# for a removal, those installed; a plugin unticked takes with it the ones
# that need it, and a plugin removed takes its installed dependents, each
# named, since that is what the actions themselves insist on.
dialogue() {
	echo "The Xymon plugins. Enter takes the answer in brackets."
	verb=$(ask "Install or remove?" install)
	case $verb in
		i*) verb=install ;;
		r*) verb=remove ;;
		*) die "neither install nor remove: '$verb'" ;;
	esac
	found=$(detected_role)
	case $found in server) role=1 ;; client) role=2 ;; tools) role=3 ;; *) role= ;; esac
	if [ -n "$found" ]; then echo "Which role does this machine play? Detected: $found."
	else echo "Which role does this machine play? Not detected: $(role_problem)"; fi
	echo "  1. the Xymon server: $(echo $(role_profiles server) | sed 's/ /, /g'), the plugins' tasks and the API, under ${XYMONHOME:-XYMONHOME}/ext"
	echo "  2. a monitored host: client (no plugin ships that profile yet)"
	echo "  3. your own machine: $(echo $(role_profiles tools) | sed 's/ /, /g'), the plugins' commands, under $PREFIX"
	role=$(ask "Role" "${role:-none}")
	case $role in
		1*|s*) side=server ;;
		2*|c*) side=client ;;
		3*|t*) side=tools ;;
		*) die "neither 1, 2 nor 3: '$role'" ;;
	esac
	if [ "$side" = server ] && [ -z "$XYMONHOME" ]; then
		XYMONHOME=$(ask "XYMONHOME, the Xymon server directory" /usr/lib/xymon/server)
		export XYMONHOME
		EXTROOT=$DESTDIR$XYMONHOME/ext
	fi
	[ "$side" = tools ] && XYMONHOME= && export XYMONHOME
	[ "$side" != client ] || die "$(role_line client) No plugin ships a client profile yet."
	# The role's profiles, as the action will take them; said as one word
	# when the role has one profile, so the printed command needs nothing else.
	PROFILES=$(echo $(role_profiles "$side"))
	ROOTS=; for prof in $PROFILES; do for pl in $(all_plugins); do r=$(root_of "$pl" "$prof"); [ -n "$r" ] || continue; case " $ROOTS " in *" $r "*) ;; *) ROOTS="$ROOTS $r" ;; esac; done; done
	offered=
	for p in $(for p in $(all_plugins); do echo "$(depth "$p") $p"; done | sort -n | cut -d' ' -f2); do
		has=
		for r in $ROOTS; do
			[ -n "$(plugin_profiles "$p" "$r" "$PROFILES")" ] || continue
			[ "$verb" = install ] || [ -e "$(base_dir "$r")/$p" ] || continue
			has=1
		done
		[ -n "$has" ] || continue
		offered="$offered $p"
	done
	[ -n "$offered" ] || die "nothing to $verb for that role: no plugin installed for it"
	echo "Plugins, all of them unless you name some:"
	for p in $offered; do
		printf '  %-16s %s\n' "$p" "$(field "$p" summary)"
	done
	chosen=$(ask "Plugins" "$(echo $offered)")
	for n in $chosen; do
		known "$n"
		case " $offered " in *" $n "*) ;; *) die "$n is not among the plugins to $verb here" ;; esac
	done
	if [ "$verb" = install ]; then
		for n in $chosen; do
			for d in $(field "$n" needs); do
				case " $chosen " in *" $d "*) ;; *) chosen="$chosen $d"; echo "With $d, which $n needs." ;; esac
			done
		done
	else
		for n in $chosen; do
			for d in $(dependents "$n"); do
				inst=; for r in $ROOTS; do [ -e "$(base_dir "$r")/$d" ] && inst=1; done
				[ -n "$inst" ] || continue
				case " $chosen " in *" $d "*) ;; *) chosen="$chosen $d"; echo "With $d, installed here, which needs $n." ;; esac
			done
		done
	fi
	# The command, in long words, one per plugin and profile: what it does
	# is then plain to read, and it runs the same on any machine.
	words=
	for n in $chosen; do
		for prof in $PROFILES; do [ -n "$(root_of "$n" "$prof")" ] && words="$words $n-$prof"; done
	done
	echo "Running: $([ "$side" != server ] || echo "XYMONHOME=$XYMONHOME ")./install.sh $verb $(echo $words)"
	echo
	exec "$ROOT/install.sh" "$verb" $words
}

# venv_auto PLUGIN ROOT MODULES NOTE -- the last step of installing a
# plugin that needs the Python modules MODULES (their import names), which
# downloads nothing unless asked. With no virtualenv at ROOT/venv yet: the
# newest Python 3.9 or later on this machine that has them already --
# PYTHON when given, else python3.14 down to python3.9 and python3, on PATH
# and in Homebrew's and pyenv's directories -- is made the virtualenv's,
# with --system-site-packages, so that it is only pinned beside the plugins
# and nothing is copied or fetched; with no such Python, the hint says which
# ./install.sh venv would use. A candidate is named by the interpreter it
# runs (sys.executable), not a shim or link found on PATH. With a virtualenv
# there, the modules it lacks are named. On a terminal the hint is an offer:
# on "y", ./install.sh venv installs the modules from PyPI there and then.
# NOTE says in the offer what the modules are for.
venv_auto() {
	plugin=$1 root=$2 modules=$3 note=$4
	[ -n "$modules" ] || return 0
	# The hint, as typed for this run: the profile, when the run serves one.
	target="./install.sh venv"; [ "$(echo $PROFILES | wc -w)" -ne 1 ] || target="$target $PROFILES"
	if [ -x "$root/venv/bin/python3" ]; then
		missing=$("$root/venv/bin/python3" -c 'import importlib.util as u, sys; print(" ".join(m for m in sys.argv[1:] if u.find_spec(m) is None))' $modules)
		[ -z "$missing" ] && return 0
		if offer "The virtualenv $root/venv lacks $missing, which $plugin needs${note:+ ($note)}. Install them into it, from PyPI?"; then
			"$ROOT/install.sh" venv $PROFILE || exit 1
		else
			echo "The virtualenv $root/venv lacks $missing, which this plugin needs: $target installs them."
		fi
		return 0
	fi
	py= newest=
	for c in ${PYTHON_GIVEN:-python3.14 python3.13 python3.12 python3.11 python3.10 python3.9 python3}; do
		for d in "" /opt/homebrew/bin /usr/local/bin /opt/homebrew/opt/python@3.*/bin "$HOME"/.pyenv/versions/*/bin; do
			case $c in
				/*) p=$c ;;
				*) if [ -n "$d" ]; then p=$d/$c; else p=$(command -v "$c" 2>/dev/null); fi ;;
			esac
			[ -n "$p" ] && [ -x "$p" ] || continue
			"$p" -c 'import sys; sys.exit(sys.version_info < (3, 9))' 2>/dev/null || continue
			real=$("$p" -c 'import sys; print(sys.executable)' 2>/dev/null)
			[ -n "$real" ] && [ -x "$real" ] && p=$real
			[ -n "$newest" ] || newest=$p
			"$p" -c 'import importlib.util as u, sys; sys.exit(any(u.find_spec(m) is None for m in sys.argv[1:]))' $modules 2>/dev/null || continue
			py=$p; break 2
		done
	done
	if [ -n "$py" ]; then
		"$py" -m venv --system-site-packages "$root/venv" || exit 1
		echo "Made $root/venv from $py ($("$py" -V 2>&1)), which has the modules this plugin needs ($modules): the plugins there run with it."
	elif [ -n "$newest" ] && offer "$plugin needs $modules, which no Python here has${note:+ ($note)}. Make a virtualenv at $root/venv with $newest, and install them from PyPI?"; then
		PYTHON=$newest "$ROOT/install.sh" venv $PROFILE || exit 1
	else
		echo "No virtualenv at $root/venv, and no Python with the modules this plugin needs ($modules): $target${newest:+ PYTHON=$newest} makes one and installs them; without it, the python3 on PATH must have them."
	fi
}

# venv ROOT -- a virtualenv at ROOT/venv, beside the plugins installed in
# ROOT, with the modules of each, from the requirements.txt installed with
# it: what every launcher runs with when XYMONAPI_PYTHON names no other. Run
# again, it adds the modules of a plugin installed since.
venv() {
	[ -d "$1" ] || die "nothing is installed in $1 yet"
	[ -x "$1/venv/bin/python3" ] || "$PYTHON" -m venv "$1/venv" || exit 1
	for r in "$1"/*/requirements.txt; do
		[ -e "$r" ] || continue
		echo "installing the modules of $r"
		"$1/venv/bin/python3" -m pip install -q -r "$r" || exit 1
	done
	echo "The plugins in $1 run with $1/venv/bin/python3 ($("$1/venv/bin/python3" -V))."
}

# A plugin's directory under a root holds every profile of it that lives
# there, and is installed and removed whole: the profiles of one root are
# one user's. install_plugin PLUGIN ROOT PROFILES installs the plugin's
# profiles among PROFILES that live under ROOT, after the plugins it needs,
# which take the same profiles, so that a plugin pinned to a profile brings
# what it needs in that profile.
DONE=
install_plugin() {
	case " $DONE " in *" $1:$2 "*) return 0 ;; esac
	for n in $(field "$1" needs); do install_plugin "$n" "$2" "$3"; done
	profs=$(plugin_profiles "$1" "$2" "$3")
	[ -n "$profs" ] || return 0
	dir=$(base_dir "$2")/$1
	fresh "$dir" || exit 1
	modules= note=
	for prof in $profs; do
		copy "$1" "$prof" "$dir"
		manual "$1" "$(field "$1" "$prof-manual")" "$(man_dir "$2")"
		modules="$modules $(field "$1" "$prof-modules")"
		[ -n "$note" ] || note=$(field "$1" "$prof-venv-note")
		command_for "$1" "$prof"
		task "$1" "$prof"
		conf "$1" "$prof"
	done
	version "$1" "$dir"
	[ "$2" != ext ] || dist "$1"
	for prof in $profs; do say "$1" "$prof-installed"; done
	for prof in $profs; do restart "$1" "$prof"; done
	venv_auto "$1" "$(base_dir "$2")" "$(echo $modules)" "$note"
	DONE="$DONE $1:$2"
}

# plugin_profiles PLUGIN ROOT PROFILES -- the plugin's profiles, among
# PROFILES, that live under ROOT.
plugin_profiles() {
	for prof in $3; do [ "$(root_of "$1" "$prof")" = "$2" ] && echo "$prof"; done
	return 0
}

# wanted PLUGIN -- the profiles asked of the plugin: the ones it is pinned
# to, else PROFILES.
wanted() {
	w=
	for pin in $PINNED; do [ "${pin%%:*}" = "$1" ] && w="$w ${pin#*:}"; done
	echo "${w:-$PROFILES}"
}

# command_for PLUGIN PROFILE -- the profile's command in $PREFIX/bin, running
# the script from where it is installed: PREFIX as given, without DESTDIR,
# quoted.
command_for() {
	set -- "$1" $(field "$1" "$2-command")
	[ $# -eq 3 ] || return 0
	mkdir -p "$BIN"
	printf '#!/bin/sh\nexec "%s/libexec/xymon-plugins/%s/%s" "$@"\n' "$PREFIX" "$1" "$3" > "$BIN/$2"
	chmod 755 "$BIN/$2"
}

# needed PLUGIN DIR -- refuse to remove the plugin while one installed in DIR
# needs it beside it: removing it would leave that one broken.
needed() {
	for d in $(dependents "$1"); do
		[ -e "$2/$d" ] && die "$1 is needed by $d, installed in $2: remove $d first"
	done
	return 0
}

# remove_plugin PLUGIN ROOT PROFILES -- the plugin's directory under ROOT, with the
# manual pages, commands and tasks of its profiles there; refused while an
# installed plugin needs it.
remove_plugin() {
	profs=$(plugin_profiles "$1" "$2" "$3")
	[ -n "$profs" ] || return 0
	dir=$(base_dir "$2")/$1
	[ -e "$dir" ] || return 0
	needed "$1" "$(base_dir "$2")"
	[ "$2" != ext ] || needed "$1" "$DIST/plugins"
	rm -rf "$dir"
	[ "$2" != ext ] || rm -rf "$DIST/plugins/$1"
	for prof in $profs; do
		m=$(field "$1" "$prof-manual")
		[ -n "$m" ] && rm -f "$(man_dir "$2")/man${m##*.}/$m"
		set -- "$1" "$2" "$prof" $(field "$1" "$prof-command")
		[ $# -eq 5 ] && rm -f "$BIN/$4"
		set -- "$1" "$2"
		[ -n "$(field "$1" "$prof-task")" ] && rm -f "$TASKDIR/$1"
		say "$1" "$prof-removed"
	done
	return 0
}

[ -z "$DIALOGUE" ] || dialogue

# The plugins named, each checked, or every plugin; for a removal, the
# deepest first, so that none is removed while one installed needs it.
for n in $NAMES; do known "$n"; done
if [ -n "$NAMES" ]; then LIST=$(echo $NAMES | tr ' ' '\n' | awk '!seen[$0]++')
elif [ -n "$PROFILE" ] || [ "$ACTION" = venv ]; then LIST=$(all_plugins)
elif [ "$ACTION" = install ] || [ "$ACTION" = remove ]; then
	die "nothing named, nothing done: name the plugins -- the plugins are $(echo $(all_plugins)) -- or a profile for all of them, or run ./install.sh with no words on a terminal and be asked"
fi
deepest_first() {
	for n in $LIST; do echo "$(depth "$n") $n"; done | sort -rn | cut -d' ' -f2
}

settle_profile
case $ACTION in
	install)
		for r in $ROOTS; do for n in $LIST; do install_plugin "$n" "$r" "$(wanted "$n")"; done; done
		for n in $NAMES; do
			case " $DONE " in *" $n:"*) ;; *) die "$n has no $(echo $(wanted "$n") | sed 's/ /, /g') profile" ;; esac
		done ;;
	remove)
		for r in $ROOTS; do
			for n in $(deepest_first); do remove_plugin "$n" "$r" "$(wanted "$n")"; done
			if [ -z "$NAMES" ]; then
				rm -rf "$(base_dir "$r")/venv"
				[ "$r" != prefix ] || rmdir "$TOOLSROOT" 2>/dev/null || true
			fi
		done ;;
	venv)
		for r in $ROOTS; do venv "$(base_dir "$r")"; done ;;
	*) usage ;;
esac
