# xymonapi

A read-only HTTP and JSON interface to a Xymon server: the status board, its
alarms and hosts, the values in its RRD files, the graphs drawn from them,
and the history of colour changes with the status text saved at each. It
changes nothing in Xymon. It runs on the server as one of
Xymon's `xymonlaunch` tasks, with Xymon's own settings.

Its operations, under `/xymon/api/v1`, all GET but for `/tokens`:

| path | gives |
|---|---|
| `/health` | whether xymond answers, its version, the search index, this API's version |
| `/states`, `/alarms`, `/entities` | the board, what is not ok, the hosts |
| `/status` | one test's current status, text and acknowledgement included |
| `/series`, `/graphs` | the values of one RRD dataset; the PNG showgraph draws |
| `/events`, `/histlog` | the colour changes, newest first; the status text saved at one |
| `/search` | the manual-page and history passages nearest a question (`xymonapi-rag`) |
| `/client` | a setup script for a laptop, this API's address filled in |
| `/tokens` | a machine's own token, listed, made and revoked with your password |

[`xymonapi.8`](xymonapi.8) describes every operation and setting, for an
admin. [`openapi.yaml`](openapi.yaml), also served at `/openapi.json`, is the
contract: each path's exact answers, the closed list of errors, and the
numbered rules every implementation keeps.

## Requirements

- A Xymon server built from Xymon's current `main`: the API's settings go in
  `xymonserver.d/`, which no release reads yet; on 4.3.30 a file there is
  ignored, and with it the password the API should ask for.
- Python 3.10 or later, with the modules in
  [`requirements.txt`](requirements.txt).
- `rrdtool`, for `/series`; a web server running Xymon's CGI programs at
  `XYMONSERVERCGIURL`, for `/graphs`; Apache's `htpasswd`, when a password
  file is used.

## Installing

```sh
make install XYMONHOME=/usr/lib/xymon/server
```

Run here, it installs the API alone; run at the repository's top, every
server-side plugin. It writes into the Xymon server directory, so it is
normally run as root. `MANDIR` (default `/usr/share/man`) says where the
manual page goes, and `DESTDIR` stages the install for a package.

| installed | from |
|---|---|
| `$XYMONHOME/ext/xymonapi/`: the code, `openapi.yaml`, `requirements.txt` and the launcher `xymonapi.sh` | this directory |
| `$XYMONHOME/ext/xymonapi/VERSION`, which `/health` gives | the release tag, `xymonapi/vX.Y.Z`, when the checkout is at one, else `version` in [`PLUGIN`](PLUGIN) |
| `$XYMONHOME/etc/tasks.d/xymonapi`, the task, written `DISABLED`, and only when there is none | `xymonapi.tasks.DIST` |
| `$XYMONHOME/etc/xymonapi-{apache,nginx,lighttpd}.conf`, web server snippets, written once | the files of the same name |
| `$MANDIR/man8/xymonapi.8` | [`xymonapi.8`](xymonapi.8) |

Xymon's own install links `$XYMONHOME/ext` and `$XYMONHOME/etc` to wherever
those really are -- `/etc/xymon` on many installations -- so the files land
there. With `DESTDIR`, the staged directories are plain ones: a package built
from that stage should check how its tool installs a directory over a link.

The Python modules are not installed, and the user Xymon runs as must be
able to import them: install them system-wide, from your distribution's
packages for instance, or in a virtualenv that user can read, named in
`XYMONAPI_PYTHON`. `pip install --user` run as root puts them where that user
does not look.

Then remove `DISABLED` from the task, and check, with the default address:

```sh
curl http://127.0.0.1:1986/xymon/api/v1/health
```

A `401` means it runs and asks for a user: add `-u` with one of Xymon's
users.

To see whether the server runs the newest code, in the checkout
`make install` ran from:

```sh
git fetch -q && git log --oneline HEAD..origin/main
```

## Updating

```sh
git pull && make install XYMONHOME=...      # in the checkout, as before
pkill -f "$XYMONHOME/ext/xymonapi/"          # the running API keeps the old code until then
```

