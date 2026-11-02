# SPDX-License-Identifier: GPL-2.0-or-later
# The Xymon API, xymonapi(8), and xymonapi_client.py, its client.
#
#   make install XYMONHOME=/usr/lib/xymon/server   the API, on the server
#   make install-client [PREFIX=$HOME/.local]      its client alone, elsewhere
#
# It needs nothing else to run; xymonapi-rag beside it is what /search
# serves, when that plugin is installed too.

PLUGIN = xymonapi
include ../../build/plugin.mk

FILES = app.py xymon.py xymonapi_client.py clientsetup.py tokens.py openapi.yaml requirements.txt xymonapi.sh

all:

install:
	$(need_home)
	$(call fresh,$(EXT))
	cp -f $(FILES) "$(EXT)/"
	chmod 644 "$(EXT)/app.py" "$(EXT)/xymon.py" "$(EXT)/xymonapi_client.py" "$(EXT)/clientsetup.py" "$(EXT)/tokens.py" "$(EXT)/openapi.yaml" "$(EXT)/requirements.txt"
	chmod 755 "$(EXT)/xymonapi.sh"
	$(call version,$(EXT))
	mkdir -p "$(MAN8)"
	cp -f xymonapi.8 "$(MAN8)/"
	chmod 644 "$(MAN8)/xymonapi.8"
	mkdir -p "$(TASKDIR)"
	$(call task,xymonapi.tasks.DIST,xymonapi)
	$(call conf,xymonapi-apache.conf)
	$(call conf,xymonapi-nginx.conf)
	$(call conf,xymonapi-lighttpd.conf)
	@echo "Installed. Enable the API: remove DISABLED from $(TASKDIR)/xymonapi. For other machines, include one of"
	@echo "  $(ETC)/xymonapi-{apache,nginx,lighttpd}.conf in the web server, or give the API xymond's certificate: see xymonapi(8)."
	@echo "Updating one that runs: it keeps the old code until restarted. Stop it, and xymonlaunch starts the new:"
	@echo "  pkill -f '$(XYMONHOME)/ext/xymonapi/'"

# The client alone, for the plugins that read the API from elsewhere.
install-client:
	$(call fresh,$(CLIENT))
	cp -f xymonapi_client.py "$(CLIENT)/"
	chmod 644 "$(CLIENT)/xymonapi_client.py"
	$(call version,$(CLIENT))

# What it removes, and what it keeps: the web server's configuration may
# include a snippet, and the tokens file is data.
uninstall:
	$(need_home)
	$(call needed_by,$(EXTROOT),xymonapi-mcp xymonapi-rag)
	$(call gone,$(EXT))
	rm -f "$(MAN8)/xymonapi.8" "$(TASKDIR)/xymonapi"
	@echo "Uninstalled xymonapi. Kept, for you to remove: $(ETC)/xymonapi-{apache,nginx,lighttpd}.conf --"
	@echo "  take its Include out of the web server first -- and the tokens file, \$$XYMONAPI_TOKENS"
	@echo "  (\$$XYMONVAR/xymonapi/tokens by default)."

uninstall-client:
	$(call needed_by,$(CLIENTROOT),xymonapi-mcp xymonapi-rag)
	$(call gone,$(CLIENT))
	@echo "Uninstalled xymonapi's client."

.PHONY: all install install-client uninstall uninstall-client test
