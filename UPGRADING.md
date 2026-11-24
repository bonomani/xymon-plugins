# Upgrading

What a change that breaks something asks of you, newest first: the plugin,
its version, what breaks, and what to do. Every other change needs nothing
but installing the new code (see each plugin's README). CI refuses a change
that breaks the API's contract without a line here.

## The task line is `server-task:`, from xymon-plugin 0.2.7

A plugin's `PLUGIN` file names its server task with `server-task:`, where
it said `task:`. The installer reads the copy of `PLUGIN` kept with each
installed plugin, and an install made before reads as one with no task:
`remove` would leave its task link, `enable` and `disable` refuse it.

- **Update first**: `./xymon-plugin update --server`, with the new
  version, rewrites every plugin's copy; then everything acts as before.
- A task link left by a `remove` before that: `rm` it from `etc/tasks.d/`.
- A plugin of your own: rename the line in its `PLUGIN`; a `task:` line
  is no longer read, and the plugin installs with no task.
- xymonapi 9.1.2 and xymonapi-rag 0.2.3 name their task so: install them
  with xymon-plugin 0.2.7 or later: an older one reads them as having no
  task.

## The installer leaves what is not its own, from xymon-plugin 0.2.4

xymon-plugin 0.2.4 to 0.2.6 take or replace only what an install made, in
`ext/` and beside it. Nothing is asked of you for a usual install; these
cases now behave differently:

- **A link, or anything no install left, at `ext/NAME`** -- a directory
  holding data, a `PLUGIN` naming another plugin, a link to a directory of
  yours -- is refused by `install`, `update` and `remove` before anything
  changes, naming it; before, it was replaced or deleted. A package that
  put a link there: install into a directory instead. `remove --all` and
  `update` with none named pass over it, saying so.
- **An install cut short** (an update stopped by an error or a signal)
  carries a file in progress, and its edited task file, snippets and
  `.old` files wait in `ext/.xymon-plugin.NAME`: the next `install` or
  `update` of the plugin resumes and puts them back. An installer older
  than 0.2.4 does not know that state: it advises removing `ext/NAME` by
  hand. Update with 0.2.4 or later instead.
- **Your own manual page or command** at a plugin's name -- in `MANDIR`, or
  `$PREFIX/bin` for the tools -- is left as it is and said, where it was
  replaced.
- **A task file or web server snippet you edited, that a new version no
  longer ships**, is kept as `NAME.old` (`verify` says it is untidy until
  you remove it); an edited snippet replaced by another for the same web
  server stops the update until your edits are carried into the new one
  and the old one is moved out of `ext/NAME`, as the refusal says.
- **Removing a plugin whose directory is gone** takes only the task link
  pointing into it: a task file of yours at that name stays.
- **The installation used last** is remembered per part, in a file of its
  own: the one remembered before is not known after the update, so where
  several are found none is offered as the default until one is chosen
  again.
- **`update` with none named, from one release's archive**, which holds its
  own plugin alone, passes over the plugins installed that it does not
  carry (0.2.6; 0.2.4 and 0.2.5 stopped on the first of them).

## The API takes up an update by itself, from xymonapi 9.1.0

`./xymon-plugin update --server` no longer looks for the API's process to
stop it: from 9.1.0 the API watches its `MANIFEST` and stops once an
update rewrites it, and xymonlaunch starts the new code (S7). An API older
than 9.1.0, running when you update it, does not watch: it keeps the code
it started with until stopped. Once, after updating it to 9.1.0 or later,
turn its task off and on, 45 seconds apart -- xymonlaunch reads tasks.d/
every 30 to 35 seconds, and must see the task gone --:
`./xymon-plugin disable --server xymonapi`, then `enable`; or restart Xymon.

## The board is /alarms, one alarm per test, from xymonapi 9.0.0

**One resource.** The board is `/alarms`, as TMF642 has `/alarm` and
`/alarm/{id}`: every alarm, green ones too, and `/alarms/{id}` one alarm
with its status's `text`. `/states` and `/status` are gone.

| before | from 9.0.0 |
|---|---|
| `/states` | `/alarms` |
| `/alarms` (what is not green) | `/alarms?state=firing`, and `state=suppressed` for blue |
| `/status?host=H&test=T` | `/alarms/{id}`, the id from `/alarms?host=H&test=T` |
| `/entities`, items `{"id", "composition", "labels"}` | `/hosts`, items `{"host"}` |

**One alarm object**, in every answer:

- `severity`, what the test last measured, in ITU-T X.733's words: red
  `critical`, yellow `warning`, green `cleared`, `indeterminate` where
  nothing was. `verdict` is gone, and so are `major` and `minor`.
- `state`: `firing`, `pending` (red or yellow reported, still shown green:
  a change delay), `suppressed` (blue: disabled, or a DOWNTIME window),
  `inactive` (green). It was the field `status`.
- Purple, clear and blue no longer replace what was measured: they are
  said beside it. `stale: {since}` for a test gone silent;
  `unreachable: {reportedBy: [id]}` for one made clear because its host's
  conn is not green, the id that conn alarm's (it was `true`, and given
  for a red conn only); `suppressedBy`, a list (it was a word): `{kind:
  disable, of: test, until, createdBy, from, text}` or `{kind: downtime,
  of: test, until, text}`, a field Xymon does not keep left out --
  `createdBy` and `from` only for a disable set from the web page; a
  DOWNTIME's `until` and its cause as `text`. A blue the test reported
  itself has no `suppressedBy`. Where xymond shows another colour than
  the one reported -- a change delay, a flap, a modifier too --
  `severity` is the reported one; `stale` only for xymond's own purple;
  `overriddenBy: [{kind: flap, since} | {kind: modifier, text}]` says a
  flap or a modifier.
