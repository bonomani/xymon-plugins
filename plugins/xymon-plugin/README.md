# xymon-plugin

The installer of these plugins, and one of them: `./xymon-plugin` at the
repository's top, in a checkout or a release's archive, is a link to
`plugins/xymon-plugin/xymon-plugin`, which also runs as itself where links
are not kept (see the repository's README). Its verbs and settings are in the
repository's [README](../../README.md) and in [plugins/README.md](../README.md);
its manual page is [xymon-plugin(8)](xymon-plugin.8).

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
waits. What it does is in `xymon-plugin.log`, in Xymon's log directory.

Yellow and purple alert as any column: in `alerts.cfg`, `EXSERVICE=plugins`
on a rule keeps it out, or a rule of its own sends it elsewhere. Behind a
proxy, or to read GitHub with a token, set `https_proxy` or `GH_TOKEN` in a
file under `xymonserver.d/`, which the task reads; it reads GitHub with
`curl`, bounded in time, and not `gh`, which is not -- and `curl` sends the
token, which `wget`, used where `curl` is not there, does not.
