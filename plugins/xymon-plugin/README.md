# xymon-plugin

The installer of these plugins, and one of them: `./xymon-plugin` at the
repository's top, in a checkout or a release's archive, is a link to
`plugins/xymon-plugin/xymon-plugin`, which also runs as itself where links
are not kept (see the repository's README). Its verbs and settings are in
[Reference](#reference) below, the short version in
[plugins/README.md](../README.md); its manual page is
[xymon-plugin(8)](xymon-plugin.8).

Installed on a Xymon server, it is known like any plugin -- its version
reported by `status` and compared by `outdated`:

```sh
XYMONHOME=/usr/lib/xymon/server ./xymon-plugin install --server xymon-plugin
```

Its version is the `version:` line of its `PLUGIN` file; `--version` gives it.

## The plugins column

Installed on the server, it brings a task, off until turned on:

```sh
XYMONHOME=/usr/lib/xymon/server ./xymon-plugin enable --server xymon-plugin
```

Once a day, after a wait drawn at random up to 6 hours, it sends this
host's status `plugins`, valid 31 hours: green when no newer release of a
plugin installed is published, yellow when one is or a plugin's `VERSION`
cannot be compared, with what to run. When GitHub is not reached it sends
nothing, and the status goes purple once 31 hours have passed since the
last one -- as it does when a restart of xymond stops the task while it
waits. The status is for `MACHINEDOTS`, the server's name in
`xymonserver.cfg`, which `hosts.cfg` must name; read back, one that xymond
did not keep is said. What it does is in `xymon-plugin.log`, in Xymon's
log directory.

Yellow and purple alert as any column: in `alerts.cfg`, `EXSERVICE=plugins`
on a rule keeps it out, or a rule of its own sends it elsewhere. Behind a
proxy, or to read GitHub with a token, set `https_proxy` or `GH_TOKEN` in a
file under `xymonserver.d/`, which the task reads; it reads GitHub with
`curl`, bounded in time, and not `gh`, which is not -- and `curl` sends the
token, which `wget`, used where `curl` is not there, does not.

## Reference

The short version is in [plugins/README.md](../README.md); every behaviour
here is a rule of [`SPEC.md`](../../SPEC.md).

### Choosing the part and the installation

- A verb, then `--server` or `--tools`, which goes alone. Without one, on a
  terminal, the server part is meant, and said; in a script, name it.
  `--client` is refused: no plugin has a part on a monitored host yet.
- The Xymon installation is `XYMONHOME`, or `--xymon-home PATH`, which
  wins. On a terminal it may be left out: the server found is proposed, or,
  with several, the one used last. The command says which it acts on before
  it changes anything.
- Run with no verb on a terminal, `./xymon-plugin` says where things stand,
  offers what applies, and prints and runs the command chosen.
- Settings come from the environment or as `NAME=value` arguments.
  `DESTDIR` stages either part for a package.

### What goes where

| part | puts |
|---|---|
| server | the code in `$XYMONHOME/ext/NAME/`; its task in `ext/NAME/tasks.cfg`, off; its manual page under `MANDIR` (`/usr/share/man`, or Homebrew's `share/man` for a Xymon it installed); a copy for the API to serve at `/plugins` |
| tools | the code in `$PREFIX/libexec/xymon-plugins/NAME/`; its command in `$PREFIX/bin`; its manual page in `$PREFIX/share/man/man1`. `PREFIX` is `~/.local` |

- A plugin needing a newer Xymon than the server's (its `PLUGIN`'s `xymon:`
  line) is refused, naming both versions; `--force` installs it anyway.
- A plugin needing another installs it first. One installed already, and
  one `--all` finds installed, are left as they are, said.
- `install` refuses a plugin installed already: `update` replaces it.
- Run as root, `--tools` is refused unless `PREFIX` or `DESTDIR` is given:
  the tools would go in root's home.

### Python

- Every plugin runs on Python 3.9 or later. Only those whose `PLUGIN` lists
  modules (`server-modules`, `tools-modules`, `tools-optional-modules`, with
  `venv-note` saying what the optional ones add) make or complete a
  virtualenv, which the others run with when it is there: one per part, `ext/venv` on the server, `libexec/xymon-plugins/venv` elsewhere,
  holding the modules of every plugin installed there.
- When a Python already has the modules -- the newest of `python3.14` down to
  `python3` on PATH and in Homebrew's and pyenv's directories, or the one
  `PYTHON=` names -- the virtualenv is made from it, fetching nothing.
- Otherwise, on a terminal, the install offers to make or complete it from
  PyPI; off a terminal it fetches only with `--venv`, and else says so.
  `update --server --venv` or `update --tools --venv` does it later. Under
  `DESTDIR` none is made.
- `enable` refuses a plugin whose Python lacks its modules, and `status`
  says so. The launchers run with `XYMONAPI_PYTHON` when set, else that
  virtualenv, else `python3` on PATH; a missing module is named, with what
  installs it.

### Tasks

- A server task is installed off. `enable --server NAME` links
  `etc/tasks.d/NAME.cfg` to `ext/NAME/tasks.cfg`, and xymonlaunch starts it
  within half a minute; `disable --server NAME` removes the link, and
  xymonlaunch stops it.
- An update keeps the task file as you left it, and whether it is on. Where
  an editor replaced the link by a file (`sed -i` does), that file is taken
  into `ext/NAME` and the link put back. A task an older install wrote with a
  `DISABLED` line is off, and the line taken out.

### Updating

- `status --server` or `status --tools` says what is installed, at which
  version, whether its task is on, and whether the checkout is newer.
- `update --server` or `update --tools`, from an updated checkout, a release
  archive or a `/plugins` download, updates what is installed, or the
  plugins named; it refuses one not installed.
- It replaces the code and keeps your task file, web server snippets and
  settings. A file you edited that this version changes too is merged on a
  terminal when the changes do not overlap and you answer y (yours kept as
  `NAME.old`); otherwise yours stays and this version's is written beside it
  as `NAME.new`.
- Running code takes up the update by itself: the API stops once the
  update command's `MANIFEST`s are written, at its end, and xymonlaunch
  starts it again on the new code; a task that runs from time to time takes
  the new code at its next run. No process is looked for or signalled.

### Checking

- `verify` (`--server`, `--tools`, or both) says what differs from what was
  installed, one line each with the command that fixes it: a file changed or
  missing, one no install wrote, a link pointing elsewhere, a Python module
  older than asked, what no installed plugin owns. It changes nothing; exit
  0 all as installed, 3 something broken, 4 only untidy.
- `outdated` says, for what is installed, whether a newer release is
  published on GitHub, with the update that takes it. It reads the releases
  with `gh`, else `curl` or `wget`, each request of `curl` and GNU `wget`
  bounded in time; `XYMON_PLUGINS_NO_GH` leaves `gh` out. Exit 1 when GitHub
  cannot be reached (or has more releases than the 60 pages read without
  `gh`); else 7 when a `VERSION` cannot be compared, each line saying why
  and what fixes it; else 6 when a newer release exists; else 0.
- `curl` sends `GH_TOKEN` when set, on its standard input, never on its
  command line; `wget` sends none, said. Behind a proxy, each uses the
  settings it sees (environment, `~/.curlrc`); under `sudo`, run as yourself
  or with `sudo -E`.
- `clean --server NAME` (or `--tools`, or `--all`) takes away what a
  deleted plugin left -- its task link, manual page link, staged copy or
  command -- once listed and confirmed, or with `--yes` off a terminal; only
  what is provably a plugin's.

### Uninstalling

- `remove --server NAME` or `remove --tools NAME` removes that plugin, and
  refuses while another installed plugin needs it, naming it; `--all`
  removes every plugin of the part and its virtualenv. Each says what it
  keeps.
- Deleting `$XYMONHOME/ext/NAME` by hand also stops its task: xymonlaunch
  skips the link now pointing nowhere at its next reload. The link, manual
  page and copy at `/plugins` stay until `remove --server NAME`.
