# SPDX-License-Identifier: GPL-2.0-or-later
# The agent command over the Xymon API, xymonapi-agent(1).
#
#   make install XYMONHOME=...                  on the server, for the API's /ask
#   make install-client [PREFIX=$HOME/.local]   where an agent CLI runs
#
# It runs an agent CLI with xymonapi-mcp, beside it, as the agent's only
# tool, so either target installs that plugin first, and xymonapi's client
# with it. On the server the API's /ask runs it, as the Xymon user, which
# must have the agent CLI installed and logged in; install there also stages
# it, for the machines that install from the server's /plugins.

PLUGIN = xymonapi-agent
include ../../build/plugin.mk

FILES = xymonagent.py xymonapi-agent.sh

all:

install:
	$(need_home)
	$(MAKE) -C ../xymonapi-mcp install
	$(call fresh,$(EXT))
	cp -f $(FILES) "$(EXT)/"
	chmod 644 "$(EXT)/xymonagent.py"
	chmod 755 "$(EXT)/xymonapi-agent.sh"
	$(call version,$(EXT))
	$(dist)
	mkdir -p "$(MAN1)"
	cp -f xymonapi-agent.1 "$(MAN1)/"
	chmod 644 "$(MAN1)/xymonapi-agent.1"
	@echo "Installed xymonapi-agent beside the API. For /ask: set XYMONAPI_ASK=1 in a file under xymonserver.d/,"
	@echo "  and as the Xymon user install and log in to claude, codex or opencode, then run xymonapi-agent doctor: see xymonapi(8), /ask."

install-client:
	$(MAKE) -C ../xymonapi-mcp install-client
	$(call fresh,$(CLIENT))
	mkdir -p "$(BIN)" "$(CLIENTMAN1)"
	cp -f $(FILES) "$(CLIENT)/"
	chmod 644 "$(CLIENT)/xymonagent.py"
	chmod 755 "$(CLIENT)/xymonapi-agent.sh"
	$(call version,$(CLIENT))
	$(call launcher,xymonapi-agent,xymonapi-agent/xymonapi-agent.sh)
	cp -f xymonapi-agent.1 "$(CLIENTMAN1)/"
	chmod 644 "$(CLIENTMAN1)/xymonapi-agent.1"

# An isolated Python for the plugins installed here, with their modules;
# this one needs none.
venv:
	$(need_home)
	$(call venv,$(EXTROOT))

venv-client:
	$(call venv,$(CLIENTROOT))

uninstall:
	$(need_home)
	$(call gone,$(EXT))
	$(call gone,$(DIST)/plugins/$(PLUGIN))
	rm -f "$(MAN1)/xymonapi-agent.1"
	@echo "Uninstalled xymonapi-agent. Kept: xymonapi-mcp and xymonapi."

uninstall-client:
	$(call gone,$(CLIENT))
	rm -f "$(BIN)/xymonapi-agent" "$(CLIENTMAN1)/xymonapi-agent.1"
	@echo "Uninstalled xymonapi-agent. Kept: xymonapi-mcp, xymonapi's client, and its sessions under \$$XDG_STATE_HOME/xymonapi-agent."

.PHONY: all install install-client venv venv-client uninstall uninstall-client test
