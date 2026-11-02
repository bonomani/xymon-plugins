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

## Installing

```sh
make install XYMONHOME=/usr/lib/xymon/server     # every server-side plugin
make install-client                              # every client-side plugin, under ~/.local
make -C plugins/NAME install XYMONHOME=...       # one plugin, and what it needs
```

On a Xymon server a plugin lands in `$XYMONHOME/ext/NAME/`; elsewhere in
`$PREFIX/libexec/xymon-plugins/NAME/`, with its command in `$PREFIX/bin`.
Each writes its version beside its files, in `VERSION`. What to do next is
in the plugin's README.

## Versions

Each plugin has its own version, in its `PLUGIN` file, and its releases are
tagged `NAME/vX.Y.Z`; none yet. How a release is made is in
[`CONTRIBUTING.md`](CONTRIBUTING.md).

## Tests

They run against a server build of Xymon's current `main`, whose test
helpers they use:

```sh
XYMON_SRC=/path/to/built/xymon tests/run.sh
```

Each plugin's tests are under its `tests/`, and those of how the plugins fit
together under [`tests/compat/`](tests/compat). Each says at its top what it
checks and what it needs; one that cannot run here skips, and says why. CI runs
them all with nothing missing:
[`.github/workflows/test.yml`](.github/workflows/test.yml).

## Contributing and licence

[`CONTRIBUTING.md`](CONTRIBUTING.md) says how to change this code, and
[`AGENTS.md`](AGENTS.md) what a coding agent adds to it. Everything here is
under the GNU General Public License version 2 or, at your option, any later
version (`GPL-2.0-or-later`); the text of version 2 is in
[`LICENSE`](LICENSE).
