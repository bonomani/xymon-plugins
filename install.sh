#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Install, update and remove the plugins, on the Xymon server or on another
# machine, with nothing but a POSIX shell and the usual tools: no make.
#
#   XYMONHOME=/usr/lib/xymon/server ./install.sh install-server [PLUGIN...]  on the Xymon server
#   ./install.sh install-tools [PLUGIN...]       on your own machine, under PREFIX (~/.local)
#   ./install.sh enable-server|disable-server [PLUGIN...]  a server task on or off
#   ./install.sh uninstall-server|uninstall-tools [PLUGIN...]
#   ./install.sh status-server|status-tools [PLUGIN...]  what is installed, and on
#   ./install.sh venv-server|venv-tools          the virtualenv beside the plugins
#
# Every action names its side. Without one -- install, uninstall, venv,
# enable, disable, status -- it is refused, naming the -server action and,
# where there is one, the -tools; install-client and its kin are refused,
# naming the tools action: "client" is Xymon's, the monitored host, and the
# action of that name will install a client extension there once one is
# here.
#
# With no PLUGIN, every plugin of that side. A server plugin whose xymon:
# line names a newer Xymon than $XYMONHOME/bin/xymon --version gives is
# refused, unless --force. A development version, 4.3.32-dev, comes after
# 4.3.31 and before 4.3.32: a plugin that needs 4.3.32 installs on it with
# a warning, as it may lack what 4.3.32 brought. A plugin that needs another
# installs it first, and an uninstall is refused while one installed needs
# the plugin removed. An install starts nothing: a server task is on when
# tasks.d/PLUGIN, a link to it, is there, which enable-server makes and
# disable-server removes. Running an install again updates: each plugin's
# directory is replaced as a whole, and the admin's task files, whether each
# is on, web server snippets and data are kept. Settings come from the environment, or as
# NAME=value arguments: XYMONHOME, PREFIX, MANDIR (/usr/share/man; Homebrew's share/man for a Xymon it installed), DESTDIR,
# which stages either side for a package, and PYTHON, the Python a
# virtualenv is made with.
#
# What each plugin installs is in its plugins/NAME/PLUGIN file. On a server
# the plugins go under $XYMONHOME/ext/, one directory each, and a plugin that
# needs another finds it beside itself; elsewhere they go under
# $PREFIX/libexec/xymon-plugins/ the same way, with a command per plugin in
# $PREFIX/bin. Each records its version beside its files, in VERSION, and
# its PLUGIN file, by which it is uninstalled, enabled and updated later;
# the virtualenv they share sits beside them, as venv/. Every path is
# quoted, and escaped before it reaches sed: a directory with a space, an &
# or a | in its name is a directory like any other.

ROOT=$(cd "$(dirname "$0")" && pwd)

die() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }
usage() {
	echo "usage: ./install.sh install-server|install-tools|enable-server|disable-server|status-server|status-tools|uninstall-server|uninstall-tools|venv-server|venv-tools [--force] [PLUGIN...] [NAME=value...]" >&2
	exit 2
}

[ $# -ge 1 ] || usage
ACTION=$1; shift
NAMES=
FORCE=
for a in "$@"; do
	case $a in
		--force) FORCE=1 ;;
		-*) usage ;;
		*=*) export "$a" ;;
		*) NAMES="$NAMES $a" ;;
	esac
done

