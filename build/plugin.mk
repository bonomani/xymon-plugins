# SPDX-License-Identifier: GPL-2.0-or-later
# build/plugin.mk -- what every plugin's Makefile includes: where the plugins
# install, and the recipes they share. A plugin's Makefile sets PLUGIN to its
# directory name, then
#
#   include ../../build/plugin.mk
#
# On a Xymon server the plugins go under $XYMONHOME/ext/, one
# directory each, and a plugin that needs another finds it beside itself;
# on a machine with no Xymon they go under $PREFIX/libexec/xymon-plugins/
# the same way, with a command per plugin in $PREFIX/bin. Each plugin records its own version beside its
# files, in VERSION.
#
# XYMONHOME is the server directory, as xymonserver.cfg names it. Xymon's own
# install links $XYMONHOME/ext and $XYMONHOME/etc to wherever those really
# are, so nothing else needs saying. DESTDIR stages the install for a package;
# MANDIR is where a server's manual page goes. Nothing is built: a plugin is
# copied as it is, and needs no Python until it runs.
#
# Every path is quoted in the recipes, and XYMONHOME is escaped before it is
# put into a task file with sed: a directory with a space, an & or a | in
# its name is a directory like any other.

MANDIR = /usr/share/man
PREFIX = $(HOME)/.local
EXTROOT = $(DESTDIR)$(XYMONHOME)/ext
EXT = $(EXTROOT)/$(PLUGIN)
ETC = $(DESTDIR)$(XYMONHOME)/etc
TASKDIR = $(ETC)/tasks.d
MAN1 = $(DESTDIR)$(MANDIR)/man1
MAN8 = $(DESTDIR)$(MANDIR)/man8
CLIENTROOT = $(DESTDIR)$(PREFIX)/libexec/xymon-plugins
CLIENT = $(CLIENTROOT)/$(PLUGIN)
BIN = $(DESTDIR)$(PREFIX)/bin
CLIENTMAN1 = $(DESTDIR)$(PREFIX)/share/man/man1

# need_home -- the first line of a server-side install: without XYMONHOME
# nothing is installed, and the usage says what is missing.
define need_home
	@test -n "$(XYMONHOME)" || { echo "usage: make install XYMONHOME=<the Xymon server directory>" >&2; exit 1; }
endef

# conf FILE -- copy FILE to $XYMONHOME/etc unless it is there already: an
# admin's edits to a web server snippet are kept, as a task file is.
define conf
	@if [ -e "$(ETC)/$(1)" ]; then \
		echo "keeping $(ETC)/$(1)"; \
	else \
		cp "$(1)" "$(ETC)/"; \
		chmod 644 "$(ETC)/$(1)"; \
	fi
endef

# version DIR -- write this plugin's version to DIR/VERSION. Installed from
# a release, the commit this plugin's tag PLUGIN/vX.Y.Z names, it is that
# tag, which git checks out: the API's, which /health gives so a laptop
# fetches the same code. From any other commit, or a tarball, it is the
# version in the PLUGIN file, X.Y.Z, which names no commit.
VERSION = $$(sed -n 's/^version: *//p' PLUGIN)
define version
	@v=$$(git describe --exact-match --tags --match '$(PLUGIN)/v*' 2>/dev/null) || v=$(VERSION); \
	printf '%s\n' "$$v" > "$(1)/VERSION"; chmod 644 "$(1)/VERSION"
endef

# fresh DIR -- DIR, emptied: an install replaces a plugin's directory as a
# whole, so that a file a newer version no longer ships does not stay behind
# to be imported. It holds only what the plugin ships and its VERSION: the
# admin's settings, task files, snippets and data live elsewhere. PLUGIN must
# be one directory name, so that DIR is never ext/ or libexec/ itself.
define fresh
	@case "$(PLUGIN)" in ""|*/*|.|..) echo "PLUGIN must name one plugin directory" >&2; exit 1 ;; esac
	rm -rf "$(1)"
	mkdir -p "$(1)"
endef

# needed_by DIR PLUGINS -- refuse to uninstall this plugin while one of
# PLUGINS, which need it beside them, is installed in DIR: removing it would
# leave that one broken. Uninstall that one first.
define needed_by
	@for p in $(2); do \
		if [ -e "$(1)/$$p" ]; then \
			echo "$(PLUGIN) is needed by $$p, installed in $(1): uninstall $$p first" >&2; exit 1; \
		fi; \
	done
endef

# gone DIR -- remove this plugin's directory, as fresh empties it.
define gone
	@case "$(PLUGIN)" in ""|*/*|.|..) echo "PLUGIN must name one plugin directory" >&2; exit 1 ;; esac
	rm -rf "$(1)"
endef

# task DIST NAME -- write DIST as $(TASKDIR)/NAME, with @XYMONHOME@ replaced,
# unless NAME is there already: the one an admin enabled is not put back to
# DISABLED by the next install. The replacement is escaped for sed first: a
# backslash, an & and the | used as the delimiter would otherwise be read
# as sed syntax.
define task
	if [ -e "$(TASKDIR)/$(2)" ]; then \
		echo "keeping $(TASKDIR)/$(2)"; \
	else \
		home=$$(printf '%s\n' '$(XYMONHOME)' | sed -e 's/[\\&|]/\\&/g'); \
		sed -e "s|@XYMONHOME@|$$home|g" "$(1)" > "$(TASKDIR)/$(2)"; \
		chmod 644 "$(TASKDIR)/$(2)"; \
	fi
endef

# launcher NAME SCRIPT -- $(BIN)/NAME, a command that runs SCRIPT, a path
# under the installed plugins, from where it is: PREFIX as given, quoted.
define launcher
	printf '#!/bin/sh\nexec "%s/libexec/xymon-plugins/$(2)" "$$@"\n' '$(PREFIX)' > "$(BIN)/$(1)"
	chmod 755 "$(BIN)/$(1)"
endef
