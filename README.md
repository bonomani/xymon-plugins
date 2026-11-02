# xymon-plugins

Plugins for the [Xymon](https://github.com/xymon-monitoring/xymon)
monitoring system, one per directory under [`plugins/`](plugins). This
repository was `xymon-api` before it held several, and carries its whole
history.

## The plugins

| plugin | side | what it is | needs |
|---|---|---|---|
| [`xymonapi`](plugins/xymonapi/README.md) | server, client | a read-only HTTP and JSON interface to a Xymon server, as one of its xymonlaunch tasks, and its client | on the server, xymon >= 4.3.31 (main); python >= 3.9 |
| [`xymonapi-mcp`](plugins/xymonapi-mcp/README.md) | client | an MCP server that gives an AI client read-only tools over the Xymon API | xymonapi >= 0.1.0 (its client beside it, the API over the network); python >= 3.9 |
| [`xymonapi-rag`](plugins/xymonapi-rag/README.md) | server, client | a search of Xymon's manual pages and history by meaning; the index task on the server, search and ask anywhere | xymonapi >= 0.1.0 (its client beside it); python >= 3.9 |

Each row summarises the plugin's `PLUGIN` file. Its README says how to
install and use it, its manual page every behaviour and setting.

## What a plugin is

A directory under `plugins/` holding:

- `PLUGIN`: its name, version, side, summary, what it needs, and its manual
  page;
- `Makefile`: installs it alone, and first any plugin it needs;
- `README.md`: installing and using it;
- its manual page, and its code.

## Getting the code

Take the branch `stable`: the newest code every test passed, which CI moves
forward. `main` holds every change as it lands.

```sh
git clone --branch stable https://github.com/bonomani/xymon-plugins   # update later with git pull
curl -L https://github.com/bonomani/xymon-plugins/archive/refs/heads/stable.tar.gz | tar xz
```

or the [zip](https://github.com/bonomani/xymon-plugins/archive/refs/heads/stable.zip).
A clone is the better choice: it updates with `git pull`, and can be asked
how far behind it is.

## Installing

The download holds every plugin; install only those you want, each from its
own directory, as its README says. A plugin's `make install` (on the Xymon
server) or `make install-client` (elsewhere) installs first any plugin it
needs, so one command is enough:

```sh
cd plugins/NAME && make install XYMONHOME=/usr/lib/xymon/server   # on the server
cd plugins/NAME && make install-client                           # elsewhere
```

Run again, it updates the plugin; `make uninstall` or `make uninstall-client`
removes it. The same targets at the top act on every plugin of one side.

The launchers run with the Python `XYMONAPI_PYTHON` names, else with the
virtualenv beside the installed plugins when there is one, else with the
`python3` on PATH, asking first when a person is at the terminal. `make venv`
(on the server) or `make venv-client` makes that virtualenv, with the modules
of the plugins installed there.

## Versions

Each plugin has its own version, in its `PLUGIN` file, written beside its
installed files as `VERSION`. It changes when compatibility does; what a
change that breaks something asks of you is in
[`UPGRADING.md`](UPGRADING.md). How versions move is in
[`CONTRIBUTING.md`](CONTRIBUTING.md).

## Tests

They run against a server build of Xymon's current `main`, whose test
helpers they use:

```sh
XYMON_SRC=/path/to/built/xymon make test               # every test
cd plugins/NAME && XYMON_SRC=... make test             # one plugin's
```

Each plugin's tests are under its `tests/`, and those of how the plugins fit
together under [`tests/compat/`](tests/compat). Each says at its top what it
checks and what it needs; one that cannot run here skips, and says why. CI
runs them all with nothing missing:
[`.github/workflows/test.yml`](.github/workflows/test.yml).

## Contributing and licence

[`CONTRIBUTING.md`](CONTRIBUTING.md) says how to change this code, and
[`AGENTS.md`](AGENTS.md) what a coding agent adds to it. Everything here is
under the GNU General Public License version 2 or, at your option, any later
version (`GPL-2.0-or-later`); the text of version 2 is in
[`LICENSE`](LICENSE).