- `acknowledged`: `since` when xymond keeps it (the critical-systems
  view), `ackedBy` and `from` when the web page made it.
- `labels: {category}` groups it, as Alertmanager's labels do: `filesystem`,
  `network`, `web`..., or a test's own name. It was `domain`.
- `id` is opaque, the same while host, test and instance are: it was
  `host:test`, which every inode alarm of a host shared. `link` is
  `alarms/{id}`. `since` was `time` in `/states`.
- A time xymond gives as 0, a test such as `trends` that never changed,
  is left out, not `1970-01-01T00:00:00Z`.

**Filters**, on `/alarms`: `host`, `test`, `severity`, `state`, `category`,
and `stale`, `unreachable`, `suppressed`, `overridden`, `acknowledged` as
`true` or `false` -- `state=firing&acknowledged=false` is what nobody has
in hand. **A query
parameter an operation does not list is refused**, `400 bad_request`,
naming it and those the operation takes (openapi.yaml, C2): it was
ignored, so `/states?entity=web1` answered the whole board and
`/series?start=-2h` the last 24 hours.

**The MCP server** (xymonapi-mcp 0.3.1) follows: its tools `alarms` (with
the same filters) and `alarm` by id; `states`, `status` and `entities` are
gone, `hosts` in their place for the last. With no `state` asked, its
`alarms` leaves the green ones out -- the whole board is more than an
agent's context holds -- and `state=inactive` gives them.

What to do: read `/alarms?state=firing` where you read `/alarms`, and
`/alarms` where you read `/states`; `severity` and `state` in place of
`verdict` and `status`; find an alarm's text at its `link`; test
`unreachable` for presence; send only the parameters `openapi.yaml` lists.

## An alarm keeps the severity its test measured, from xymonapi 8.0.0

`/alarms` turned xymond's colours into severities: purple critical, clear
and blue minor. Purple, clear and blue are xymond's, not the test's (RFC
#113): an alarm now keeps the severity the test last reported -- `major`
for red, `minor` for yellow, read from xymond's `prevgapcolor`, Xymon
4.3.31 -- and says beside it `stale: {since}` for a test gone silent,
`unreachable: true` for one that is clear, and the status `suppressed` for
one disabled. `indeterminate` is the severity where nothing that is not ok
was measured: a clear from xymonnet, a test that was green. `critical` is
given no more. What to do: a client that read `critical` for a silent test
reads `stale`; one that left out clear or blue by their severity leaves out
`unreachable`, `suppressed` or `indeterminate`.

An inode test in alarm is given once for each file system its status
names, each with its `instance`: several alarms share the `id`
`host:inode`. A client that keys alarms by `id` keys them by host, test and
instance.

## A host is called host, from xymonapi 8.0.0

The API called a host `entity`, as a query parameter and as a field; it is
`host` now, Xymon's own word (RFC #113): `/states?host=`, `/status`,
`/series`, `/graphs`, `/events` and `/histlog` take `host=`, and every
answer that named the host -- a state, an alarm, a status, an event, a
saved status, a series' labels, a passage of the history found by `/search`
-- gives `host`. `entity` is read no more. `/entities` keeps its name for
now. The MCP server's tools `states`, `status` and `series` take `host`
(xymonapi-mcp 0.2.0), and xymonapi-mcp and xymonapi-rag need xymonapi
8.0.0. What to do: a script reads and sends `host`; update the server and
every machine's tools together (`./xymon-plugin update --server`, then
`--tools`). The search's history passages say `host` once the next
`xymonapi-rag index` has run, which keeps their vectors.

