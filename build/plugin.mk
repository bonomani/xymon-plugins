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
# the same way, with a command per plugin in $PREFIX/bin. Each plugin records
# its own version beside its files, in VERSION, and the virtualenv they share
# sits beside them, as venv/.
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
# The Python make venv makes the virtualenv with: 3.9 or later. Given on the
# command line, it is also the one an install makes the virtualenv from
# (venv_auto), in place of the search there.
PYTHON = python3
# Where an install looks for a Python beyond PATH: Homebrew's and pyenv's.
PYTHON_DIRS = /opt/homebrew/bin /usr/local/bin /opt/homebrew/opt/python@3.*/bin $(HOME)/.pyenv/versions/*/bin
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
# What other machines install from, which the API serves at /plugins: each
# plugin installed on the server stages its directory here, as in the
# repository, beside build/ and the top Makefile.
DIST = $(EXTROOT)/xymon-plugins-client

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

# venv DIR -- a virtualenv at DIR/venv, beside the plugins installed in DIR,
# with the modules of each, from the requirements.txt installed with it: what
# every launcher runs with when XYMONAPI_PYTHON names no other, in place of
# the python3 on PATH, which may lack them. Run again, it adds the modules
# of a plugin installed since.
define venv
	@test -d "$(1)" || { echo "nothing is installed in $(1) yet" >&2; exit 1; }
	@[ -x "$(1)/venv/bin/python3" ] || "$(PYTHON)" -m venv "$(1)/venv" || exit 1
	@for r in "$(1)"/*/requirements.txt; do \
		[ -e "$$r" ] || continue; \
		echo "installing the modules of $$r"; \
		"$(1)/venv/bin/python3" -m pip install -q -r "$$r" || exit 1; \
	done
	@echo "The plugins in $(1) run with $(1)/venv/bin/python3 (`"$(1)/venv/bin/python3" -V`)."
endef

# venv_auto DIR TARGET -- the last step of installing a plugin that needs
# the modules MODULES names (their import names), and downloads nothing
# unless asked. With no
# virtualenv at DIR/venv yet: the newest Python 3.9 or later on this machine
# that has them already -- PYTHON when given on the command line, else
# python3.14 down to python3.9 and python3, on PATH and in PYTHON_DIRS -- is
# made the virtualenv's, with --system-site-packages, so that it is only
# pinned beside the plugins and nothing is copied or fetched; with no such
# Python, the hint says which make venv would use. A candidate is named by
# the interpreter it runs (sys.executable), not a shim or symlink found on
# PATH, so the message and the hint say what the virtualenv records. With a
# virtualenv there, the modules it lacks are named, for make venv to install.
# Where the install runs on a terminal, the hint is instead an offer: on
# "y", make TARGET -- venv or venv-client -- installs the modules from PyPI
# there and then; anything else leaves the hint. Without a terminal -- a
# package build, CI -- nothing is asked. VENV_NOTE, set by a plugin for its
# client side, says in the offer what the modules are for there.
PYTHON_GIVEN = $(if $(filter command line environment,$(origin PYTHON)),$(PYTHON))
define venv_auto
	@offer() { [ -t 0 ] && [ -t 1 ] || return 1; printf '%s [y/N] ' "$$1"; read -r yn; case $$yn in [yY]*) return 0 ;; esac; return 1; }; \
	note='$(if $(filter venv-client,$(2)),$(VENV_NOTE))'; \
	if [ -x "$(1)/venv/bin/python3" ]; then \
		missing=`"$(1)/venv/bin/python3" -c 'import importlib.util as u, sys; print(" ".join(m for m in sys.argv[1:] if u.find_spec(m) is None))' $(MODULES)`; \
		[ -z "$$missing" ] && exit 0; \
		if offer "The virtualenv $(1)/venv lacks $$missing, which $(PLUGIN) needs$${note:+ ($$note)}. Install them into it, from PyPI?"; then \
			$(MAKE) --no-print-directory $(2) || exit 1; \
		else \
			echo "The virtualenv $(1)/venv lacks $$missing, which this plugin needs: make venv (venv-client elsewhere) installs them."; \
		fi; \
	else \
		py=""; newest=""; \
		for c in $(if $(PYTHON_GIVEN),$(PYTHON_GIVEN),python3.14 python3.13 python3.12 python3.11 python3.10 python3.9 python3); do \
			for d in "" $(PYTHON_DIRS); do \
				case $$c in /*) p=$$c ;; *) if [ -n "$$d" ]; then p=$$d/$$c; else p=`command -v "$$c" 2>/dev/null`; fi ;; esac; \
				[ -n "$$p" ] && [ -x "$$p" ] || continue; \
				"$$p" -c 'import sys; sys.exit(sys.version_info < (3, 9))' 2>/dev/null || continue; \
				real=`"$$p" -c 'import sys; print(sys.executable)' 2>/dev/null`; [ -n "$$real" ] && [ -x "$$real" ] && p=$$real; \
				[ -n "$$newest" ] || newest=$$p; \
				"$$p" -c 'import importlib.util as u, sys; sys.exit(any(u.find_spec(m) is None for m in sys.argv[1:]))' $(MODULES) 2>/dev/null || continue; \
				py=$$p; break 2; \
			done; \
		done; \
		if [ -n "$$py" ]; then \
			"$$py" -m venv --system-site-packages "$(1)/venv" || exit 1; \
			echo "Made $(1)/venv from $$py (`"$$py" -V 2>&1`), which has the modules this plugin needs ($(MODULES)): the plugins there run with it."; \
		elif [ -n "$$newest" ] && offer "$(PLUGIN) needs $(MODULES), which no Python here has$${note:+ ($$note)}. Make a virtualenv at $(1)/venv with $$newest, and install them from PyPI?"; then \
			$(MAKE) --no-print-directory $(2) PYTHON="$$newest" || exit 1; \
		else \
			echo "No virtualenv at $(1)/venv, and no Python with the modules this plugin needs ($(MODULES)): make venv (venv-client elsewhere)$${newest:+ PYTHON=$$newest} makes one and installs them; without it, the python3 on PATH must have them."; \
		fi; \
	fi
endef

# Included at the top of each plugin's Makefile, before its all: so that
# the test target below is not taken for the default.
.DEFAULT_GOAL := all

# test -- this plugin's tests, run from the repository's top, against the
# built Xymon tree XYMON_SRC names. They start the plugins this one needs.
test:
	cd ../.. && tests/run.sh "plugins/$(PLUGIN)/tests"

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

# dist -- stage this plugin's directory under $(DIST)/plugins, as it is in
# the repository but for its tests, with build/plugin.mk, the top Makefile
# and LICENSE beside: a machine unpacking it runs make install-client there,
# at the server's versions. Links are copied as links, as in the repository.
define dist
	@case "$(PLUGIN)" in ""|*/*|.|..) echo "PLUGIN must name one plugin directory" >&2; exit 1 ;; esac
	rm -rf "$(DIST)/plugins/$(PLUGIN)"
	mkdir -p "$(DIST)/plugins" "$(DIST)/build"
	cp -R . "$(DIST)/plugins/$(PLUGIN)"
	rm -rf "$(DIST)/plugins/$(PLUGIN)/tests"
	find "$(DIST)/plugins/$(PLUGIN)" -name __pycache__ -prune -exec rm -rf {} +
	cp -f ../../build/plugin.mk "$(DIST)/build/"
	cp -f ../../Makefile ../../LICENSE "$(DIST)/"
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
