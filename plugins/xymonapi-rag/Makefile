# SPDX-License-Identifier: GPL-2.0-or-later
# The search over Xymon's manual pages and history, xymonapi-rag(1).
#
#   make install XYMONHOME=...                  the index task, on the server
#   make install-client [PREFIX=$HOME/.local]   search and ask, elsewhere
#
# It reads the API through xymonapi's client, beside it, so either target
# installs that plugin first: on the server the API too, whose xymon.py it
# also reads the history through.

PLUGIN = xymonapi-rag
include ../../build/plugin.mk

FILES = xymonrag.py xymonapi-rag.sh requirements.txt

all:

install:
	$(need_home)
	$(MAKE) -C ../xymonapi install
	$(call fresh,$(EXT))
	cp -f $(FILES) "$(EXT)/"
	chmod 644 "$(EXT)/xymonrag.py" "$(EXT)/requirements.txt"
	chmod 755 "$(EXT)/xymonapi-rag.sh"
	$(call version,$(EXT))
	$(dist)
	mkdir -p "$(MAN1)"
	cp -f xymonapi-rag.1 "$(MAN1)/"
	chmod 644 "$(MAN1)/xymonapi-rag.1"
	mkdir -p "$(TASKDIR)"
	$(call task,xymonapi-rag.tasks.DIST,xymonapi-rag)

install-client:
	$(MAKE) -C ../xymonapi install-client
	$(call fresh,$(CLIENT))
	mkdir -p "$(BIN)" "$(CLIENTMAN1)"
	cp -f $(FILES) "$(CLIENT)/"
	chmod 644 "$(CLIENT)/xymonrag.py" "$(CLIENT)/requirements.txt"
	chmod 755 "$(CLIENT)/xymonapi-rag.sh"
	$(call version,$(CLIENT))
	$(call launcher,xymonapi-rag,xymonapi-rag/xymonapi-rag.sh)
	cp -f xymonapi-rag.1 "$(CLIENTMAN1)/"
	chmod 644 "$(CLIENTMAN1)/xymonapi-rag.1"

# It removes itself alone: the plugins it brought may serve others.
uninstall:
	$(need_home)
	$(call gone,$(EXT))
	$(call gone,$(DIST)/plugins/$(PLUGIN))
	rm -f "$(MAN1)/xymonapi-rag.1" "$(TASKDIR)/xymonapi-rag"
	@echo "Uninstalled xymonapi-rag. Kept: its index, \$$XYMONAPI_RAG_INDEX, and xymonapi."

uninstall-client:
	$(call gone,$(CLIENT))
	rm -f "$(BIN)/xymonapi-rag" "$(CLIENTMAN1)/xymonapi-rag.1"
	@echo "Uninstalled xymonapi-rag. Kept: xymonapi's client, and any index here, \$$XYMONAPI_RAG_INDEX."

.PHONY: all install install-client uninstall uninstall-client test
