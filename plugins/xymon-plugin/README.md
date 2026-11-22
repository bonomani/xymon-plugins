# xymon-plugin

The installer of these plugins, and one of them. Whoever installs, updates
or removes a plugin runs it; installed on a Xymon server, it also sends the
`plugins` column, which says when a newer release is out.

## Install

| part | where, as whom | command |
|---|---|---|
| server | the Xymon server, as the user that owns it | `XYMONHOME=/usr/lib/xymon/server ./xymon-plugin install --server xymon-plugin` |

- Then it is known like any plugin: `status` reports its version, `outdated`
  compares it.
- Its `plugins` task is installed off; to turn it on:
  `XYMONHOME=/usr/lib/xymon/server ./xymon-plugin enable --server xymon-plugin`.

## Use

| to | run or read |
|---|---|
| install, update, remove plugins | `./xymon-plugin VERB --server NAME` (or `--tools`), [verbs](#reference) |
| see where things stand, on a terminal | `./xymon-plugin` with no verb |
| know its own version | `./xymon-plugin --version` |
| see whether a newer release is out, every day | the `plugins` column of the server's host ([details](#the-plugins-column)) |
| read the short version | [plugins/README.md](../README.md) |
| read the manual page | [xymon-plugin(8)](xymon-plugin.8) |

## Needs

- A POSIX shell; Python 3.9 or later for the plugins it installs
  ([Python](#python)).
- For the `plugins` column: `curl` (or `wget`) reaching GitHub, and the
  server's name, `MACHINEDOTS`, in `hosts.cfg`.

## Reference

Every behaviour here is a rule of [`SPEC.md`](../../SPEC.md). Where things
go, the `plugins` column, the environment and exit statuses:
[xymon-plugin(8)](xymon-plugin.8).

### The program and its version

- `plugins/xymon-plugin/xymon-plugin` also runs as itself where links are
  not kept (see the repository's README).

### The plugins column

- A yellow status says what to run.
- Besides `EXSERVICE=plugins` in `alerts.cfg`, a rule of its own can send it
  elsewhere.
- `wget`, used where `curl` is not there, does not send `GH_TOKEN`.

### Choosing the part and the installation

- A verb, then `--server`, `--client` or `--tools`, one at a time. Without
  one, on a terminal, the server part is meant, and said, but a client's
  tree is refused, the command given with `--client`; in a script, name it.
- `--client` installs, updates and removes a plugin's client part in a
  standalone Xymon client's tree, run by whoever owns its `ext/`. A
  client tree that is, or may be, a server's own is refused; `enable`,
  `disable`, `status`, `verify`, `outdated` and `clean` do not take it yet.
  A directory in `ext/` no install completed -- one cut short has no
  `MANIFEST` -- is left as it is: remove it by hand.
- The Xymon installation is `XYMONHOME`, or `--xymon-home PATH`, which wins.
  On a terminal it may be left out: the server found is proposed, or, with
  several, the one used last.
- The command says which installation it acts on before changing anything.
- With no verb on a terminal, it also offers what applies, and prints and
  runs the command chosen.
- Settings come from the environment or as `NAME=value` arguments.
- `DESTDIR` stages either part for a package.

### What goes where

| part | puts, besides the code |
|---|---|
| server | its task in `ext/NAME/tasks.cfg`, off; its manual page under `MANDIR` (`/usr/share/man`, or Homebrew's `share/man` for a Xymon it installed); a copy for the API to serve at `/plugins` |
| client | its manual page under `MANDIR`, when that can be written; nothing else |
| tools | its command in `$PREFIX/bin`; its manual page in `$PREFIX/share/man/man1`. `PREFIX` is `~/.local` |

- A plugin needing a newer Xymon than the server's (its `PLUGIN`'s `xymon:`
  line) is refused, naming both versions; `--force` installs it anyway.
- A plugin needing another installs it first.
- A needed plugin installed already, and one `--all` finds installed, are
  left as they are, said.
- `install` refuses a plugin installed already: `update` replaces it.
- Run as root, `--tools` is refused unless `PREFIX` or `DESTDIR` is given:
  the tools would go in root's home.

### Python

- Only plugins whose `PLUGIN` lists modules (`server-modules`,
  `tools-modules`, `tools-optional-modules`, with `venv-note` saying what the
  optional ones add) make or complete a virtualenv; the others run with it
  when it is there.
- One virtualenv per part: `ext/venv` on the server,
  `libexec/xymon-plugins/venv` elsewhere, holding the modules of every
  plugin installed there.
- When a Python already has the modules -- the newest of `python3.14` down to
  `python3` on PATH and in Homebrew's and pyenv's directories, or the one
  `PYTHON=` names -- the virtualenv is made from it, fetching nothing.
- Otherwise, on a terminal, the install offers to make or complete it from
  PyPI; off a terminal it fetches only with `--venv`, and else says so.
  `update --server --venv` or `update --tools --venv` does it later.
- Under `DESTDIR` none is made.
- `enable` refuses a plugin whose Python lacks its modules, and `status`
  says so.
- The launchers run with `XYMONAPI_PYTHON` when set, else that virtualenv,
  else `python3` on PATH; a missing module is named, with what installs it.

### Tasks

- `enable --server NAME` links `etc/tasks.d/NAME.cfg` to
  `ext/NAME/tasks.cfg`, and xymonlaunch starts it within half a minute.
- `disable --server NAME` removes the link, and xymonlaunch stops it.
- An update keeps the task file as you left it, and whether it is on.
- Where an editor replaced the link by a file (`sed -i` does), that file is
  taken into `ext/NAME` and the link put back.
- A task an older install wrote with a `DISABLED` line is off, and the line
  taken out.

### Updating

- `status --server` or `status --tools` says what is installed, at which
  version, whether its task is on, and whether the checkout is newer.
- `update --server` or `update --tools`, from an updated checkout, a release
  archive or a `/plugins` download, updates what is installed, or the
  plugins named; it refuses one not installed.
- It replaces the code and keeps your task file, web server snippets and
  settings.
- A file you edited that this version changes too is merged on a terminal
  when the changes do not overlap and you answer y (yours kept as
  `NAME.old`); otherwise yours stays and this version's is written beside it
  as `NAME.new`.
- Running code takes up the update by itself: the API stops once the update
  command's `MANIFEST`s are written, at its end, and xymonlaunch starts it
  again on the new code. A task that runs from time to time takes the new
  code at its next run. No process is looked for or signalled.

### Checking

- `verify` (`--server`, `--tools`, or both) says what differs from what was
  installed, one line each with the command that fixes it: a file changed or
  missing, one no install wrote, a link pointing elsewhere, a Python module
  older than asked, what no installed plugin owns. It changes nothing.
- `outdated` says, for what is installed, whether a newer release is
  published on GitHub, with the update that takes it.
- It reads the releases with `gh`, else `curl` or `wget`, each request of
  `curl` and GNU `wget` bounded in time.
- It ends with 1, before 7 and 6, when GitHub cannot be reached or has more
  releases than the 60 pages read without `gh`.
- `curl` sends `GH_TOKEN` when set, on its standard input, never on its
  command line; `wget` sends none, said.
- Behind a proxy, each uses the settings it sees (environment,
  `~/.curlrc`); under `sudo`, run as yourself or with `sudo -E`.
- `clean --server NAME` (or `--tools`, or `--all`) takes away what a deleted
  plugin left -- its task link, manual page link, staged copy or command --
  once listed and confirmed, or with `--yes` off a terminal; it takes only
  what is provably a plugin's.

### Uninstalling

- `remove --server NAME` or `remove --tools NAME` removes that plugin; it
  refuses while another installed plugin needs it, naming it.
- `--all` removes every plugin of the part and its virtualenv.
- Each says what it keeps.
- Deleting `$XYMONHOME/ext/NAME` by hand also stops its task: xymonlaunch
  skips the link now pointing nowhere at its next reload. The link, manual
  page and copy at `/plugins` stay until `remove --server NAME`.