## A task's link becomes tasks.d/NAME.cfg, from November 2026

A plugin's task is on when `etc/tasks.d/NAME.cfg` links to its task file;
the link was `tasks.d/NAME`. A packaged Xymon may read only the files of
`tasks.d/` that end in `.cfg`, where Xymon's own reads them all. The next
`./xymon-plugin update --server`, or `enable`, renames the link an older
install made, and the task stays on: nothing to do. What breaks: a script
that names `tasks.d/xymonapi`. Also: `enable` now refuses a server whose
`tasks.cfg` has no `directory` line for `tasks.d/`, and says the line to
add; `--force` makes the link where the server reads it another way.

## /health says each version under what it is the version of, from xymonapi 7.0.0

`/health` gave `version`, the API's, and `server_version`, xymond's answer
to a ping, with `alive` for whether xymond answered: names that did not say
whose, and `version` in two forms, `6.0.1` or `xymonapi/v6.0.1`. It now
gives `api.version`, always `X.Y.Z`, and `xymond.alive`, `xymond.version`
(`4.3.32-dev`) and `xymond.answer` (`xymond 4.3.32-dev`); `version`,
`server_version` and the top-level `alive` are gone. What to do: a script
reading `/health` reads the new fields; update the server and every
machine's tools together (`./xymon-plugin update --server`, then
`--tools`): a client of this version reads no version from an older API,
and says no difference of versions with it.

## The client's directory becomes ~/.config/xymonapi, from xymonapi 6.0.0

`xymonapi-connect` keeps the API's URL, its token and a certificate in
`$XDG_CONFIG_HOME/xymonapi/`, the plugin's own name (SPEC, S28); it was
`xymon-api/`, which is read no more. What to do: move the directory,
`mv ~/.config/xymon-api ~/.config/xymonapi`, or run `xymonapi-connect URL`
again, which asks your password once. An AI tool registered with
`XYMONAPI_TOKEN_FILE` or `XYMONAPI_CA` under the old directory needs them
renamed too, or `xymonapi-mcp register URL` again.

## install.sh becomes xymon-plugin, from November 2026

The installer is `./xymon-plugin`, with a verb and the part it acts on:
`install-server NAME` is `install --server NAME`, `install-tools` is
`install --tools`, `uninstall-*` is `remove`, and so for `enable`,
`disable` and `status`; `venv-server` and `venv-tools` are `update --venv`,
the virtualenv having no verb of its own; `install.sh` is gone, and each old action
is refused, naming the new form. What breaks: a script that calls
`install.sh`. Also: `install` and `remove` need a plugin named, or `--all`;
`install` refuses a plugin installed already, which `update` replaces; a
script names the part, `--server` or `--tools`; and the tools are refused
as root unless `PREFIX` or `DESTDIR` is given; off a terminal, modules are
fetched only with `--venv`; `enable` refuses a plugin whose Python lacks
its modules. What is installed, and where, is unchanged. A plugin
installed before reads as needing nothing, as its copy of `PLUGIN` has
`needs:`, not `server-needs:` or `tools-needs:`: `remove --all` then
removes in no set order, which is harmless when all go; to remove one
alone, update first.

## xymonapi-connect asks the password once more, from xymonapi 5.0.2

`xymonapi-connect` now keeps the API's URL beside the token, in
`~/.config/xymon-api/NAME.url`, and sends a token only to that URL. What
breaks: on a machine connected before, the first `xymonapi-connect URL`, or
`xymonapi-mcp register URL`, asks your password again, once, and keeps a new
token, which replaces the one before on that server; a token kept for
another server stays valid there until its `/tokens` revokes it.
The same server reached by another URL asks it too. Then the agent and
`xymonapi-rag` find the API with no `XYMONAPI_URL` set.

## The relay socket moves to Xymon's runtime directory, from xymonapi 5.0.0

