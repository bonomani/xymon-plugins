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
