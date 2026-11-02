# SPDX-License-Identifier: GPL-2.0-or-later
# The Xymon API, xymonapi(8): a server-side plugin.
#
#   make install XYMONHOME=/usr/lib/xymon/server
#
# It needs nothing else to run; xymonapi-rag beside it is what /search
# serves, when that plugin is installed too.

PLUGIN = xymonapi
include ../../build/plugin.mk

FILES = app.py xymon.py clientsetup.py tokens.py openapi.yaml requirements.txt xymonapi.sh

all:

install:
	$(need_home)
	$(call fresh,$(EXT))
	cp -f $(FILES) "$(EXT)/"
	chmod 644 "$(EXT)/app.py" "$(EXT)/xymon.py" "$(EXT)/clientsetup.py" "$(EXT)/tokens.py" "$(EXT)/openapi.yaml" "$(EXT)/requirements.txt"
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

.PHONY: all install
