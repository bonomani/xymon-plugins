# xymon-plugins

Plugins and extensions for the [Xymon](https://github.com/xymon-monitoring/xymon)
monitoring system, of two kinds:

- under [`plugins/`](plugins), plugins with a manual page and tests,
  installed with [`install.sh`](install.sh): today the Xymon API and what builds on it.
  [The plugins](#the-plugins) below says what each is and how it installs;
- under [`checks/`](checks), one directory per check for a monitored host
  or the server, each with its script, its `clientlaunch.cfg` stanza and a
  README, copied into place by hand. [`checks/README.md`](checks/README.md)
  lists them, how they install, and where each came from.

The `plugins/` half was the repository `xymon-api`, then `bonomani/xymon-plugins`,
and carries its whole history.

## Where things run

Code in this repository runs in one of three places, and Xymon has names for
the first two:

| place | Xymon's name | started by | lives in |
|---|---|---|---|
| the Xymon server | server extension | xymonlaunch, from a file in `tasks.d` | `$XYMONHOME/ext` |
| a monitored host | client extension | the Xymon client, from `clientlaunch.cfg` | the client's `ext/` |
| your own machine | -- | you, or your AI tool | `~/.local` |

The API is the line between the first two places and the third. Everything
on the two Xymon sides is started by Xymon itself, as its own user, and needs
no credential of the API's: on the server, the API, the daily search index
and `/ask` read xymond's own files; on a monitored host, a check reads the
host it is on. Everything on your own machine -- `xymonapi-connect`, the MCP
server your AI tool starts, `xymonapi-rag search`, `xymonapi-agent` -- goes
through the API, with a token or, on the server itself, its socket. **No
language model is needed for the monitoring data to reach your AI tool**:
only `xymonapi-agent`, `/ask` and `xymonapi-rag ask` call one, as [A language
model](#a-language-model) says.

"Client" in these pages means Xymon's client, on a monitored host; a program
that calls the API is an *API client*; Claude Code, Codex, opencode and the
like are *AI tools*.

## The plugins

| plugin | on the Xymon server | on your own machine | needs |
|---|---|---|---|
| [`xymonapi`](plugins/xymonapi/README.md) | the API: a read-only HTTP and JSON interface to the server, as one of its xymonlaunch tasks | `xymonapi-connect`, which gets this machine a token, and the client library the other plugins use | on the server, xymon >= 4.3.31 (main); python >= 3.9 |
| [`xymonapi-mcp`](plugins/xymonapi-mcp/README.md) | nothing runs: the plugin is staged for `/plugins` | an MCP server that gives an AI tool read-only tools over the API | xymonapi >= 0.1.0 (its client library beside it; the API's socket on the server, or the API over the network); python >= 3.9 |
| [`xymonapi-rag`](plugins/xymonapi-rag/README.md) | the daily index of Xymon's manual pages and history, which the API serves at `/search` | `xymonapi-rag search` and `ask`: the same search, by meaning, from anywhere | xymonapi >= 0.1.0 (its client library beside it); python >= 3.9; a language model only for `ask` |
| [`xymonapi-agent`](plugins/xymonapi-agent/README.md) | `/ask`: the API answers a question in words, off by default | `xymonapi-agent`: one command that asks an AI CLI -- Claude Code, Codex or opencode, headless -- with the MCP server as its only tool | xymonapi-mcp >= 0.1.0 (beside it, with xymonapi's client library); one of the AI CLIs, installed and logged in; python >= 3.9 |

Each row summarises the plugin's `PLUGIN` file. Its README says how to
install and use it, its manual page every behaviour and setting.

## What a plugin is

A directory under `plugins/` holding:

- `PLUGIN`: its name, version, which of the two sides below it has, summary,
  what it needs, its manual page, and the files `install.sh` installs;
- `README.md`: installing and using it;
- its manual page, and its code.

## Getting the code

Take the branch `stable`: the newest code every test passed, which CI moves
forward. `main` holds every change as it lands.

```sh
git clone --branch stable https://github.com/xymon-monitoring/xymon-plugins   # update later with git pull
```

or the [tarball](https://github.com/xymon-monitoring/xymon-plugins/archive/refs/heads/stable.tar.gz)
or [zip](https://github.com/xymon-monitoring/xymon-plugins/archive/refs/heads/stable.zip).
A clone is the better choice: it updates with `git pull`, and
`git fetch -q && git log --oneline HEAD..origin/stable` says what an update
would bring.

A machine that will only read the API can instead take the code from the
Xymon server once the plugins are installed there, at the versions it runs:

```sh
curl --cacert ~/.config/xymon-api/xymon-ca.pem https://xymon.example.ch/xymon/api/v1/plugins | tar xz
```

The address is the API's URL as `xymonapi`'s README gives it for each way of
reaching it -- port included when it is not 443 -- followed by
`/xymon/api/v1/plugins`. `--cacert` names the server's certificate when it
is not one the machine trusts already; `xymonapi`'s README says where to get
it. Never `-k`: code
fetched without checking the certificate could be anyone's.

## Installing a plugin

Every plugin installs the same way, with `./install.sh` at the
repository's top -- a POSIX shell script, needing no `make` -- and each
README says only what is particular to it. A plugin has up to two sides, the
Xymon server's and your own machine's ([Where things run](#where-things-run)),
and you install the one the machine plays. The server actions are also
spelt without `-server`, as they were before the tools had a name of their
own; `install-client` is refused, naming `install-tools`: a client here is
Xymon's, on a monitored host, and nothing installs one there yet.

| side | where, as whom | command | puts |
|---|---|---|---|
| the Xymon server | the Xymon server, as the user that may write its directory, usually root | `XYMONHOME=/usr/lib/xymon/server ./install.sh install-server NAME` | the code in `$XYMONHOME/ext/NAME/`, its task in `$XYMONHOME/etc/tasks.d/`, written `DISABLED`, its manual page under `MANDIR` (`/usr/share/man`) |
| your own machine | any machine that reads the API, the server included, as yourself | `./install.sh install-tools NAME` | the code in `$PREFIX/libexec/xymon-plugins/NAME/`, its command in `$PREFIX/bin`, its manual page in `$PREFIX/share/man/man1`; `PREFIX` is `~/.local` |

A plugin that needs another installs it first, so one command is enough,
and with no `NAME` the same two commands install every plugin of a side.
Settings are taken from the environment or as `NAME=value` arguments. `DESTDIR` stages either side for a package. The server install also
copies each plugin into what the API serves at `/plugins`, for other
machines to install from.

**Python.** Every plugin runs on Python 3.9 or later. Only those that need
modules beyond the standard library -- the `server-modules` and `tools-modules`
lines of its `PLUGIN` -- make
or complete a virtualenv; the others ask nothing about one, and run with it
when it is there. For a plugin that needs modules, when the machine already
has a Python with them -- the newest of `python3.14` down to `python3` on
PATH and in Homebrew's and pyenv's directories, or the one `PYTHON=` names
-- the install makes a virtualenv beside the plugins from it, `ext/venv` on
the server and `libexec/xymon-plugins/venv` elsewhere, pinning that
interpreter and fetching nothing. When no Python has them, or the virtualenv
there lacks some, the install run from a terminal offers to make or complete
it, installing the modules from PyPI -- the one virtualenv of that side,
with the modules of every plugin installed there; without a terminal, or
answered no, it says so, and `XYMONHOME=... ./install.sh venv-server PYTHON=...` on the
server, or `./install.sh venv-tools PYTHON=...` elsewhere, does it later. The
launchers run with `XYMONAPI_PYTHON` when it is set, else with that
virtualenv, else with the `python3` on PATH, asking nothing; a command that
then needs a module it lacks says which, and what installs it.

**Enabling.** A server task is installed `DISABLED`, so that installing
changes nothing until you remove that line from its file; xymonlaunch
notices and starts it. A later install leaves the task file as you left
it.

**Updating.** Run the same install again, from an updated checkout or a
fresh `/plugins` download. The server install replaces the plugin's code and
keeps your task file, snippets and settings. A task that runs on keeps the
code it loaded: the API's install stops the API, saying so, and xymonlaunch
starts the new; a task that runs from time to time, as the index, takes the
new code at its next run.

**Uninstalling.** `XYMONHOME=... ./install.sh uninstall-server NAME` or
`./install.sh uninstall-tools NAME` removes that plugin alone, and refuses
while another installed plugin needs it, naming it; with no `NAME`, every
plugin of the side and the virtualenv beside them. Each says what it keeps.

## A language model

None of the plugins needs one to do its work. The API, the MCP server, the
index and the search run without any. Three things call a model, and each
says whose:

- **Your AI tool's**, with the MCP server: the model is whatever Claude
  Code, Codex, opencode or Claude Desktop runs -- a subscription, an API key
  of yours, or a local model. The Xymon server knows nothing about it. What
  the tools return, status texts included, goes to that tool's provider;
  with a local model it stays on your machine.
- **The server's**, for `/ask`: the Xymon user runs an AI CLI of its own,
  and needs a backend for it, of one of three kinds -- a hosted provider
  with an API key; a local model on the server itself, through Ollama or LM
  Studio; or a local model on another machine of yours, reached by URL. A
  profile under the Xymon user's `~/.config/xymonapi-agent/agents/` names
  it, as [`xymonapi-agent`'s README](plugins/xymonapi-agent/README.md#agents-another-xymon-another-tool-set)
  shows; `xymonapi-agent doctor`, run as that user, says whether it
  answers. With none, `/ask` stays off and everything else works.
- **A model you run**, for `xymonapi-rag ask`: an OpenAI-compatible
  endpoint, Ollama by default, named by `XYMONAPI_RAG_LLM_URL`; no tools,
  no CLI.

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
XYMON_SRC=/path/to/built/xymon tests/run.sh                    # every test
XYMON_SRC=/path/to/built/xymon tests/run.sh plugins/NAME/tests # one plugin's
```

Each plugin's tests are under its `tests/`, and those of how the plugins fit
together under [`tests/compat/`](tests/compat). Each says at its top what it
checks and what it needs; one that cannot run here skips, and says why. CI
runs them all with nothing missing:
[`.github/workflows/test.yml`](.github/workflows/test.yml).

## Contributing and licence

[`CONTRIBUTING.md`](CONTRIBUTING.md) says how to change this code, and
[`AGENTS.md`](AGENTS.md) what a coding agent adds to it. Everything under `plugins/`, and the build and tests, is
under the GNU General Public License version 2 or, at your option, any later
version (`GPL-2.0-or-later`); the text of version 2 is in
[`LICENSE`](LICENSE). The checks under `checks/` each keep their own licence: see
[Licensing & provenance](checks/README.md#licensing--provenance).
