# xymon-plugins

Plugins for the [Xymon](https://github.com/xymon-monitoring/xymon)
monitoring system, one per directory under [`plugins/`](plugins). This
repository was `xymon-api` before it held several, and carries its whole
history.

## The plugins

| plugin | side | what it is | needs |
|---|---|---|---|
| [`xymonapi`](plugins/xymonapi/README.md) | server, client | a read-only HTTP and JSON interface to a Xymon server, as one of its xymonlaunch tasks, and its client | on the server, xymon >= 4.3.31 (main); python >= 3.9 |
| [`xymonapi-mcp`](plugins/xymonapi-mcp/README.md) | client | an MCP server that gives an AI client read-only tools over the Xymon API | xymonapi >= 0.1.0 (its client beside it; the API's socket on the server, or the API over the network); python >= 3.9 |
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
```

or the [tarball](https://github.com/bonomani/xymon-plugins/archive/refs/heads/stable.tar.gz)
or [zip](https://github.com/bonomani/xymon-plugins/archive/refs/heads/stable.zip).
A clone is the better choice: it updates with `git pull`, and
`git fetch -q && git log --oneline HEAD..origin/stable` says what an update
would bring.

A machine that will only read the API can instead take the code from the
Xymon server once the plugins are installed there, at the versions it runs:

```sh
curl --cacert ~/.config/xymon-api/xymon-ca.pem https://xymon.example.ch/xymon/api/v1/client | tar xz
```

`--cacert` names the server's certificate when it is not one the machine
trusts already; `xymonapi`'s README says where to get it. Never `-k`: code
fetched without checking the certificate could be anyone's.

## Installing

Every plugin installs the same way, from its own directory, and each
README says only what is particular to it. A plugin has two sides, and
you install the one the machine plays:

| side | where | command | puts |
|---|---|---|---|
| server | the Xymon server, as the user that may write its directory, usually root | `make install XYMONHOME=/usr/lib/xymon/server` | the code in `$XYMONHOME/ext/NAME/`, its task in `$XYMONHOME/etc/tasks.d/`, written `DISABLED`, its manual page under `MANDIR` (`/usr/share/man`) |
| client | any machine that reads the API, as yourself | `make install-client` | the code in `$PREFIX/libexec/xymon-plugins/NAME/`, its command in `$PREFIX/bin`, its manual page in `$PREFIX/share/man/man1`; `PREFIX` is `~/.local` |

A plugin that needs another installs it first, so one command is enough,
and the same two targets at the repository's top install every plugin of a
side. `DESTDIR` stages either side for a package. The server install also
copies each plugin into what the API serves at `/client`, for other
machines to install from.

**Python.** Every plugin runs on Python 3.9 or later. Only those that need
modules beyond the standard library -- each `Makefile`'s `MODULES` -- make
or complete a virtualenv; the others ask nothing about one, and run with it
when it is there. For a plugin that needs modules, when the machine already
has a Python with them -- the newest of `python3.14` down to `python3` on PATH and in
Homebrew's and pyenv's directories, or the one `PYTHON=` names -- the
install makes a virtualenv beside the plugins from it, `ext/venv` on the
server and `libexec/xymon-plugins/venv` elsewhere, pinning that interpreter
and fetching nothing. When no Python has them, or the virtualenv there lacks
some, the install run from a terminal offers to make or complete it,
installing the modules from PyPI -- the one virtualenv of that side, with
the modules of every plugin installed there; without a terminal, or answered
no, it says so, and `make venv XYMONHOME=... PYTHON=...` on the server, or
`make venv-client PYTHON=...` elsewhere, does it later. The launchers run
with `XYMONAPI_PYTHON` when it is set, else with that virtualenv, else with
the `python3` on PATH, asking nothing; a command that then needs a module it
lacks says which, and what installs it.

**Enabling.** A server task is installed `DISABLED`, so that installing
changes nothing until you remove that line from its file; xymonlaunch
notices and starts it. A later install leaves the task file as you left
it.

**Updating.** Run the same install again, from an updated checkout or a
fresh `/client` download. The server install replaces the plugin's code and
keeps your task file, snippets and settings; a task that is running keeps
the old code until it is stopped, and xymonlaunch starts the new.

**Uninstalling.** `make uninstall XYMONHOME=...` or `make uninstall-client`
in a plugin's directory removes that plugin alone, and refuses while another
installed plugin needs it, naming it; at the repository's top, every plugin
of the side and the virtualenv beside them. Each says what it keeps.

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
