# SPDX-License-Identifier: GPL-2.0-or-later
# Install every plugin for one side at once. Each plugin has a Makefile of
# its own under plugins/, with the same targets, for installing it alone;
# build/plugin.mk says where they go and what the variables mean.
#
#   make install XYMONHOME=/usr/lib/xymon/server   on the Xymon server
#   make install-client [PREFIX=$HOME/.local]      where no Xymon is
#
# A plugin that needs another installs it first, so the lists name only the
# ends: xymonapi-rag brings xymonapi-mcp with it on either side.

SERVER = xymonapi xymonapi-rag
CLIENT = xymonapi-rag

all:

install:
	@test -n "$(XYMONHOME)" || { echo "usage: make install XYMONHOME=<the Xymon server directory>" >&2; exit 1; }
	@for p in $(SERVER); do $(MAKE) -C "plugins/$$p" install || exit 1; done

install-client:
	@for p in $(CLIENT); do $(MAKE) -C "plugins/$$p" install-client || exit 1; done

.PHONY: all install install-client
