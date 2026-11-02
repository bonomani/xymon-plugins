# SPDX-License-Identifier: GPL-2.0-or-later
# The MCP server for the Xymon API, xymonapi-mcp(1).
#
#   make install-client [PREFIX=$HOME/.local]   where the AI client runs
#   make install XYMONHOME=...                  on the Xymon server, staged
#                                               for other machines, not run
#
# It reads the API through xymonapi's client, beside it, which either target
# installs first; the API itself runs on the server. xymonapi_client.py here
# is a link to that client, for a marketplace install of this directory alone.

PLUGIN = xymonapi-mcp
include ../../build/plugin.mk

FILES = server.py xymonapi-mcp.sh

all:

# Nothing of it runs on the server: it is staged there, for the machines that
# install from the server's /client. The directory an older install put in
# ext/ goes.
install:
	$(need_home)
	$(MAKE) -C ../xymonapi install
	$(call gone,$(EXT))
	$(dist)

install-client:
	$(MAKE) -C ../xymonapi install-client
	$(call fresh,$(CLIENT))
	mkdir -p "$(BIN)" "$(CLIENTMAN1)"
	cp -f $(FILES) "$(CLIENT)/"
	chmod 644 "$(CLIENT)/server.py"
	chmod 755 "$(CLIENT)/xymonapi-mcp.sh"
	$(call version,$(CLIENT))
	$(call launcher,xymonapi-mcp,xymonapi-mcp/xymonapi-mcp.sh)
	cp -f xymonapi-mcp.1 "$(CLIENTMAN1)/"
	chmod 644 "$(CLIENTMAN1)/xymonapi-mcp.1"

# An isolated Python for the plugins installed here, with their modules;
# this one needs none, but xymonapi beside it does on the server.
venv:
	$(need_home)
	$(call venv,$(EXTROOT))

venv-client:
	$(call venv,$(CLIENTROOT))

uninstall:
	$(need_home)
	$(call gone,$(EXT))
	$(call gone,$(DIST)/plugins/$(PLUGIN))
	@echo "Uninstalled xymonapi-mcp. Kept: xymonapi."

# register also registered the server with the AI clients, and kept a token:
# said, not done, since they are this user's and the server's.
uninstall-client:
	$(call gone,$(CLIENT))
	rm -f "$(BIN)/xymonapi-mcp" "$(CLIENTMAN1)/xymonapi-mcp.1"
	@echo "Uninstalled xymonapi-mcp. What register did besides, to undo by hand:"
	@echo "  claude mcp remove --scope user xymon; codex mcp remove xymon"
	@echo "  revoke this machine's token: curl -X DELETE -u USER https://SERVER/xymon/api/v1/tokens/\$$(hostname -s)"
	@echo "  rm ~/.config/xymon-api/xymon.token"

.PHONY: all install install-client venv venv-client uninstall uninstall-client test