XYMONHOME=${XYMONHOME:-}
DESTDIR=${DESTDIR:-}
# MANDIR, /usr/share/man by default, which macOS lets no one write: for a
# Xymon that Homebrew installed, XYMONHOME under its prefix, Homebrew's
# share/man, where man looks.
if [ -z "${MANDIR:-}" ]; then
	MANDIR=/usr/share/man
	bp=$(brew --prefix 2>/dev/null) || bp=
	if [ -n "$bp" ]; then
		case $XYMONHOME in "$bp"/*) MANDIR=$bp/share/man ;; esac
	fi
fi
PREFIX=${PREFIX:-$HOME/.local}
# PYTHON given is also the one an install makes the virtualenv from, in
# place of its search for one.
PYTHON_GIVEN=${PYTHON:-}
PYTHON=${PYTHON:-python3}

# inside PATH -- where PATH, absolute and without DESTDIR, lies under
# DESTDIR, each part followed inside it: a link to an absolute path taken
# from DESTDIR, a relative one from where it lies, a .. stopping at
# DESTDIR. Xymon's own staged install links $XYMONHOME/etc to INSTALLETCDIR,
# /etc/xymon on Debian and with the RPM, and a packager may link any
# directory of the stage the same way: followed as they are, such links
# lead out of the stage into the build host's directories, and an install
# under DESTDIR writes nothing outside it. A link that cannot be read, or
# forty in a row, stops the run rather than be guessed at. Without
# DESTDIR, PATH as it is. Run in $(...): its variables stay there.
inside() {
	if [ -z "$DESTDIR" ]; then printf '%s\n' "$1"; return; fi
	rest=$1 cur= hops=0
	while [ -n "$rest" ]; do
		case $rest in /*) rest=${rest#/}; continue ;; esac
		part=${rest%%/*}
		if [ "$part" = "$rest" ]; then rest=; else rest=${rest#*/}; fi
		case $part in
			.) continue ;;
			..) cur=${cur%/*}; continue ;;
		esac
		if [ -L "$DESTDIR$cur/$part" ]; then
			hops=$((hops + 1))
			[ "$hops" -le 40 ] || die "more than 40 links under DESTDIR at $cur/$part"
			t=$(readlink "$DESTDIR$cur/$part") && [ -n "$t" ] || die "cannot read the link $DESTDIR$cur/$part"
			case $t in /*) cur= ;; esac
			rest=$t${rest:+/$rest}
		else
			cur=$cur/$part
		fi
	done
	printf '%s\n' "$DESTDIR${cur:-/}"
}

EXTROOT=$(inside "$XYMONHOME/ext") || exit 1
ETC=$(inside "$XYMONHOME/etc") || exit 1
TASKDIR=$(inside "$XYMONHOME/etc/tasks.d") || exit 1
TOOLSROOT=$(inside "$PREFIX/libexec/xymon-plugins") || exit 1
BIN=$(inside "$PREFIX/bin") || exit 1
TOOLSMAN1=$(inside "$PREFIX/share/man/man1") || exit 1
# What other machines install from, which the API serves at /plugins: each
# plugin installed on the server stages its directory here, as in the
# repository, beside this script and LICENSE.
DIST=$EXTROOT/xymon-plugins-dist

# field PLUGIN KEY -- the value of KEY in the plugin's PLUGIN file, one line
# for each time the key appears; nothing for a plugin gone from the checkout.
field() { [ ! -f "$ROOT/plugins/$1/PLUGIN" ] || sed -n "s/^$2: //p" "$ROOT/plugins/$1/PLUGIN"; }

# held ROOT PLUGIN KEY -- the value of KEY in the PLUGIN file installed with
# the plugin under ROOT ($EXTROOT or $TOOLSROOT): the record of what that
# install put in place, which uninstall, enable, disable and an update act
# on, rather than on what this checkout would install. An install from
# before the record has none: the checkout's is read, as it was. The record
# lies in a directory the Xymon user can write, so a name read from it is
# used only once plain says it names no other directory.
held() {
	if [ -f "$1/$2/PLUGIN" ] && [ ! -L "$1/$2/PLUGIN" ]; then
		sed -n "s/^$3: //p" "$1/$2/PLUGIN"
	elif [ -f "$ROOT/plugins/$2/PLUGIN" ]; then
		field "$2" "$3"
	fi
}

# sedesc TEXT -- TEXT escaped for the right-hand side of a sed s|||.
sedesc() { printf '%s\n' "$1" | sed -e 's/[\\&|]/\\&/g'; }

# say PLUGIN KEY -- print the plugin's message KEY, its placeholders filled
# with the paths of the installed system, never the stage's under DESTDIR:
# the message is for whoever runs that system.
say() {
	field "$1" "$2" | sed -e "s|@ETC@|$(sedesc "$XYMONHOME/etc")|g" -e "s|@TASKDIR@|$(sedesc "$XYMONHOME/etc/tasks.d")|g" \
		-e "s|@XYMONHOME@|$(sedesc "$XYMONHOME")|g"
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
	plain "$1" || die "not a plugin name: '$1'"
	[ -f "$ROOT/plugins/$1/PLUGIN" ] || [ -f "$EXTROOT/$1/PLUGIN" ] || [ -f "$TOOLSROOT/$1/PLUGIN" ] \
		|| die "no plugin $1 here: the plugins are $(echo $(all_plugins))"
}

# depth PLUGIN [ROOT] -- how many plugins deep it stands on: 0 for one that
# needs none; by the records of the plugins installed under ROOT when
# given, as an uninstall goes from the deepest up among what is installed.
depth() {
	# Always run in $(...): globbing off for this subshell only.
	set -f
	d=0
	if [ -n "${2:-}" ]; then needs=$(held "$2" "$1" needs); else needs=$(field "$1" needs); fi
	for n in $needs; do
		plain "$n" || continue
		x=$(depth "$n" "${2:-}"); [ $((x + 1)) -gt $d ] && d=$((x + 1))
	done
	echo $d
}

# dependents PLUGIN -- the plugins that name it in their needs.
dependents() {
	for p in $(all_plugins); do
		case " $(field "$p" needs) " in *" $1 "*) echo "$p" ;; esac
	done
}

# older A B -- true when version A is older than B, comparing X.Y.Z by
# number; awk reads 32-dev as 32.
older() {
	awk -v a="$1" -v b="$2" 'BEGIN {
		n = split(a, x, "."); m = split(b, y, ".")
		for (i = 1; i <= (n > m ? n : m); i++) {
			if (x[i] + 0 < y[i] + 0) exit 0
			if (x[i] + 0 > y[i] + 0) exit 1
		}
		exit 1
	}'
}

# xymon_ok PLUGIN -- refuse the plugin, or one it needs, when its xymon:
# line names a newer Xymon than the server's, unless --force; say so when
# the server's cannot be read. Run on every plugin to install before any is
# touched.
CHECKED=
xymon_ok() {
	case " $CHECKED " in *" $1 "*) return 0 ;; esac
	CHECKED="$CHECKED $1"
	for n in $(field "$1" needs); do xymon_ok "$n"; done
	want=$(field "$1" xymon); [ -n "$want" ] || return 0
	xymon=$(inside "$XYMONHOME/bin/xymon") || exit 1
	have=$("$xymon" --version 2>/dev/null | sed -n 's/^Xymon version \([0-9][0-9.]*[^ ]*\).*/\1/p')
	if [ -z "$have" ]; then
		echo "install.sh: $1 needs Xymon $want or newer, and the version of $xymon could not be read: not checked" >&2
	elif older "$have" "$want"; then
		[ -n "$FORCE" ] || die "$1 needs Xymon $want or newer, and this server's is $have: --force installs it anyway"
		echo "install.sh: $1 needs Xymon $want or newer, and this server's is $have: installed anyway, as --force asks" >&2
	elif [ "$have" != "${have%%-*}" ] && ! older "$want" "${have%%-*}"; then
		echo "install.sh: $1 needs Xymon $want or newer, and this server's is $have, on the way to $want: not checked" >&2
	fi
	return 0
}

# reads_d -- say when the server's xymonserver.cfg does not read
# xymonserver.d/, where the plugins' settings go: a configuration kept from
# before 4.3.31 would ignore them all, without a word.
reads_d() {
	c=$(inside "$XYMONHOME/etc/xymonserver.cfg") || exit 1
	[ -f "$c" ] || return 0
	grep -q '^[[:space:]]*\(optional[[:space:]]\{1,\}\)\{0,1\}directory[[:space:]]\{1,\}\(.*/\)\{0,1\}xymonserver\.d/\{0,1\}[[:space:]]*$' "$c" && return 0
	echo "install.sh: $c does not read xymonserver.d/, where the plugins' settings go: add the line" >&2
	echo "  optional directory $XYMONHOME/etc/xymonserver.d" >&2
	echo "as Xymon's own xymonserver.cfg has it since 4.3.31" >&2
}

# marks TREE -- what TREE is by Xymon's marks, a whole pair counting before
# any single mark: server, when both of a server's are there, a client's
# files with them or not, as where server and client share /etc/xymon;
# else client; else "some MARK..." naming the marks there; else none.
SERVER_MARKS="etc/xymonserver.cfg bin/xymond"
CLIENT_MARKS="etc/xymonclient.cfg bin/xymonclient.sh"
marks() {
	found=
	for m in $SERVER_MARKS $CLIENT_MARKS; do
		if [ -e "$1/$m" ]; then found="$found $m"; fi
	done
	case " $found " in
		*" etc/xymonserver.cfg"*" bin/xymond "*) echo server ;;
		*" etc/xymonclient.cfg"*" bin/xymonclient.sh "*) echo client ;;
		"  ") echo none ;;
		*) echo "some$found" ;;
	esac
}

# xymon_trees -- the Xymon trees on this machine, "KIND DIR" each: those
# XYMON_PLUGINS_TREES names, colon-separated, and the packages' usual paths,
# Homebrew's among them where brew is installed.
# It only tells what is here: nothing is chosen from it.
# ponytail: fixed paths only; a running xymonlaunch's tree when a relocated
# server needs finding, which ps cannot tell portably.
xymon_trees() {
	{
		printf '%s\n' "${XYMON_PLUGINS_TREES:-}" | tr ':' '\n'
		for t in /usr/lib/xymon/server /usr/lib/xymon/client /usr/local/xymon/server \
			/usr/local/xymon/client /home/xymon/server /home/xymon/client; do
			printf '%s\n' "$t"
		done
		bp=$(brew --prefix 2>/dev/null) && [ -n "$bp" ] && printf '%s\n' "$bp/opt/xymon-server/server"
	} | sort -u | while IFS= read -r t; do
		[ -n "$t" ] || continue
		k=$(marks "$t")
		case $k in server|client) printf '%s %s\n' "$k" "$t" ;; esac
	done
}

