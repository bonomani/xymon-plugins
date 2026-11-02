# xymon-plugins

Plugins for the [Xymon](https://github.com/xymon-monitoring/xymon)
monitoring system: a read-only HTTP and JSON API to a Xymon server, and two
pieces that use it -- tools for AI clients such as Claude and Codex, and a
search of Xymon's manual pages and history. This repository was `xymon-api`
before the split, and carries its whole history.

| plugin | runs on | what it does |
|---|---|---|
| [`xymonapi`](plugins/xymonapi) | the Xymon server | the API: status board, alarms, hosts, RRD values, graphs, history |
| [`xymonapi-mcp`](plugins/xymonapi-mcp) | your machine | gives an AI client read-only tools over the API |
| [`xymonapi-rag`](plugins/xymonapi-rag) | both | finds the manual-page and history passages a question is about |

Each plugin has its own README, for installing and using it, and its own
manual page, for every behaviour and setting.

## Quick start

On the Xymon server, as root:

```sh
make install XYMONHOME=/usr/lib/xymon/server
```

The API is installed disabled: remove `DISABLED` from
`$XYMONHOME/etc/tasks.d/xymonapi`, then check it answers:

```sh
curl http://127.0.0.1:1986/xymon/api/v1/health
```

A `401` means it runs and asks for a user: add `-u` with one of Xymon's
users.

On your laptop, once the API is reachable from it:

```sh
curl https://xymon.example.ch/xymon/api/v1/client > xymon-setup.sh
sh xymon-setup.sh
```

The script installs the client side, gets this machine a token with your
password, and registers the tools with Claude Code and Codex. Then ask your
AI client: "which hosts are red?"

Reaching the server over HTTPS, a self-signed certificate, the search index:
see [`plugins/xymonapi`](plugins/xymonapi/README.md) and
[`plugins/xymonapi-rag`](plugins/xymonapi-rag/README.md).

## Requirements

- A Xymon server built from Xymon's current `main`: the plugins' settings go
  in `xymonserver.d/`, which no Xymon release reads yet.
- Python 3.10 or later, on the server and on the laptop.

## Security, in short

- The API only reads; it changes nothing in Xymon.
- It asks for the users of Xymon's own password file. A laptop keeps a
  token of its own, never the password, and a removed user's tokens stop
  working.
- From another machine, use HTTPS, or an SSH tunnel.
- Status texts can hold secrets: `XYMONAPI_HIDE` blanks what you name, in
  every answer and in the search index.
- An AI client online sends what the tools return to its provider; a local
  model keeps it on your network.

## Versions

Each plugin has its own version, in its `PLUGIN` file, and its releases are
tagged `NAME/vX.Y.Z`; none yet. A laptop installs the version the server
runs, and is told when the server's API is older than it needs. How a
release is made is in [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Where to read more

| for | read |
|---|---|
| installing and using a plugin | its README: [`xymonapi`](plugins/xymonapi/README.md), [`xymonapi-mcp`](plugins/xymonapi-mcp/README.md), [`xymonapi-rag`](plugins/xymonapi-rag/README.md) |
| every behaviour and setting | its manual page: [`xymonapi.8`](plugins/xymonapi/xymonapi.8), [`xymonapi-mcp.1`](plugins/xymonapi-mcp/xymonapi-mcp.1), [`xymonapi-rag.1`](plugins/xymonapi-rag/xymonapi-rag.1) |
| the API's exact answers, for a client or another implementation | the contract, [`openapi.yaml`](plugins/xymonapi/openapi.yaml) |
| changing this code | [`CONTRIBUTING.md`](CONTRIBUTING.md), and [`AGENTS.md`](AGENTS.md) for coding agents |

## Tests

They run against a server build of Xymon's current `main`, whose test
helpers they use:

```sh
XYMON_SRC=/path/to/built/xymon tests/run.sh
```

Each test, under [`tests/api/`](tests/api), says at its top what it checks
and what it needs; one that cannot run here skips, and says why. CI runs
them all with nothing missing:
[`.github/workflows/test.yml`](.github/workflows/test.yml).

## Licence

GNU General Public License version 2 or, at your option, any later version
(`GPL-2.0-or-later`); the text of version 2 is in [`LICENSE`](LICENSE).