The web server's relay socket is now `$XYMONRUNDIR/xymonapi/relay.sock`,
in the directory Xymon keeps for its sockets, or in its log directory,
`$XYMONSERVERLOGS`, when `XYMONRUNDIR` is empty, as Xymon does. It was
`$XYMONHOME/tmp/xymonapi-relay/relay.sock`. The socket for the server's
own programs is beside it, `$XYMONRUNDIR/xymonapi/local/api.sock`; it was
`$XYMONVAR/xymonapi/api.sock`, and the clients look only at the new path.
The install reads the directory
from `$XYMONHOME/etc/xymonserver.cfg` and replaces a 4.0.0 snippet it finds
unedited. What breaks: a snippet you edited is kept, and the install says
it differs: put the new socket path in it. Where `XYMONRUNDIR` names a
variable the install cannot read, the snippets keep `@XYMONRUNDIR@`, and
the install says to put the directory there. An SSH tunnel goes to the new
path. Setting `XYMONAPI_RELAY_SOCKET` keeps the socket where you name it.

## The web server reaches the API on its relay socket, from xymonapi 4.0.0

The API now also answers on a Unix socket for the web server,
`$XYMONHOME/tmp/xymonapi-relay/relay.sock` (`XYMONAPI_RELAY_SOCKET`), in plain
HTTP whether port 1986 speaks HTTPS or not, asking the same password or
token; the web server's snippets pass `/xymon/api/` there. Before, they
passed it to `127.0.0.1:1986` in plain HTTP, which failed with a 502 where
1986 speaks HTTPS, as it does by itself once xymond's certificate is in
`etc/tls/`. An install replaces a snippet it finds as an older version
shipped it; one you edited is kept, and the install says it differs: put the new
`ProxyPass`, `proxy_pass` or `proxy.server` line in it, from the snippet
the plugin ships. The snippets need Apache 2.4.7, or lighttpd
1.4.36, or later. An SSH tunnel can go to the socket too:
`ssh -L 1986:$XYMONHOME/tmp/xymonapi-relay/relay.sock HOST`.

What breaks: a path with a trailing slash, which redirected to the one
without, is now not_found -- a redirect would send a client behind a web
server back to http://. And there is no relay where the socket's
directory, or one on the way to it, can be changed by anyone but root and
the Xymon user: the API runs on, says why in its log, and `/health` says
`"relay": "refused"`; the log names the directory, and the group that may
write it. On Homebrew, `/opt/homebrew`'s directories -- `opt`, `Cellar`,
`var` -- are writable by the `admin` group, by Homebrew's design: set
`XYMONAPI_RELAY_TRUSTED_GROUPS=admin` in `xymonserver.d/`, if every admin is
trusted with the API's passwords.
`XYMONAPI_RELAY_SOCKET` set empty turns the relay off.
Under SELinux, as with Xymon's RPM on RHEL, Apache must be allowed to
connect to the socket: from xymonapi 5.0.1 the install loads a module
for it, its boolean off, `setsebool -P xymonapi_relay on`.

## Every install action names its side, install.sh from November 2026

`./install.sh install`, `uninstall`, `venv`, `enable`, `disable` and
`status`, the server actions without `-server`, are refused, naming the
action with a side: `install-server`, `uninstall-server`, `venv-server`,
`enable-server`, `disable-server`, `status-server`, and for the first
three and `status` the `-tools` ones too. A script that used a short
spelling adds `-server`. Nothing installed changes. The plain verbs are
`xymon-plugin`'s, the command SPEC.md plans to replace `install.sh`.

## The server actions need a Xymon server's tree, install.sh from November 2026

Every server action -- `install-server`, `enable-server`,
`disable-server`, `status-server`, `uninstall-server`, `venv-server` --
now reads the tree `XYMONHOME` names for a server's two marks,
`etc/xymonserver.cfg` and `bin/xymond`, and refuses it before changing
anything when they are not both there: a client's tree, part of a pair, or
a directory that is no Xymon tree at all. An install into an empty
directory, which used to make one, is refused; to stage the plugins for a
package, set `DESTDIR`, under which no marks are read. A plugin left in a
tree whose Xymon is already gone is removed by deleting `ext/NAME`. A real
server, packaged or built from source, needs nothing.

## A password file is needed, from xymonapi 3.0.0