# need_home -- the server's part goes in the tree XYMONHOME names, and only
# in a server's: without XYMONHOME, the trees found are named, none chosen;
# a client's tree, part of a pair and no marks at all are refused before
# anything changes. Under DESTDIR, a staging target, no marks are read,
# the host's included.
need_home() {
	if [ -z "$XYMONHOME" ]; then
		found=
		[ -n "$DESTDIR" ] || found=$(xymon_trees | sed 's/^\([a-z]*\) \(.*\)/  \2, a Xymon \1/')
		die "XYMONHOME is not set: XYMONHOME=<the Xymon server directory> ./install.sh $ACTION [PLUGIN...]${found:+
Xymon trees found here, none chosen:
$found}"
	fi
	[ -z "$DESTDIR" ] || return 0
	set -- $(marks "$XYMONHOME")
	case $1 in
		client) die "$XYMONHOME is a Xymon client's tree ($CLIENT_MARKS), not a server's: the server's part of a plugin goes in a server's tree" ;;
		some) shift; die "$XYMONHOME is not a whole Xymon server's tree: it has $*, and a server's has $SERVER_MARKS" ;;
		none) die "$XYMONHOME is no Xymon server's tree: none of $SERVER_MARKS is there; to stage one for a package, set DESTDIR" ;;
	esac
}

# fresh DIR -- DIR, emptied: an install replaces a plugin's directory as a
# whole, so that a file a newer version no longer ships does not stay behind
# to be imported. It holds only what the plugin ships, its VERSION and its
# PLUGIN file.
fresh() { rm -rf "$1" && mkdir -p "$1"; }

# copy PLUGIN SIDE DIR -- the side's files into DIR, executable or not.
copy() {
	exe=" $(field "$1" executable) "
	set -f
	for f in $(field "$1" "$2-files"); do
		plain "$f" || die "$1's PLUGIN file names '$f' to install, which is no file of its own directory"
		[ ! -L "$ROOT/plugins/$1/$f" ] || die "$1's $f is a link, which is not installed"
		cp -f "$ROOT/plugins/$1/$f" "$3/" || exit 1
		case $exe in *" $f "*) chmod 755 "$3/$f" ;; *) chmod 644 "$3/$f" ;; esac || exit 1
	done
	set +f
}

# version PLUGIN DIR -- the plugin's version, in DIR/VERSION. Installed from
# a release, the commit its tag PLUGIN/vX.Y.Z names, it is that tag, which
# git checks out: the API's, which /health gives so a laptop fetches the same
# code. From any other commit, or an archive, the version in the PLUGIN file.
version() {
	v=$(git -C "$ROOT/plugins/$1" describe --exact-match --tags --match "$1/v*" 2>/dev/null) || v=$(field "$1" version)
	printf '%s\n' "$v" > "$2/VERSION" && chmod 644 "$2/VERSION"
}

# manual PLUGIN PAGE DIR MANROOT FINAL -- the page kept in the plugin's
# directory DIR, and linked from its section's directory under MANROOT,
# without DESTDIR, found inside it; the link names FINAL, that directory as
# installed, without DESTDIR too. Removing
# the directory leaves a link that points nowhere, and a removal knows the
# page is the plugin's by the link, not by what its record says.
manual() {
	[ -n "$2" ] || return 0
	plain "$2" || die "$1's PLUGIN file names '$2' as its manual page, which is no file of its own directory"
	[ ! -L "$ROOT/plugins/$1/$2" ] || die "$1's $2 is a link, which is not installed"
	cp -f "$ROOT/plugins/$1/$2" "$3/$2" && chmod 644 "$3/$2" || exit 1
	sec=$(inside "$4/man${2##*.}") || exit 1
	mkdir -p "$sec" || exit 1
	rm -f "$sec/$2" && ln -s "$5/$2" "$sec/$2" || exit 1
}

# declared PLUGINFILE -- the names a PLUGIN file gives to stage, one per
# line: itself, README.md, each side's files and manual page, the task and
# the snippets. Read with globbing off; the callers check each is a plain
# name of the plugin's own directory.
declared() {
	echo PLUGIN
	echo README.md
	for k in server-files tools-files server-manual tools-manual task conf; do
		sed -n "s/^$k: //p" "$1" | tr ' ' '\n'
	done
}

# plain NAME -- true when NAME is a file name of a plugin's own directory:
# letters, digits, ., _, + and - only, and not . or ..: no /, and nothing a
# shell would expand or split.
plain() {
	case $1 in ""|.|..|*[!A-Za-z0-9._+-]*) return 1 ;; esac
	return 0
}

# dist PLUGIN -- stage under $DIST/plugins what a machine needs to install
# the plugin, with this script and LICENSE beside: a machine unpacking it
# runs ./install.sh install-tools there, at the server's versions. Only
# what the PLUGIN file names is staged, each a plain file of the plugin's
# directory and no link, so that a file left beside them in the checkout,
# a note, a key, a build's leftover, is not served to anyone by /plugins.
# The stage is pruned first, then the plugin built beside its old copy
# and moved into place, so that a failure leaves the old copy whole.
dist() {
	prune_dist
	d=$DIST/plugins/$1
	new=$DIST/plugins/.$1.new
	exe=" $(field "$1" executable) "
	mkdir -p "$new" || exit 1
	set -f
	for f in $(declared "$ROOT/plugins/$1/PLUGIN"); do
		plain "$f" || die "$1's PLUGIN file names '$f' to stage, which is no file of its own directory"
		src=$ROOT/plugins/$1/$f
		if [ "$f" = README.md ] && [ ! -e "$src" ]; then continue; fi
		[ ! -L "$src" ] || die "$1's $f is a link, which /plugins does not serve"
		cp -f "$src" "$new/" || exit 1
		case $exe in *" $f "*) chmod 755 "$new/$f" ;; *) chmod 644 "$new/$f" ;; esac || exit 1
	done
	set +f
	rm -rf "$d" || die "could not replace $d"
	mv "$new" "$d" || die "could not replace $d"
	rm -f "$DIST/install.sh" "$DIST/LICENSE" || die "could not replace $DIST/install.sh and LICENSE"
	cp -f "$ROOT/install.sh" "$ROOT/LICENSE" "$DIST/" || exit 1
	chmod 755 "$DIST/install.sh" && chmod 644 "$DIST/LICENSE" || exit 1
}

