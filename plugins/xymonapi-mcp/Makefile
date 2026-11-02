# SPDX-License-Identifier: GPL-2.0-or-later
# The MCP server for the Xymon API, xymonapi-mcp(1), and client.py, the
# module every plugin reads the API through.
#
#   make install-client [PREFIX=$HOME/.local]   where the AI client runs
#   make install XYMONHOME=...                  on the server, for xymonapi-rag
#
# It needs a running xymonapi(8), here or elsewhere, and nothing of this
# tree beside it.

PLUGIN = xymonapi-mcp
include ../../build/plugin.mk

FILES = server.py client.py xymonapi-mcp.sh requirements.txt

all:

install:
	$(need_home)
	$(call fresh,$(EXT))
	cp -f $(FILES) "$(EXT)/"
	chmod 644 "$(EXT)/server.py" "$(EXT)/client.py" "$(EXT)/requirements.txt"
	chmod 755 "$(EXT)/xymonapi-mcp.sh"
	$(call version,$(EXT))

install-client:
	$(call fresh,$(CLIENT))
	mkdir -p "$(BIN)" "$(CLIENTMAN1)"
	cp -f $(FILES) "$(CLIENT)/"
	chmod 644 "$(CLIENT)/server.py" "$(CLIENT)/client.py" "$(CLIENT)/requirements.txt"
	chmod 755 "$(CLIENT)/xymonapi-mcp.sh"
	$(call version,$(CLIENT))
	$(call launcher,xymonapi-mcp,xymonapi-mcp/xymonapi-mcp.sh)
	cp -f xymonapi-mcp.1 "$(CLIENTMAN1)/"
	chmod 644 "$(CLIENTMAN1)/xymonapi-mcp.1"

uninstall:
	$(need_home)
	$(call needed_by,$(EXTROOT),xymonapi-rag)
	$(call gone,$(EXT))
	@echo "Uninstalled xymonapi-mcp."

# The setup script also registered the server with the AI clients and kept a
# token: said, not done, since they are this user's and the server's.
uninstall-client:
	$(call needed_by,$(CLIENTROOT),xymonapi-rag)
	$(call gone,$(CLIENT))
	rm -f "$(BIN)/xymonapi-mcp" "$(CLIENTMAN1)/xymonapi-mcp.1"
	@echo "Uninstalled xymonapi-mcp. What the setup script did besides, to undo by hand:"
	@echo "  claude mcp remove --scope user xymon; codex mcp remove xymon"
	@echo "  revoke this machine's token: curl -X DELETE -u USER https://SERVER/xymon/api/v1/tokens/\$$(hostname -s)"
	@echo "  rm ~/.config/xymon-api/xymon.token"

.PHONY: all install install-client uninstall uninstall-client
