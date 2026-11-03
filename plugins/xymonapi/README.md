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
- Python 3.9 or later, with the modules in
  [`requirements.txt`](requirements.txt): how the install finds or makes a
  Python with them is in the [top README](../../README.md#installing).
- `rrdtool`, for `/series`; a web server running Xymon's CGI programs at
  `XYMONSERVERCGIURL`, for `/graphs`; Apache's `htpasswd`, when a password
  file is used.

## On the server

```sh
make install XYMONHOME=/usr/lib/xymon/server
```

Besides the code, the task and the manual page, which every plugin
installs ([top README](../../README.md#installing)), it writes once the web
server snippets `$XYMONHOME/etc/xymonapi-{apache,nginx,lighttpd}.conf`, for
[other machines](#reaching-it-from-another-machine), and keeps them after.
Xymon's own install links `$XYMONHOME/ext` and `$XYMONHOME/etc` to wherever
those really are -- `/etc/xymon` on many installations -- so the files land
there; with `DESTDIR`, the staged directories are plain ones.

Then remove `DISABLED` from `$XYMONHOME/etc/tasks.d/xymonapi`, and check:

```sh
curl http://127.0.0.1:1986/xymon/api/v1/health              # the port: 401 means it runs and asks for a user
curl --unix-socket "$XYMONVAR/xymonapi/api.sock" http://localhost/xymon/api/v1/health
```

The port asks for one of its [users](#users), `-u alice`, whatever the
address. The socket, `$XYMONVAR/xymonapi/api.sock`, is for the programs of
the server itself and asks none: its permissions let the Xymon user and its
group in, and nobody else. The plugins' own clients take it by default
there (`xymonapi.8`, `XYMONAPI_SOCKET`).

Updating: install again, then `pkill -f "$XYMONHOME/ext/xymonapi/"`; the
running API keeps the old code until then, and xymonlaunch starts the new.
`make uninstall XYMONHOME=...` keeps the snippets -- take the `Include` out
of your web server's configuration before deleting them -- and the tokens
file, `$XYMONAPI_TOKENS`.

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

## Reaching it from another machine

Its port listens on 127.0.0.1 unless told otherwise, and asks the password
there whatever the address; the socket above never leaves the machine. From
another machine, use HTTPS, one of -- each with the URL a client is then
given, in `xymonapi-connect`, `register` or `XYMONAPI_URL`: the scheme, the
host and the port, without `/xymon/api/v1`, which the client adds:

- **Its own HTTPS.** Where xymond has a certificate for TLS (`xymon-tls(7)`,
  from Xymon pull requests #617–#623, not yet merged), the API finds it in
  `etc/tls/` and speaks HTTPS by itself; or name any certificate and key in
  `XYMONAPI_TLS_CERT` and `_KEY`. Open the port with
  `XYMONAPI_LISTEN="0.0.0.0:1986"`. The URL: `https://xymon.example.ch:1986`.
- **The web server in front of it.** Include the snippet `make install` wrote
  for your web server, `$XYMONHOME/etc/xymonapi-*.conf`, in its HTTPS part:
  one hostname for the pages and the API. The URL: the web server's,
  `https://xymon.example.ch`, with its port when that is not 443, as in
  `https://xymon.example.ch:8443`.
- **An SSH tunnel**, for one person:
  `ssh -L 1986:127.0.0.1:1986 xymon-server`. The URL:
  `http://127.0.0.1:1986`, as if local.

Plain HTTP across a network carries the password, the tokens and the status
texts readable, as port 1984 does: keep it to a network where the Xymon pages
themselves are plain and trusted. Whichever you choose, keep secrets out of
the texts: `XYMONAPI_HIDE` names a file of regular expressions whose matches
come out as `[hidden]`, in every text and in the search index.

## On another machine

A machine that reads the API -- a laptop, say -- needs its client and a
token of its own, and for that `make`, `curl` and Python 3.9 or later,
nothing else:

```sh
# Only when the certificate is the server's own, not one the machine trusts:
# copy it where xymonapi-connect looks, over a channel you already trust.
mkdir -p ~/.config/xymon-api
scp xymon.example.ch:/etc/xymon/tls/xymond.pem ~/.config/xymon-api/xymon-ca.pem

cd xymon-plugins/plugins/xymonapi        # the code: top README, Getting the code
make install-client                      # under ~/.local; PREFIX=... for elsewhere
xymonapi-connect https://xymon.example.ch   # the URL: as reached, above
```

`xymonapi-connect` asks for your user and password once -- one of the API's
[users](#users) -- to get this machine a token, kept in
`~/.config/xymon-api/xymon.token`; the password is not kept. Run again, it
keeps a token that works, says when this machine's client and the API run
different versions, and prints the settings a program reading the API
needs. A second server gets a name of its own:
`xymonapi-connect https://lab.example.ch xymon-lab`. `/tokens` lists your
machines and revokes one, and removing a user from the password file
revokes all of theirs. Every detail is in
[`xymonapi-connect.1`](xymonapi-connect.1).

`make uninstall-client` keeps the token: revoke it with `/tokens`, or delete
`~/.config/xymon-api/xymon.token`.
