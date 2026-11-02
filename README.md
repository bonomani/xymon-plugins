# xymon-plugins

Plugins for the [Xymon](https://github.com/xymon-monitoring/xymon)
monitoring system, one per directory under [`plugins/`](plugins). This
repository was `xymon-api` before it held several, and carries its whole
history.

## The plugins

| plugin | side | what it is | needs |
|---|---|---|---|
| [`xymonapi`](plugins/xymonapi/README.md) | server | a read-only HTTP and JSON interface to a Xymon server, as one of its xymonlaunch tasks | xymon >= 4.3.31 (main), python >= 3.10 |
| [`xymonapi-mcp`](plugins/xymonapi-mcp/README.md) | client | an MCP server that gives an AI client read-only tools over the Xymon API | xymonapi >= 0.1.0, over the network; python >= 3.10 |
| [`xymonapi-rag`](plugins/xymonapi-rag/README.md) | server, client | a search of Xymon's manual pages and history by meaning; the index task on the server, search and ask anywhere | xymonapi-mcp beside it; xymonapi >= 0.1.0; python >= 3.10 |

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

Any of these gives the same tree:

```sh
git clone https://github.com/bonomani/xymon-plugins              # update later with git pull
curl -L https://github.com/bonomani/xymon-plugins/archive/refs/heads/main.tar.gz | tar xz   # no git
```

or the [zip](https://github.com/bonomani/xymon-plugins/archive/refs/heads/main.zip)
of the same. A clone is the better choice: without git, `VERSION` holds the
plugin's version alone, never a release tag, and a checkout cannot be asked
how far behind it is. Once releases exist, each is a tag, `NAME/vX.Y.Z`, to
clone (`git clone --branch NAME/vX.Y.Z ...`) or download as an archive from
the repository's Releases page.

A plugin's README says when it can be had without this download.

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

## Versions

Each plugin has its own version, in its `PLUGIN` file, written beside its
installed files as `VERSION`; its releases are tagged `NAME/vX.Y.Z`, none
yet. How a release is made is in [`CONTRIBUTING.md`](CONTRIBUTING.md).

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