# prune_dist -- what /plugins serves holds nothing else: at the top only
# install.sh and LICENSE, files, and plugins/, a directory, none a link; in
# plugins/ only the directories of plugins installed here, each with a
# PLUGIN file holding plain names, and holding only the files it names.
# An install before this one staged a plugin's whole source directory,
# whatever lay in it, and a plugin since renamed or gone leaves a copy that
# no install of this one rewrites. A removal that fails stops the run: a
# file left would still be served.
prune_dist() {
	[ -e "$DIST" ] || [ -L "$DIST" ] || return 0
	if [ -L "$DIST" ] || [ ! -d "$DIST" ]; then
		rm -rf "$DIST" || die "could not remove $DIST"
		return 0
	fi
	for e in "$DIST"/* "$DIST"/.[!.]* "$DIST"/..?*; do
		[ -e "$e" ] || [ -L "$e" ] || continue
		case ${e##*/} in
			install.sh|LICENSE) [ -f "$e" ] && [ ! -L "$e" ] && continue ;;
			plugins) [ -d "$e" ] && [ ! -L "$e" ] && continue ;;
		esac
		rm -rf "$e" || die "could not remove $e, which /plugins would serve"
	done
	for p in "$DIST"/plugins/* "$DIST"/plugins/.[!.]* "$DIST"/plugins/..?*; do
		[ -e "$p" ] || [ -L "$p" ] || continue
		if [ -L "$p" ] || [ ! -d "$p" ] || [ ! -f "$p/PLUGIN" ] || [ -L "$p/PLUGIN" ] \
			|| [ ! -f "$EXTROOT/${p##*/}/VERSION" ]; then
			rm -rf "$p" || die "could not remove $p, which /plugins would serve"
			continue
		fi
		set -f
		keep=" "
		for f in $(declared "$p/PLUGIN"); do
			if plain "$f"; then keep="$keep$f "; else keep=; break; fi
		done
		set +f
		if [ -z "$keep" ]; then
			rm -rf "$p" || die "could not remove $p, which /plugins would serve"
			continue
		fi
		for e in "$p"/* "$p"/.[!.]* "$p"/..?*; do
			[ -e "$e" ] || [ -L "$e" ] || continue
			case $keep in *" ${e##*/} "*) [ -f "$e" ] && [ ! -L "$e" ] && continue ;; esac
			rm -rf "$e" || die "could not remove $e, which /plugins would serve"
		done
	done
}

# ours PLUGIN -- refuse a tasks.d/PLUGIN that is a link to something other
# than the plugin's task file: it is not ours to change.
ours() {
	if [ -L "$TASKDIR/$1" ] && [ "$(readlink "$TASKDIR/$1")" != "$XYMONHOME/ext/$1/tasks.cfg" ]; then
		die "$TASKDIR/$1 is a link to $(readlink "$TASKDIR/$1"), not $1's task: left alone"
	fi
}

# task PLUGIN -- its xymonlaunch task file, @XYMONHOME@ replaced, kept in
# the plugin's directory as ext/PLUGIN/tasks.cfg. The task is on when
# tasks.d/PLUGIN, a link to that file, is there: removing ext/PLUGIN by hand
# then takes the task with it, since xymonlaunch skips a link that points
# nowhere and stops the task at its next reload, where a copy in tasks.d
# would have it log that it cannot start the task, forever. A first install
# makes no link. A later one keeps the task file as the admin left it --
# install_server sets it aside before it replaces the directory -- and
# whether the task is on. A regular file at tasks.d/PLUGIN wins over the
# one set aside, as it is the one xymonlaunch was reading: the copy an older
# install made there, or what an editor that writes by renaming, "sed -i"
# among them, left where the link was. It is moved into the directory, and
# linked. Older installs said off with a DISABLED line in the file: a file
# with one is off, its line taken out and its link removed.
task() {
	t=$(field "$1" task); [ -n "$t" ] || return 0
	tf=$EXTROOT/$1/tasks.cfg
	link=$TASKDIR/$1
	ours "$1"
	mkdir -p "$TASKDIR"
	on=
	if [ -f "$link" ] && [ ! -L "$link" ]; then
		on=1
		rm -f "$EXTROOT/.$1.tasks.cfg"
		mv "$link" "$tf" || exit 1
		echo "keeping $link, moved to $tf"
	elif [ -f "$EXTROOT/.$1.tasks.cfg" ]; then
		[ -L "$link" ] && on=1
		mv "$EXTROOT/.$1.tasks.cfg" "$tf" || exit 1
		echo "keeping $tf"
	else
		sed -e "s|@XYMONHOME@|$(sedesc "$XYMONHOME")|g" "$ROOT/plugins/$1/$t" > "$tf" && chmod 644 "$tf"
	fi
	if grep -q '^[[:space:]]*DISABLED[[:space:]]*$' "$tf"; then
		on=
		sed -e '/^[[:space:]]*DISABLED[[:space:]]*$/d' "$tf" > "$tf.new" && mv "$tf.new" "$tf" && chmod 644 "$tf" || exit 1
		echo "$1's task was DISABLED: it is off from now on, by its link"
	fi
	rm -f "$link"
	if [ -n "$on" ]; then
		ln -s "$XYMONHOME/ext/$1/tasks.cfg" "$link" || exit 1
		echo "$1's task is on, as it was"
	else
		echo "$1's task is off: XYMONHOME=$XYMONHOME ./install.sh enable-server $1 turns it on"
	fi
}

# enable PLUGIN, disable PLUGIN -- its task on or off, by its link.
enable() {
	[ -n "$(held "$EXTROOT" "$1" task)" ] || die "$1 has no task to enable"
	[ -f "$EXTROOT/$1/tasks.cfg" ] || die "$1 is not installed in $EXTROOT"
	ours "$1"
	[ -L "$TASKDIR/$1" ] || [ ! -d "$TASKDIR/$1" ] || die "$TASKDIR/$1 is a directory, not $1's task: left alone"
	[ -L "$TASKDIR/$1" ] && { echo "$1 is on already"; return 0; }
	mkdir -p "$TASKDIR"
	ln -s "$XYMONHOME/ext/$1/tasks.cfg" "$TASKDIR/$1" || exit 1
	echo "$1 is on: xymonlaunch reads it within half a minute and starts it; one that keeps failing it holds for ten minutes after five restarts"
}
disable() {
	[ -n "$(held "$EXTROOT" "$1" task)" ] || die "$1 has no task to disable"
	ours "$1"
	[ -L "$TASKDIR/$1" ] || { echo "$1 is off already"; return 0; }
	rm -f "$TASKDIR/$1"
	echo "$1 is off: xymonlaunch stops it within half a minute"
}

# status SIDE ROOT PLUGIN -- one line for the plugin on that side: the
# version installed, from its VERSION -- a release tag, NAME/vX.Y.Z, read as
# its X.Y.Z -- or that it is not; on the server, whether its task is on; and
# the version in this checkout, with "newer" when it is, or that the
# checkout has it no more. The side and the task are read from the
# installed copy of its PLUGIN file. A plugin that has nothing on that
# side says nothing.
status() {
	[ -n "$(held "$2" "$3" "$1-files")" ] || return 0
	here=$(field "$3" version)
	if [ ! -f "$2/$3/VERSION" ]; then
		echo "$3: not installed; this checkout has $here"
		return 0
	fi
	v=$(sed -e 's|^.*/v||' "$2/$3/VERSION")
	state=
	if [ "$1" = server ] && [ -n "$(held "$2" "$3" task)" ]; then
		if [ -L "$TASKDIR/$3" ]; then state=", on"; else state=", off"; fi
	fi
	if [ -z "$here" ]; then
		echo "$3: $v installed$state; not in this checkout"
		return 0
	fi
	newer=
	older "$v" "$here" && newer=", newer"
	echo "$3: $v installed$state; this checkout has $here$newer"
}

