# Plugins

The plugins of [xymon-plugins](../README.md): each a directory here with a
`PLUGIN` file, a README, a manual page, tests and its code, installed with
[`xymon-plugin`](../xymon-plugin) at the repository's top. What a plugin is, and
what installing one guarantees, are in [`SPEC.md`](../SPEC.md); the
conventions they share, in the [top README](../README.md).

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
curl --cacert ~/.config/xymonapi/xymon-ca.pem https://xymon.example.ch/xymon/api/v1/plugins | tar xz
```

The address is the API's URL as `xymonapi`'s README gives it for each way of
reaching it -- port included when it is not 443 -- followed by
`/xymon/api/v1/plugins`. `--cacert` names the server's certificate when it
is not one the machine trusts already; `xymonapi`'s README says where to get
it. Never `-k`: code
fetched without checking the certificate could be anyone's.

## Installing a plugin

Every plugin installs the same way, with `./xymon-plugin` at the
repository's top -- a POSIX shell script, needing no `make` -- and each
README says only what is particular to it. A plugin has up to two parts, the
Xymon server's and your own machine's ([Where things run](../README.md#where-things-run)),
and you install the one the machine plays: a verb, then `--server` or
`--tools`, which goes alone. Without one, on a terminal, the server part is
meant, and said; in a script, name it. The Xymon installation is
`XYMONHOME`, or `--xymon-home PATH`, which wins; on a terminal it may be
left out: the server found is proposed, or, with several, the one used
last, and the command says which it acts on before it changes anything. Run with no verb on a
terminal, `./xymon-plugin` says where things stand and offers what applies,
printing and running the command chosen.
`--client` is refused: a client here
is Xymon's, on a monitored host, and no plugin has a part there yet.

| side | where, as whom | command | puts |
|---|---|---|---|
| the Xymon server | the Xymon server, as the user that may write its directory, usually root | `XYMONHOME=/usr/lib/xymon/server ./xymon-plugin install --server NAME` | the code in `$XYMONHOME/ext/NAME/`, its task in `ext/NAME/tasks.cfg`, off until enabled, its manual page under `MANDIR` (`/usr/share/man`, Homebrew's `share/man` for a Xymon it installed) |
| your own machine | any machine that reads the API, the server included, as yourself | `./xymon-plugin install --tools NAME` | the code in `$PREFIX/libexec/xymon-plugins/NAME/`, its command in `$PREFIX/bin`, its manual page in `$PREFIX/share/man/man1`; `PREFIX` is `~/.local` |

A plugin that needs a newer Xymon than the server's, by the `xymon:` line of
its `PLUGIN`, is refused, naming both versions; `--force` installs it
anyway. A plugin that needs another installs it first, so one command is enough,
and `--all` in place of `NAME` installs every plugin of a part. `install`
refuses a plugin installed already: `update` replaces it. A plugin needed
that is installed already, and one `--all` finds installed, are left as
they are, said. Run as root, the tools are refused unless `PREFIX` or
`DESTDIR` is given: they would go in root's home.
Settings are taken from the environment or as `NAME=value` arguments. `DESTDIR` stages either side for a package. The server install also
copies each plugin into what the API serves at `/plugins`, for other
machines to install from.

**Python.** Every plugin runs on Python 3.9 or later. Only those that need
modules beyond the standard library -- the `server-modules` and `tools-modules`
lines of its `PLUGIN`, and `tools-optional-modules` for those a part does
without, `venv-note` saying what they add -- make
or complete a virtualenv; the others ask nothing about one, and run with it
when it is there. For a plugin that needs modules, when the machine already
has a Python with them -- the newest of `python3.14` down to `python3` on
PATH and in Homebrew's and pyenv's directories, or the one `PYTHON=` names
-- the install makes a virtualenv beside the plugins from it, `ext/venv` on
the server and `libexec/xymon-plugins/venv` elsewhere, pinning that
interpreter and fetching nothing. When no Python has them, or the virtualenv
there lacks some, the install run from a terminal offers to make or complete
it, installing the modules from PyPI -- the one virtualenv of that side,
with the modules of every plugin installed there; without a terminal, it
fetches only when `--venv` is given, and otherwise says so: `update
--server --venv` on the server, or `update --tools --venv` elsewhere, does
it later, with `PYTHON=...` to name the Python to make it from. Under
`DESTDIR` none is made. There is no verb of its own for it. `enable`
refuses a plugin whose Python lacks its modules, naming what makes them,
and `status` says so. The
launchers run with `XYMONAPI_PYTHON` when it is set, else with that
virtualenv, else with the `python3` on PATH, asking nothing; a command that
then needs a module it lacks says which, and what installs it.

**Enabling.** A server task is installed off, so that installing changes
nothing until `XYMONHOME=... ./xymon-plugin enable --server NAME`, which links
`etc/tasks.d/NAME.cfg` to the task file, `ext/NAME/tasks.cfg`; xymonlaunch
notices and starts it within half a minute. `disable --server NAME` removes the
link, and xymonlaunch stops the task. An update keeps the task file as
you left it, and whether it is on; where an editor replaced the link by a
file of its own, as `sed -i` does, it moves that file into `ext/NAME` and
puts the link back. A task an older install wrote with a
`DISABLED` line is off, and that line is taken out.

**Updating.** `XYMONHOME=... ./xymon-plugin status --server`, or
`./xymon-plugin status --tools`, says what is installed, at which version,
whether its task is on, and whether the checkout it runs from is newer.
`update --server`, or `update --tools`, from an updated checkout or a fresh
`/plugins` download, updates what is installed, or the plugins named; it
refuses one that is not installed. It replaces the plugin's code and
keeps your task file, snippets and settings. One you edited that this
version changes too is merged on a terminal when the two changes do not
touch the same lines and you answer y, your file before kept as
`NAME.old`; otherwise it stays as you left it, this version's beside it as
`NAME.new`, to compare and remove. A task that runs on keeps the
code it loaded: the API's update sends the API the signal to stop, saying
so, and xymonlaunch starts it again on the new code if its task is on; a task
that runs from time to time, as the index, takes the new code at its next run.

**Checking.** `./xymon-plugin verify`, or `verify --server` or `--tools`,
says what differs from what was installed, one line each, with the command
that puts it right: a file changed or missing, a file or bytecode that no
install wrote, a link pointing elsewhere, a Python module older than the
plugin asks, and what no plugin installed owns. It changes nothing, and
exits 0 when all is as installed, 3 when something is broken, 4 when
something is only untidy -- what a nightly check can test.
`./xymon-plugin outdated` says, for what is installed, whether a newer
release is published on GitHub, with the update that takes it. It changes
nothing, reads the releases with `gh` or, when `gh` is missing or fails,
`curl` or `wget`, and exits 6 when it said of a plugin that a newer release
exists, 0 when it said of none, and 1, saying why, when GitHub cannot be
reached, when it has more releases than the 60 pages read without `gh`, or
when a `VERSION` cannot be read. Behind a proxy, each of `gh`, `curl` and
`wget` uses the proxy settings it sees -- its environment, `~/.curlrc` for
`curl`; under `sudo`, which those are depends on sudo's policy, so run it as
yourself or with `sudo -E`.
`clean --server NAME`, or `--tools`, or `--all`, takes away what a plugin
gone left -- a directory deleted by hand leaves its task link, its manual
page's link, its staged copy or its command -- once listed and confirmed,
or with `--yes` off a terminal; only what is provably a plugin's.

**Uninstalling.** `XYMONHOME=... ./xymon-plugin remove --server NAME` or
`./xymon-plugin remove --tools NAME` removes that plugin alone, and refuses
while another installed plugin needs it, naming it; `--all` in place of
`NAME` removes every plugin of the part and the virtualenv beside them. Each says what it keeps.
On the server, removing `$XYMONHOME/ext/NAME` by hand also removes the
plugin's task: xymonlaunch skips the link in `tasks.d` that now points
nowhere and stops the task at its next reload, within half a minute, with
nothing in its log. The link, the manual page and the copy served at
`/plugins` stay until `remove --server NAME`.
