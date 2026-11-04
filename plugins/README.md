# Plugins

The plugins of [xymon-plugins](../README.md): each a directory here with a
`PLUGIN` file, a README, a manual page, tests and its code, installed with
[`install.sh`](../install.sh) at the repository's top. What a plugin is, and
the conventions they share, are in the [top README](../README.md).

## The plugins

Four today, one family: the Xymon API and what builds on it. How they fit
together, and what each needs, is in [`xymonapi`'s
README](xymonapi/README.md#the-api-and-what-builds-on-it); each plugin's
own README says how to install and use it, its manual page every behaviour
and setting.

| plugin | what it is |
|---|---|
| [`xymonapi`](xymonapi/README.md) | the Xymon API: a read-only HTTP and JSON interface to a Xymon server, with `xymonapi-connect` and a client library for the machines that read it |
| [`xymonapi-mcp`](xymonapi-mcp/README.md) | an MCP server that gives an AI tool read-only tools over the API |
| [`xymonapi-rag`](xymonapi-rag/README.md) | a search of Xymon's manual pages and history by meaning: the index on the server, `search` and `ask` anywhere |
| [`xymonapi-agent`](xymonapi-agent/README.md) | one command that asks an AI CLI a question about Xymon, with the MCP server as its only tool; on the server, the API's `/ask` |

## Getting the code from the server

A machine that will only read the API can take the code from the
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
README says only what is particular to it. A plugin ships profiles, each
its part for one kind of place ([Where things run](../README.md#where-things-run)),
declared in its `PLUGIN` file as `PROFILE-*` keys: where it goes
(`PROFILE-root`: `ext`, under `$XYMONHOME/ext`; `prefix`, under
`$PREFIX/libexec/xymon-plugins`), which roles of a machine bring it
(`PROFILE-roles`), its files, manual page, modules, command, task, snippets
and messages. `server`, the Xymon server's, `client`, a monitored host's,
which no plugin ships yet, and `tools`, your own machine's, are the first
three; a plugin may declare another, and the script learns the names from
the files. You install the profiles for the role the machine plays. Run with no word on a terminal,
`./install.sh` asks: install or remove, which role this machine plays, the
detected one by default, and which plugins, Enter taking each default; a
plugin chosen alone brings what it needs, and a plugin removed takes the
installed plugins that need it, each named. It then runs the command the
answers spell, saying which, which are the ones below: the actions are
`install`, `remove` and `venv`, each plugin named short, `xymonapi-mcp`,
or long, `xymonapi-mcp-tools`, the plugin pinned to one profile whatever
the machine; a profile word alone means every plugin of it, and nothing
named does nothing. Short, the action serves every profile the machine's
role brings, the role detected from the
tree `XYMONHOME` names, one per run, each role by two marks both needed --
`etc/xymonserver.cfg` and `bin/xymond` make the server, `etc/xymonclient.cfg`
and `bin/xymonclient.sh` a monitored host, two places so that they are two
pieces of evidence, no `XYMONHOME` your own machine;
one mark of a pair is an error, none a tree that is not Xymon's, and neither
is guessed at -- and the first line says the role, why, and the profiles.
Said, the profile is taken as said, so that a package is staged for a
machine other than this one; a profile under `ext` still needs `XYMONHOME`.
A plugin's directory under a root holds every profile of it that lives
there, installed and removed whole. The tools profile is your own commands under your own
home, so it is installed as yourself, in your own shell, on any machine:
`./install.sh install NAME-tools` on the Xymon server puts them beside the
server profile, which is installed as the Xymon user, and on a monitored
host, where the short form is refused, it is the one thing to install. No plugin ships a client profile yet:
`client` says so and stops.

| profile | where, as whom | command | puts |
|---|---|---|---|
| `server` | the Xymon server, as the user that may write its directory, usually root | `XYMONHOME=/usr/lib/xymon/server ./install.sh install NAME server` | the code in `$XYMONHOME/ext/NAME/`, its task in `$XYMONHOME/etc/tasks.d/`, written `DISABLED`, its manual page under `MANDIR` (`/usr/share/man`) |
| `tools` | any machine that reads the API, the server included, as yourself | `./install.sh install NAME tools` | the code in `$PREFIX/libexec/xymon-plugins/NAME/`, its command in `$PREFIX/bin`, its manual page in `$PREFIX/share/man/man1`; `PREFIX` is `~/.local` |

A plugin that needs another installs it first, so one command is enough,
and with no `NAME` the same two commands install every plugin of a profile.
Settings are taken from the environment or as `NAME=value` arguments. `DESTDIR` stages a profile for a package. The server install also
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
answered no, it says so, and `./install.sh venv PROFILE PYTHON=...`, with
`XYMONHOME` set on the server, does it later. The
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

**Removing.** `./install.sh remove NAME PROFILE`, with `XYMONHOME` set on the
server, removes that plugin alone, and refuses
while another installed plugin needs it, naming it; with no `NAME`, every
plugin of the side and the virtualenv beside them. Each says what it keeps.
