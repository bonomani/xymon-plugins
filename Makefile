# SPDX-License-Identifier: GPL-2.0-or-later
# Install every plugin for one side at once. Each plugin has a Makefile of
# its own under plugins/, with the same targets, for installing it alone;
# build/plugin.mk says where they go and what the variables mean.
#
#   make install XYMONHOME=/usr/lib/xymon/server   on the Xymon server
#   make install-client [PREFIX=$HOME/.local]      where no Xymon is
#   make venv XYMONHOME=... [PYTHON=python3.x]    an isolated Python with their modules
#   make venv-client [PREFIX=...] [PYTHON=...]     the same, where no Xymon is
#   make uninstall XYMONHOME=..., make uninstall-client [PREFIX=...]
#   make test                                      every test, with XYMON_SRC set
#
# A plugin that needs another installs it first, so the lists name only the
# ends: xymonapi-mcp and xymonapi-rag bring xymonapi with them, its client
# on a laptop, the API on the server. The MCP server runs on a laptop; the
# server only stages it, for laptops to install from its /plugins.

SERVER = xymonapi-mcp xymonapi-rag
CLIENT = xymonapi-mcp xymonapi-rag

all:

install:
	@test -n "$(XYMONHOME)" || { echo "usage: make install XYMONHOME=<the Xymon server directory>" >&2; exit 1; }
	@for p in $(SERVER); do $(MAKE) -C "plugins/$$p" install || exit 1; done

install-client:
	@for p in $(CLIENT); do $(MAKE) -C "plugins/$$p" install-client || exit 1; done

# The virtualenv beside the installed plugins, which the launchers prefer to
# the python3 on PATH: one per side, so one plugin's Makefile makes it.
venv:
	@test -n "$(XYMONHOME)" || { echo "usage: make venv XYMONHOME=<the Xymon server directory> [PYTHON=python3.x]" >&2; exit 1; }
	@$(MAKE) -C plugins/xymonapi venv

venv-client:
	@$(MAKE) -C plugins/xymonapi venv-client

# Every plugin of a side, those that need another first, and the virtualenv
# beside them.
uninstall:
	@test -n "$(XYMONHOME)" || { echo "usage: make uninstall XYMONHOME=<the Xymon server directory>" >&2; exit 1; }
	@for p in xymonapi-rag xymonapi-mcp xymonapi; do $(MAKE) -C "plugins/$$p" uninstall || exit 1; done
	rm -rf "$(DESTDIR)$(XYMONHOME)/ext/venv"

uninstall-client:
	@for p in xymonapi-rag xymonapi-mcp xymonapi; do $(MAKE) -C "plugins/$$p" uninstall-client || exit 1; done
	rm -rf "$(DESTDIR)$(or $(PREFIX),$(HOME)/.local)/libexec/xymon-plugins/venv"
	-rmdir "$(DESTDIR)$(or $(PREFIX),$(HOME)/.local)/libexec/xymon-plugins" 2>/dev/null

# Every plugin's tests, then those of how they fit together.
test:
	tests/run.sh

.PHONY: all install install-client venv venv-client uninstall uninstall-client test