# installed_tasks -- the plugins named, or every one installed with a task.
installed_tasks() {
	for n in $LIST; do
		if [ -n "$NAMES" ] || { [ -n "$(held "$EXTROOT" "$n" task)" ] && [ -d "$EXTROOT/$n" ]; }; then echo "$n"; fi
	done
}

# conf PLUGIN -- its web server snippets, in the plugin's directory, which
# the web server includes in a way that skips a file that is not there --
# Apache's IncludeOptional, a wildcard include for nginx -- so that removing
# ext/PLUGIN takes them with it, and the web server still starts. The one an
# admin edited is kept: install_server set it aside; one an older version
# shipped, unedited, takes this version's.

# cfgval NAME -- NAME's value in the server's configuration, as written:
# the last NAME= line, quotes and comment taken off, of xymonserver.cfg and
# then of the files in xymonserver.d/, which Xymon reads after it, leaving
# out what it leaves out: dot-files, editor backups, README and packaging
# leftovers.
# ponytail: one level of xymonserver.d/, as the plugins write it; Xymon also
# reads its subdirectories.
cfgval() {
	c=$(inside "$XYMONHOME/etc/xymonserver.cfg") || exit 1
	d=$(inside "$XYMONHOME/etc/xymonserver.d") || exit 1
	[ -f "$c" ] || return 0
	for f in "$c" "$d"/*; do
		[ -f "$f" ] || continue
		case ${f##*/} in .*|*~|*,v|README*|*.dpkg-new|*.dpkg-orig|*.rpmsave|*.rpmorig|*.rpmnew) continue ;; esac
		sed -n -e "s/^[[:space:]]*$1=\"\([^\"]*\)\".*/\1/p" -e "s/^[[:space:]]*$1=\([^\"#[:space:]]*\).*/\1/p" "$f"
	done | tail -n 1
}