The install replaces the plugin's directory and keeps the task file you
enabled, the web server snippets and your settings; xymonlaunch starts the
new code once the old process is gone. Then run the setup script again on
each laptop, to bring its client to the same version.

## Uninstalling

```sh
make uninstall XYMONHOME=...
```

Run here, it removes the API alone, and is refused while `xymonapi-rag`,
which needs it, is installed; at the repository's top, every server-side
plugin. It removes the code, the manual page and the task. It keeps the web
server snippets -- take the `Include` out of your web server's configuration
before deleting them -- and the tokens file, `$XYMONAPI_TOKENS`.

## Reaching it from another machine

Xymon is what you look at when the rest is down, so the API depends on
nothing central: its password file and its certificate are Xymon's own,
files on the server. It listens on 127.0.0.1 unless told otherwise. From
another machine, use HTTPS, one of:

- **Its own HTTPS.** Where xymond has a certificate for TLS (`xymon-tls(7)`,
  from Xymon pull requests #617–#623, not yet merged), the API finds it in
  `etc/tls/` and speaks HTTPS by itself; or name any certificate and key in
  `XYMONAPI_TLS_CERT` and `_KEY`. Open the port with
  `XYMONAPI_LISTEN="0.0.0.0:1986"`.
- **The web server in front of it.** Include the snippet `make install` wrote
  for your web server in its HTTPS part: one hostname for the pages and the
  API.
- **An SSH tunnel**, for one person:
  `ssh -L 1986:127.0.0.1:1986 xymon-server`, then the API is at
  `http://127.0.0.1:1986` as if local.

Plain HTTP across a network carries the password, the tokens and the status
texts readable, as port 1984 does: keep it to a network where the Xymon pages
themselves are plain and trusted. Whichever you choose, keep secrets out of
the texts: `XYMONAPI_HIDE` names a file of regular expressions whose matches
come out as `[hidden]`, in every text and in the search index.

## On a laptop

A laptop needs `git`, `make`, `curl`, and Python 3.10 or later with its
`venv` module, which Debian and Ubuntu package apart, as `python3-venv`; on a
Mac, `git` and `make` come with the Xcode command-line tools. Ask the API for
its setup script, read it, run it:

```sh
# Only when the certificate is the server's own, not one the laptop trusts:
# copy it where the script looks, and name it to curl. Otherwise leave out
# these two lines and the --cacert options below.
mkdir -p ~/.config/xymon-api
scp xymon.example.ch:/etc/xymon/tls/xymond.pem ~/.config/xymon-api/xymon-ca.pem

# Optional: does the API answer here? Its "search" says if there is an index,
# how big and how old.
curl --cacert ~/.config/xymon-api/xymon-ca.pem -u me https://xymon.example.ch/xymon/api/v1/health

curl --cacert ~/.config/xymon-api/xymon-ca.pem https://xymon.example.ch/xymon/api/v1/client > xymon-setup.sh
sh xymon-setup.sh
```

Never `-k`: a script fetched without checking the certificate could be
anyone's.

`/client` asks for no password: the script holds the API's address and
nothing secret, not even the version the server runs. The address is
`XYMONAPI_PUBLIC_URL` when the server sets it, else the one the request came
through; set it on any server other machines reach. The script:

1. checks it reaches the API and trusts its certificate, and stops there,
   before asking anything, when it does not;
2. when the API asks for a password, asks for your user and password once,
   to get this machine a token of its own, named by its short hostname, and
   keeps the token in `~/.config/xymon-api/xymon.token`, not the password;
3. asks `/health` for the version the server runs, and installs the client
   side of that release -- or the newest code, when the server runs none;
4. makes a virtualenv with the `mcp` module, checks `/health` answers, and
   registers the MCP server with Claude Code and with Codex, each when it is
   installed.

Running it again keeps a token that still works and replaces one that does
not. `XYMONAPI_USER`, when set, is the user, not asked. `?name=xymon-lab`
gives a second server its own name and token file; `?format=env` gives the
two settings alone. `/tokens` lists your machines and revokes one, and
removing a user from the password file revokes all of theirs.

What the laptop runs then is [`xymonapi-mcp`](../xymonapi-mcp/README.md) and
[`xymonapi-rag`](../xymonapi-rag/README.md).
