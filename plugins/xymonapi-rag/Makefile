# SPDX-License-Identifier: GPL-2.0-or-later
# The search over Xymon's manual pages and history, xymonapi-rag(1).
#
#   make install XYMONHOME=...                  the index task, on the server
#   make install-client [PREFIX=$HOME/.local]   search and ask, elsewhere
#
# It reads the API through xymonapi-mcp's client.py, beside it, so either
# target installs that plugin first; on the server it also reads the history
# through xymonapi's xymon.py, which make install of that plugin puts there.

PLUGIN = xymonapi-rag
include ../../build/plugin.mk

FILES = xymonrag.py xymonapi-rag.sh requirements.txt

all:

install:
	$(need_home)
	$(MAKE) -C ../xymonapi install
	$(MAKE) -C ../xymonapi-mcp install
	$(call fresh,$(EXT))
	cp -f $(FILES) "$(EXT)/"
	chmod 644 "$(EXT)/xymonrag.py" "$(EXT)/requirements.txt"
	chmod 755 "$(EXT)/xymonapi-rag.sh"
	$(call version,$(EXT))
	mkdir -p "$(MAN1)"
	cp -f xymonapi-rag.1 "$(MAN1)/"
	chmod 644 "$(MAN1)/xymonapi-rag.1"
	mkdir -p "$(TASKDIR)"
	$(call task,xymonapi-rag.tasks.DIST,xymonapi-rag)

install-client:
	$(MAKE) -C ../xymonapi-mcp install-client
	$(call fresh,$(CLIENT))
	mkdir -p "$(BIN)" "$(CLIENTMAN1)"
	cp -f $(FILES) "$(CLIENT)/"
	chmod 644 "$(CLIENT)/xymonrag.py" "$(CLIENT)/requirements.txt"
	chmod 755 "$(CLIENT)/xymonapi-rag.sh"
	$(call version,$(CLIENT))
	$(call launcher,xymonapi-rag,xymonapi-rag/xymonapi-rag.sh)
	cp -f xymonapi-rag.1 "$(CLIENTMAN1)/"
	chmod 644 "$(CLIENTMAN1)/xymonapi-rag.1"

.PHONY: all install install-client