With `XYMONAPI_PASSWD` not set and no `$XYMONHOME/etc/xymonpasswd`, the API
answered anyone who reached it. It now does not start, and says why. A
missing file -- a configuration kept from an older install that does not
read `xymonserver.d/`, a new install without the web pages' passwords --
no longer opens the API without a word. Create the file with `htpasswd`,
name another in `XYMONAPI_PASSWD`, or, for an API open to anyone who
reaches it, set `XYMONAPI_PASSWD=""` in a file under `xymonserver.d/`.

## Server tasks on and off, by a link, from xymonapi 2.4.0

A plugin's task is no longer turned on by removing `DISABLED` from its
file: it is on when `etc/tasks.d/NAME` links to `ext/NAME/tasks.cfg`, which
`XYMONHOME=... ./xymon-plugin enable --server NAME` makes and `disable-server
NAME` removes. The first install with this version keeps each task as it
was: one still `DISABLED` stays off and loses that line, and says how to
turn it on; one you enabled stays on. A script that enabled a task by
editing its file runs `enable-server` instead.

## The install actions, from xymonapi 2.3.0

`./install.sh install-client`, `uninstall-client` and `venv-client` are now
`install-tools`, `uninstall-tools` and `venv-tools`: what they install are
the plugins' commands, on your own machine, and "client" is Xymon's word for
a monitored host. The old names are refused, saying the new one. The server
actions gain `-server` -- `install-server`, `uninstall-server`,
`venv-server` -- and keep their old spellings. What is installed, and where,
is unchanged: an install over the old one needs nothing more. In a
`PLUGIN` file, `client-files`, `client-manual`, `client-modules` and
`uninstalled-client` are `tools-files`, `tools-manual`, `tools-modules` and
`uninstalled-tools`. The directory the server stages the plugins in for
`/plugins`, `ext/xymon-plugins-client`, is `ext/xymon-plugins-dist`; a
server install renames nothing, so remove the old directory by hand after
the first install with this version, or leave it: nothing reads it.

## Every plugin's install, from xymonapi 2.2.0

The plugins install with `./install.sh` at the repository's top, and `make`
is no longer used: the `Makefile`s are gone. What was
`make install XYMONHOME=...` in `plugins/NAME` is
`XYMONHOME=... ./install.sh install NAME`; `make install-client`,
`make uninstall`, `make uninstall-client`, `make venv` and
`make venv-client` are the same words after `./install.sh`, and with no
`NAME` they act on every plugin of the side, as the top `Makefile` did.
`PREFIX`, `MANDIR`, `DESTDIR` and `PYTHON` mean what they meant, from the
environment or as `NAME=value` arguments. What is installed, and where, is
unchanged: an install over the old one needs nothing more. The tests run
with `tests/run.sh` instead of `make test`.

## xymonapi 2.0.0

An API started before its launcher named it by its full path -- one whose
`pgrep -lf app.py` line shows a bare `app.py` -- is not found by the install,
which from now on stops the running API itself, and keeps running the old
code. Stop it once by its number, `kill PID`; xymonlaunch starts the new
one, which the next install finds.

`/client` is now `/plugins`, what it gives unchanged: the plugins installed
on the server, as a `.tar.gz`. Machines already installed need nothing; one
downloading the code from the server asks for
`https://SERVER/xymon/api/v1/plugins` instead.

## xymonapi 1.0.0

`/client` gives the code of the plugins installed on the server, as a
`.tar.gz`, instead of a setup script; its `name` and `format` options, and
the settings `XYMONAPI_PUBLIC_URL` and `XYMONAPI_REPO`, are gone. Machines
already set up keep their token and registrations and need nothing. To set
up one, or redo it: get the code -- from `/client` or a clone -- run
`make install-client` in `plugins/xymonapi-mcp`, then
`xymonapi-mcp register URL` (or `xymonapi-connect URL` for the API alone).
On the server, `make install` at the repository's top now also stages
`xymonapi-mcp` there, for `/client`.

## xymonapi-mcp, xymonapi-rag 0.1.0

The clients send a token and nothing else: `XYMONAPI_USER`,
`XYMONAPI_PASSWORD` and `XYMONAPI_PASSWORD_FILE` are no longer read. A
machine set up with a password gets 401: run `xymonapi-connect`, which gets
it a token.

## xymonapi 0.1.0

A user removed from the password file loses every client token at the first
use of one; putting the user back does not bring them back. Each of that
user's machines runs `xymonapi-connect` again for a new token.