# rundir -- Xymon's directory for runtime files, where a plugin's sockets
# go: XYMONRUNDIR, or XYMONSERVERLOGS when it is empty, as Xymon does. Asked
# of Xymon itself first: xymoncmd loads xymonserver.cfg as xymonlaunch does
# for the plugins' tasks -- its includes and directories, its variables
# expanded, Xymon's defaults -- so the snippets name the socket the API
# makes; with a clean environment, so that nothing of this shell's slips
# in. Under DESTDIR the stage's xymoncmd is not run, being the installed
# system's, and where it is missing or fails, the files are read here, as
# cfgval reads them. Empty when that gives no absolute path -- one that names
# a variable, read here -- which the install cannot know.
rundir() {
	if [ -z "$DESTDIR" ] && [ -x "$XYMONHOME/bin/xymoncmd" ]; then
		# xymoncmd expands a $ in its own arguments: it runs env, and the
		# two settings are read from what env prints.
		e=$(env -i PATH=/usr/bin:/bin "$XYMONHOME/bin/xymoncmd" --env="$XYMONHOME/etc/xymonserver.cfg" env 2>/dev/null) || e=
		r=$(printf '%s\n' "$e" | sed -n 's/^XYMONRUNDIR=//p' | tail -n 1)
		[ -n "$r" ] || r=$(printf '%s\n' "$e" | sed -n 's/^XYMONSERVERLOGS=//p' | tail -n 1)
		case $r in /*\$*) ;; /*) echo "$r"; return 0 ;; esac
	fi
	r=$(cfgval XYMONRUNDIR) || exit 1
	[ -n "$r" ] || r=$(cfgval XYMONSERVERLOGS) || exit 1
	case $r in /*\$*) ;; /*) echo "$r" ;; esac
}

# stock PLUGIN SNIPPET -- the snippet as this version ships it, @XYMONHOME@
# and @XYMONRUNDIR@ filled in, as the task file's is: what it names lies
# under the server's tree, which only the install knows. @XYMONRUNDIR@ stays
# where rundir is empty.
stock() {
	sed -e "s|@XYMONHOME@|$(sedesc "$XYMONHOME")|g" ${RUNDIR:+-e "s|@XYMONRUNDIR@|$(sedesc "$RUNDIR")|g"} "$ROOT/plugins/$1/$2"
}

# shipped PLUGIN SNIPPET FILE -- true when FILE is, byte for byte, the
# snippet as an older version shipped it: its cksum is among the plugin's
# conf-stock lines, as it is, or with $XYMONHOME put back as @XYMONHOME@, or
# $RUNDIR as @XYMONRUNDIR@ and then $XYMONHOME, so that the same snippet
# installed under any tree gives the same one. As it is first: a snippet
# without a placeholder is then recognised whatever the tree, though
# $XYMONHOME may also be part of its text (/xymon in /xymon/api/). Where
# that putting back cannot tell, the snippet is taken for edited: kept, and
# said to differ, never overwritten.
shipped() {
	list="
$(field "$1" conf-stock)
"
	for way in raw home ${RUNDIR:+run}; do
		sum=$(awk -v way="$way" -v h="$XYMONHOME" -v r="$RUNDIR" '
		function back(s, p, name,    out, i) {
			out = ""
			while ((i = index(s, p)) > 0) { out = out substr(s, 1, i - 1) name; s = substr(s, i + length(p)) }
			return out s
		}
		{ s = $0
		  if (way == "run") s = back(s, r, "@XYMONRUNDIR@")
		  if (way != "raw") s = back(s, h, "@XYMONHOME@")
		  print s }' "$3" | cksum | cut -d' ' -f1,2)
		case $list in *"
$2 $sum
"*) return 0 ;; esac
	done
	return 1
}

# same PLUGIN SNIPPET FILE -- true when FILE is this version's snippet. The
# x keeps the last newlines a command substitution drops.
same() {
	[ "$(stock "$1" "$2"; echo x)" = "$(cat "$3"; echo x)" ]
}

conf() {
	# The snippets name a path under $XYMONHOME and Xymon's runtime
	# directory; one a web server's configuration cannot take as it is is
	# said, for the admin to write, and so is a runtime directory the
	# install cannot know.
	RUNDIR=$(rundir) || exit 1
	case $XYMONHOME$RUNDIR in
		*[!A-Za-z0-9._/+-]*) echo "The web server snippets in $EXTROOT/$1 name $XYMONHOME${RUNDIR:+ and $RUNDIR}, which hold characters a web server's configuration may not take as they are: check the path in the snippet you include." ;;
	esac
	[ -n "$RUNDIR" ] || echo "The web server snippets in $EXTROOT/$1 name @XYMONRUNDIR@: $XYMONHOME/etc/xymonserver.cfg gives XYMONRUNDIR, or XYMONSERVERLOGS, as no path the install can read; put Xymon's runtime directory in its place in the snippet you include."
	for c in $(field "$1" conf); do
		dst=$EXTROOT/$1/$c
		if [ -f "$EXTROOT/.$1.$c" ]; then
			mv "$EXTROOT/.$1.$c" "$dst" || exit 1
		else
			stock "$1" "$c" > "$dst" && chmod 644 "$dst" || exit 1
			continue
		fi
		# A kept snippet an older version shipped, unedited, takes this
		# version's; one that differs from it is the admin's, and kept,
		# said to be.
		if same "$1" "$c" "$dst"; then
			:
		elif shipped "$1" "$c" "$dst"; then
			stock "$1" "$c" > "$dst" && chmod 644 "$dst" || exit 1
			echo "$dst, an older version's as shipped, is replaced by this version's"
		else
			echo "$dst is kept as edited; this version's differs: compare it with $ROOT/plugins/$1/$c, @XYMONHOME@ being $XYMONHOME${RUNDIR:+ and @XYMONRUNDIR@ $RUNDIR}"
		fi
	done
}

# selinux PLUGIN -- where SELinux is active, load the plugin's SELinux
# module, PLUGIN.cil in its installed directory, which semodule takes as it
# is; what it grants lies behind booleans, off until the admin sets them,
# as its message says (S23). Named after the plugin, never otherwise, so
# that an uninstall, which reads the installed PLUGIN copy, removes that
# module and no other. Under DESTDIR nothing is loaded: it is the installed
# system's.
selinux() {
	m=$(field "$1" selinux); [ -n "$m" ] || return 0
	[ "$m" = "$1.cil" ] || die "$1: its SELinux module must be $1.cil, not $m"
	if [ -n "$DESTDIR" ]; then
		echo "Under DESTDIR no SELinux module is loaded: on the installed system, where SELinux is active, semodule -i $XYMONHOME/ext/$1/$m"
		return 0
	fi
	command -v selinuxenabled >/dev/null 2>&1 && selinuxenabled && command -v semodule >/dev/null 2>&1 || return 0
	if semodule -i "$EXTROOT/$1/$m"; then
		say "$1" selinux-loaded
	else
		echo "Could not load the SELinux module $EXTROOT/$1/$m: semodule -i it as root" >&2
	fi
}

# restart PLUGIN -- a process that runs the plugin's program from this
# install keeps the code it loaded: stop it, and confirm xymonlaunch starts
# the new.
# Found by its command line, which names the program by its full path,
# escaped for pgrep's regular expressions, as a directory may hold a | or a
# dot. With DESTDIR the path is the staging one, which nothing runs from.
restart() {
	prog=$(field "$1" restart); [ -n "$prog" ] || return 0
	if ! command -v pgrep >/dev/null 2>&1; then
		echo "An API that runs keeps the old code until it is stopped; xymonlaunch then starts the new."
		return 0
	fi
	pat=$(printf '%s/%s' "$EXTROOT/$1" "$prog" | sed -e 's/[][\\.*^$|+?(){}]/\\&/g')
	pids=$(echo $(pgrep -f "$pat" | grep -vx "$$"))
	[ -n "$pids" ] || return 0
	if kill $pids 2>/dev/null; then
		# Confirm the respawn rather than promise it: xymonlaunch restarts
		# the task within half a minute, as a process at the same path whose
		# PID is none of those just stopped. Where xymonlaunch is not running
		# to respawn it, none appears and the wait ends saying so.
		# XYMON_PLUGINS_RESPAWN_WAIT, the seconds to wait, is for the tests.
		new=
		i=0; waitsecs=${XYMON_PLUGINS_RESPAWN_WAIT:-35}
		while [ "$i" -lt "$waitsecs" ]; do
			sleep 1
			for p in $(pgrep -f "$pat" | grep -vx "$$"); do
				case " $pids " in *" $p "*) ;; *) new=$p; break ;; esac
			done
			[ -n "$new" ] && break
			i=$((i + 1))
		done
		if [ -n "$new" ]; then
			echo "Stopped the API that ran the old code (PID $pids); xymonlaunch started the new one (PID $new)."
		else
			echo "Stopped the API that ran the old code (PID $pids); xymonlaunch had not restarted it after ${waitsecs}s: check that xymonlaunch is running." >&2
		fi
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

# venv_auto PLUGIN ROOT MODULES TARGET NOTE -- the last step of installing a
# plugin that needs the Python modules MODULES (their import names), which
# downloads nothing unless asked. With no virtualenv at ROOT/venv yet: the
# newest Python 3.9 or later on this machine that has them already --
# PYTHON when given, else python3.14 down to python3.9 and python3, on PATH
# and in Homebrew's and pyenv's directories -- is made the virtualenv's,
# with --system-site-packages, so that it is only pinned beside the plugins
# and nothing is copied or fetched; with no such Python, the hint says which
# ./install.sh TARGET would use. A candidate is named by the interpreter it
# runs (sys.executable), not a shim or link found on PATH. With a virtualenv
# there, the modules it lacks are named. On a terminal the hint is an offer:
# on "y", ./install.sh TARGET -- venv-server or venv-tools -- installs the modules
# from PyPI there and then. NOTE says in the offer what the modules are for.
venv_auto() {
	plugin=$1 root=$2 modules=$3 target=$4 note=$5
	[ -n "$modules" ] || return 0
	if [ -n "$DESTDIR" ]; then
		echo "Under DESTDIR no virtualenv is made or used: on the installed system, ./install.sh $target makes one for $plugin's modules ($modules)."
		return 0
	fi
	if [ -x "$root/venv/bin/python3" ]; then
		missing=$("$root/venv/bin/python3" -c 'import importlib.util as u, sys; print(" ".join(m for m in sys.argv[1:] if u.find_spec(m) is None))' $modules)
		[ -z "$missing" ] && return 0
		if offer "The virtualenv $root/venv lacks $missing, which $plugin needs${note:+ ($note)}. Install them into it, from PyPI?"; then
			"$ROOT/install.sh" "$target" || exit 1
		else
			echo "The virtualenv $root/venv lacks $missing, which this plugin needs: ./install.sh $target installs them."
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
			# One that prints no interpreter is none, whatever its exit
			# status: an empty file runs as an empty script, and exits 0.
			real=$("$p" -c 'import sys; print(sys.executable)' 2>/dev/null)
			[ -n "$real" ] || continue
			[ -x "$real" ] && p=$real
			[ -n "$newest" ] || newest=$p
			"$p" -c 'import importlib.util as u, sys; sys.exit(any(u.find_spec(m) is None for m in sys.argv[1:]))' $modules 2>/dev/null || continue
			py=$p; break 2
		done
	done
	if [ -n "$py" ]; then
		# It has the modules: where it cannot make a virtualenv -- Debian
		# without python3-venv -- the plugins can still run with it.
		if ! "$py" -m venv --system-site-packages "$root/venv" || [ ! -x "$root/venv/bin/python3" ]; then
			echo "Could not make a virtualenv at $root/venv with $py (on Debian and Ubuntu, python3-venv provides what it needs): the plugins run with the python3 on PATH, or XYMONAPI_PYTHON=$py, which has the modules ($modules)."
			return 0
		fi
		echo "Made $root/venv from $py ($("$py" -V 2>&1)), which has the modules this plugin needs ($modules): the plugins there run with it."
	elif [ -n "$newest" ] && offer "$plugin needs $modules, which no Python here has${note:+ ($note)}. Make a virtualenv at $root/venv with $newest, and install them from PyPI?"; then
		PYTHON=$newest "$ROOT/install.sh" "$target" || exit 1
	else
		echo "No virtualenv at $root/venv, and no Python with the modules this plugin needs ($modules): ./install.sh $target${newest:+ PYTHON=$newest} makes one and installs them; without it, the python3 on PATH must have them."
	fi
}

# venv ROOT -- a virtualenv at ROOT/venv, beside the plugins installed in
# ROOT, with the modules of each, from the requirements.txt installed with
# it: what every launcher runs with when XYMONAPI_PYTHON names no other. Run
# again, it adds the modules of a plugin installed since.
venv() {
	[ -z "$DESTDIR" ] || die "a virtualenv is made on the installed system, not under DESTDIR: run this there, without DESTDIR"
	[ -d "$1" ] || die "nothing is installed in $1 yet"
	if [ ! -x "$1/venv/bin/python3" ]; then
		"$PYTHON" -m venv "$1/venv" || exit 1
		[ -x "$1/venv/bin/python3" ] || die "$PYTHON made no virtualenv at $1/venv"
	fi
	for r in "$1"/*/requirements.txt; do
		[ -e "$r" ] || continue
		echo "installing the modules of $r"
		"$1/venv/bin/python3" -m pip install -q -r "$r" || exit 1
	done
	echo "The plugins in $1 run with $1/venv/bin/python3 ($("$1/venv/bin/python3" -V))."
}

