# xymonapi

The Xymon API gives, over HTTP and as JSON, the status board, its alarms
and hosts, the values in its RRD files, the graphs drawn from them, and the
history of colour changes with the status text saved at each. It only
reads, and changes nothing in Xymon. It runs on the server as one of
Xymon's `xymonlaunch` tasks, with Xymon's own settings.

Its operations, under `/xymon/api/v1`, all GET but for `/tokens`:

| path | gives |
|---|---|
| `/health` | whether xymond answers, its version, the search index, this API's version |
| `/states`, `/alarms`, `/entities` | the board, what is not ok, the hosts |
| `/status` | one test's current status, text and acknowledgement included |
| `/series`, `/graphs` | the values of one RRD dataset; the PNG showgraph draws |
| `/events`, `/histlog` | the colour changes, newest first; the status text saved at one |
| `/search` | the manual-page and history passages nearest a question, when the server has a search index |
| `/client` | the code of the plugins installed here, for other machines to install from |
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
`make install-client` installs only the API's client, for another machine:
see [Setting up another machine](#setting-up-another-machine).

| installed | from |
|---|---|
| `$XYMONHOME/ext/xymonapi/`: the code, `openapi.yaml`, `requirements.txt` and the launcher `xymonapi.sh` | this directory |
| `$XYMONHOME/ext/xymonapi/VERSION`, which `/health` gives | `version` in [`PLUGIN`](PLUGIN) |
| `$XYMONHOME/etc/tasks.d/xymonapi`, the task, written `DISABLED`, and only when there is none | `xymonapi.tasks.DIST` |
| `$XYMONHOME/etc/xymonapi-{apache,nginx,lighttpd}.conf`, web server snippets, written once | the files of the same name |
| `$MANDIR/man8/xymonapi.8` | [`xymonapi.8`](xymonapi.8) |
| `$XYMONHOME/ext/xymon-plugins-client/plugins/xymonapi/`, what `/client` serves | this directory, without its tests |

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

A `401` means it runs and asks for a user: add `-u` with one of its users
(see [Users](#users)).

## Users

The API's users are those of Xymon's own web password file,
`$XYMONHOME/etc/xymonpasswd`: the same names and passwords as the Xymon web
pages. Add one with Xymon's `useradm.cgi`, or by hand:

```sh
htpasswd -B "$XYMONHOME/etc/xymonpasswd" alice
```

The API reads the file at each request: nothing to restart. Without that
file, the API asks for no password at all -- fine while it listens on
127.0.0.1 alone, not once other machines reach it. `XYMONAPI_PASSWD` names
another file, as `xymonapi.8` says.

## Updating

```sh
git pull && make install XYMONHOME=...      # in the checkout, as before
pkill -f "$XYMONHOME/ext/xymonapi/"          # the running API keeps the old code until then
```

The install replaces the plugin's directory and keeps the task file you
enabled, the web server snippets and your settings; xymonlaunch starts the
new code once the old process is gone. A machine that installed from
`/client` gets the new code by downloading it again and running
`make install-client`; `xymonapi-connect`, run there, says whether it is
behind. What an update would bring, before pulling:
`git fetch -q && git log --oneline HEAD..origin/stable`.

## Uninstalling

```sh
make uninstall XYMONHOME=...
```

Run here, it removes the API alone, and is refused, naming the plugin, while
another installed one needs it; at the repository's top, every server-side
plugin. It removes the code, what `/client` serves of it, the manual page
and the task. It keeps the web server snippets -- take the `Include` out of
your web server's configuration before deleting them -- and the tokens
file, `$XYMONAPI_TOKENS`.
`make uninstall-client` removes the client, refused in the same way.

## Reaching it from another machine

It listens on 127.0.0.1 unless told otherwise. From another machine, use
HTTPS, one of:

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

## Setting up another machine

A machine that reads the API -- a laptop, say -- needs its client and a
token of its own, and for that `make`, `curl` and Python 3.10 or later,
nothing else. Get the code from this server, at its versions, or from a
clone of this repository:

```sh
# Only when the certificate is the server's own, not one the machine trusts:
# copy it where xymonapi-connect looks, over a channel you already trust.
# Otherwise leave out these two lines and the --cacert option below.
mkdir -p ~/.config/xymon-api
scp xymon.example.ch:/etc/xymon/tls/xymond.pem ~/.config/xymon-api/xymon-ca.pem

curl --cacert ~/.config/xymon-api/xymon-ca.pem \
  https://xymon.example.ch/xymon/api/v1/client | tar xz
cd xymon-plugins/plugins/xymonapi
make install-client                       # under ~/.local; PREFIX=... for elsewhere
xymonapi-connect https://xymon.example.ch
```

Never `-k`: code fetched without checking the certificate could be
anyone's. `/client` asks for no password: it holds the code and nothing
secret.

`make install-client` puts the client under
`$PREFIX/libexec/xymon-plugins/xymonapi` and the command `xymonapi-connect`
in `$PREFIX/bin`. `xymonapi-connect` asks for your user and password once --
one of the API's [users](#users) -- to get this machine a token, kept in
`~/.config/xymon-api/xymon.token`; the password is not kept. Run again, it
keeps a token that works. It says when this machine's client and the API
run different versions, and prints the settings a program reading the API
needs. A second server gets a name of its own:
`xymonapi-connect https://lab.example.ch xymon-lab`. `/tokens` lists your
machines and revokes one, and removing a user from the password file
revokes all of theirs. Every detail is in
[`xymonapi-connect.1`](xymonapi-connect.1).
