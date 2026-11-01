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
	mkdir -p "$(EXT)"
	cp -f $(FILES) "$(EXT)/"
	chmod 644 "$(EXT)/server.py" "$(EXT)/client.py" "$(EXT)/requirements.txt"
	chmod 755 "$(EXT)/xymonapi-mcp.sh"
	$(call version,$(EXT))

install-client:
	mkdir -p "$(CLIENT)" "$(BIN)" "$(CLIENTMAN1)"
	cp -f $(FILES) "$(CLIENT)/"
	chmod 644 "$(CLIENT)/server.py" "$(CLIENT)/client.py" "$(CLIENT)/requirements.txt"
	chmod 755 "$(CLIENT)/xymonapi-mcp.sh"
	$(call version,$(CLIENT))
	$(call launcher,xymonapi-mcp,xymonapi-mcp/xymonapi-mcp.sh)
	cp -f xymonapi-mcp.1 "$(CLIENTMAN1)/"
	chmod 644 "$(CLIENTMAN1)/xymonapi-mcp.1"

.PHONY: all install install-client