DONE=
install_server() {
	case " $DONE " in *" $1 "*) return 0 ;; esac
	for n in $(field "$1" needs); do known "$n"; install_server "$n"; done
	[ -n "$(field "$1" server-files)" ] || die "$1 has nothing to install on the server"
	ext=$EXTROOT/$1
	# A link in the plugin directory's place is not the plugin's: removed,
	# as fresh would, before anything is read or moved through it.
	if [ -L "$ext" ]; then rm -f "$ext" || exit 1; fi
	# What the install in place put outside its directory, by its record,
	# for what this one no longer does.
	was_manual=$(held "$EXTROOT" "$1" server-manual)
	was_task=$(held "$EXTROOT" "$1" task)
	was_selinux=$(held "$EXTROOT" "$1" selinux)
	# Refused before anything is replaced, not halfway through.
	[ -z "$(field "$1" task)" ] || ours "$1"
	# The task file an admin may have enabled, and the web server snippets
	# an admin may have edited, outlive the directory.
	# A link where one is set aside would take it elsewhere: removed first.
	if [ -L "$EXTROOT/.$1.tasks.cfg" ]; then rm -f "$EXTROOT/.$1.tasks.cfg" || exit 1; fi
	if [ -f "$ext/tasks.cfg" ]; then mv "$ext/tasks.cfg" "$EXTROOT/.$1.tasks.cfg" || exit 1; fi
	for c in $(field "$1" conf); do
		if [ -L "$EXTROOT/.$1.$c" ]; then rm -f "$EXTROOT/.$1.$c" || exit 1; fi
		if [ -f "$ext/$c" ]; then mv "$ext/$c" "$EXTROOT/.$1.$c" || exit 1; fi
	done
	fresh "$ext" || exit 1
	copy "$1" server "$ext"
	version "$1" "$ext"
	record "$1" "$ext"
	dist "$1"
	[ "$was_manual" = "$(field "$1" server-manual)" ] || drop_manual "$was_manual" "$MANDIR" "$XYMONHOME/ext/$1" ""
	manual "$1" "$(field "$1" server-manual)" "$ext" "$MANDIR" "$XYMONHOME/ext/$1"
	[ -z "$was_task" ] || [ -n "$(field "$1" task)" ] || drop_task "$1"
	task "$1"
	conf "$1"
	say "$1" installed
	restart "$1"
	# A module the installed version loaded and this one has not goes.
	if [ -n "$was_selinux" ] && [ -z "$(field "$1" selinux)" ] && [ -z "$DESTDIR" ] && command -v semodule >/dev/null 2>&1; then
		semodule -r "$1" >/dev/null 2>&1 || :
	fi
	selinux "$1"
	venv_auto "$1" "$EXTROOT" "$(field "$1" server-modules)" venv-server ""
	DONE="$DONE $1"
}

install_tools() {
	case " $DONE " in *" $1 "*) return 0 ;; esac
	for n in $(field "$1" needs); do known "$n"; install_tools "$n"; done
	[ -n "$(field "$1" tools-files)" ] || die "$1 has nothing to install on your own machine"
	dir=$TOOLSROOT/$1
	if [ -L "$dir" ]; then rm -f "$dir" || exit 1; fi
	was_manual=$(held "$TOOLSROOT" "$1" tools-manual)
	was_command=$(held "$TOOLSROOT" "$1" command)
	fresh "$dir" || exit 1
	mkdir -p "$BIN" "$TOOLSMAN1"
	copy "$1" tools "$dir"
	version "$1" "$dir"
	record "$1" "$dir"
	set -f
	# shellcheck disable=SC2086
	[ "$was_command" = "$(field "$1" command)" ] || drop_command "$1" $was_command
	set +f
	[ "$was_manual" = "$(field "$1" tools-manual)" ] \
		|| drop_manual "$was_manual" "$PREFIX/share/man" "$PREFIX/libexec/xymon-plugins/$1" ""
	set -- "$1" $(field "$1" command)
	if [ $# -eq 3 ]; then
		rm -f "$BIN/$2" || exit 1
		wrapper "$1" "$3" > "$BIN/$2"
		chmod 755 "$BIN/$2"
	fi
	manual "$1" "$(field "$1" tools-manual)" "$dir" "$PREFIX/share/man" "$PREFIX/libexec/xymon-plugins/$1"
	venv_auto "$1" "$TOOLSROOT" "$(field "$1" tools-modules)" venv-tools "$(field "$1" venv-note)"
	DONE="$DONE $1"
}

# needed PLUGIN DIR -- refuse to remove the plugin while one installed in DIR
# needs it beside it: removing it would leave that one broken.
needed() {
	for p in "$2"/*; do
		[ -d "$p" ] || continue
		case " $(held "$2" "${p##*/}" needs) " in
			*" $1 "*) die "$1 is needed by ${p##*/}, installed in $2: uninstall ${p##*/} first" ;;
		esac
	done
	return 0
}

# record PLUGIN DIR -- keep the plugin's PLUGIN file in DIR, its installed
# directory, as the record held reads.
record() {
	cp -f "$ROOT/plugins/$1/PLUGIN" "$2/PLUGIN" && chmod 644 "$2/PLUGIN" || exit 1
}

# drop_manual NAME MANROOT FINAL LEGACY -- remove the manual page NAME from
# its section under MANROOT, without DESTDIR, when it is the link an install made into FINAL,
# the plugin's directory as installed; or, for an install from before the
# record, LEGACY set, the page copied there, its name the checkout's.
drop_manual() {
	[ -n "$1" ] && plain "$1" || return 0
	m=$(inside "$2/man${1##*.}") || exit 1
	m=$m/$1
	if [ -L "$m" ]; then
		[ "$(readlink "$m")" = "$3/$1" ] && rm -f "$m"
	elif [ -n "$4" ]; then
		rm -f "$m"
	fi
	return 0
}

# wrapper PLUGIN SCRIPT -- the command an install writes in $BIN: it runs
# the script from where it is installed, PREFIX as given, without DESTDIR.
wrapper() {
	printf '#!/bin/sh\nexec "%s/libexec/xymon-plugins/%s/%s" "$@"\n' "$PREFIX" "$1" "$2"
}

# drop_command PLUGIN NAME SCRIPT -- remove $BIN/NAME when it is, byte for
# byte, the command an install of PLUGIN wrote for SCRIPT, and not a
# command of someone else's, a wrapper of their own among them.
drop_command() {
	[ -n "$2" ] && plain "$2" && plain "$3" && [ -f "$BIN/$2" ] && [ ! -L "$BIN/$2" ] || return 0
	# The x keeps the trailing newlines a command substitution drops.
	[ "$(cat "$BIN/$2"; echo x)" = "$(wrapper "$1" "$3"; echo x)" ] && rm -f "$BIN/$2"
	return 0
}

# drop_task PLUGIN -- remove tasks.d/PLUGIN: the link to the plugin's task
# file, or the file there, a copy an older install made or the task an
# editor left in the link's place; never a link to something else. And the
# task file an install set aside.
drop_task() {
	if [ -L "$TASKDIR/$1" ]; then
		[ "$(readlink "$TASKDIR/$1")" = "$XYMONHOME/ext/$1/tasks.cfg" ] && rm -f "$TASKDIR/$1"
	else
		rm -f "$TASKDIR/$1"
	fi
	rm -f "$EXTROOT/.$1.tasks.cfg"
}

# with_installed ROOT -- LIST, and the plugins installed under ROOT with a
# record the checkout no longer has, for an action given no names.
with_installed() {
	echo $LIST
	for d in "$1"/*; do
		[ -f "$d/PLUGIN" ] && [ ! -L "$d/PLUGIN" ] || continue
		n=${d##*/}
		plain "$n" || continue
		case " $(echo $LIST) " in *" $n "*) ;; *) echo "$n" ;; esac
	done
}

uninstall_server() {
	needed "$1" "$EXTROOT"
	needed "$1" "$DIST/plugins"
	m=$(held "$EXTROOT" "$1" server-manual)
	t=$(held "$EXTROOT" "$1" task)
	se=$(held "$EXTROOT" "$1" selinux)
	legacy=; [ -f "$EXTROOT/$1/PLUGIN" ] || legacy=1
	rm -rf "$EXTROOT/$1" "$DIST/plugins/$1"
	drop_manual "$m" "$MANDIR" "$XYMONHOME/ext/$1" "$legacy"
	[ -z "$t" ] || drop_task "$1"
	# Its SELinux module, the one named after it (S23).
	if [ -n "$se" ] && [ -z "$DESTDIR" ] && command -v semodule >/dev/null 2>&1; then
		semodule -r "$1" >/dev/null 2>&1 || :
	fi
	if [ -f "$ROOT/plugins/$1/PLUGIN" ]; then say "$1" uninstalled; else echo "Uninstalled $1."; fi
}

uninstall_tools() {
	needed "$1" "$TOOLSROOT"
	c=$(held "$TOOLSROOT" "$1" command)
	m=$(held "$TOOLSROOT" "$1" tools-manual)
	legacy=; [ -f "$TOOLSROOT/$1/PLUGIN" ] || legacy=1
	rm -rf "$TOOLSROOT/$1"
	set -f
	# shellcheck disable=SC2086
	drop_command "$1" $c
	set +f
	drop_manual "$m" "$PREFIX/share/man" "$PREFIX/libexec/xymon-plugins/$1" "$legacy"
	if [ -f "$ROOT/plugins/$1/PLUGIN" ]; then say "$1" uninstalled-tools; else echo "Uninstalled $1."; fi
}

case $ACTION in
	install-client|uninstall-client|venv-client)
		die "$ACTION is now ${ACTION%-client}-tools: the plugins' commands, on your own machine. A client, here, is Xymon's, on a monitored host, and nothing installs one yet." ;;
	install|uninstall|venv|status)
		die "$ACTION names no side: $ACTION-server on the Xymon server, $ACTION-tools on your own machine" ;;
	enable|disable)
		die "$ACTION names no side: $ACTION-server, on the Xymon server" ;;
esac

# The plugins named, each checked, or every plugin; for an uninstall, the
# deepest first, so that none is removed while one installed needs it.
for n in $NAMES; do known "$n"; done
if [ -n "$NAMES" ]; then LIST=$NAMES; else LIST=$(all_plugins); fi
deepest_first() {
	for n in $LIST; do echo "$(depth "$n" "$1") $n"; done | sort -rn | cut -d' ' -f2
}

case $ACTION in
	install-server)
		need_home
		for n in $LIST; do xymon_ok "$n"; done
		reads_d
		for n in $LIST; do install_server "$n"; done ;;
	install-tools)
		for n in $LIST; do install_tools "$n"; done ;;
	enable-server)
		need_home
		[ -n "$NAMES" ] || LIST=$(with_installed "$EXTROOT")
		for n in $(installed_tasks); do enable "$n"; done ;;
	disable-server)
		need_home
		[ -n "$NAMES" ] || LIST=$(with_installed "$EXTROOT")
		for n in $(installed_tasks); do disable "$n"; done ;;
	status-server)
		need_home
		[ -n "$NAMES" ] || LIST=$(with_installed "$EXTROOT")
		for n in $LIST; do status server "$EXTROOT" "$n"; done ;;
	status-tools)
		[ -n "$NAMES" ] || LIST=$(with_installed "$TOOLSROOT")
		for n in $LIST; do status tools "$TOOLSROOT" "$n"; done ;;
	uninstall-server)
		need_home
		# The stage served at /plugins, pruned first, as an install does:
		# a link there would take the removal elsewhere.
		prune_dist
		[ -n "$NAMES" ] || LIST=$(with_installed "$EXTROOT")
		for n in $(deepest_first "$EXTROOT"); do uninstall_server "$n"; done
		[ -n "$NAMES" ] || rm -rf "$EXTROOT/venv" ;;
	uninstall-tools)
		[ -n "$NAMES" ] || LIST=$(with_installed "$TOOLSROOT")
		for n in $(deepest_first "$TOOLSROOT"); do uninstall_tools "$n"; done
		if [ -z "$NAMES" ]; then
			rm -rf "$TOOLSROOT/venv"
			rmdir "$TOOLSROOT" 2>/dev/null || true
		fi ;;
	venv-server)
		need_home
		venv "$EXTROOT" ;;
	venv-tools)
		venv "$TOOLSROOT" ;;
	*) usage ;;
esac
