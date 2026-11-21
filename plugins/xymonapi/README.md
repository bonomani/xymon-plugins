# xymonapi

A read-only HTTP/JSON API to a Xymon server: the status board, its alarms and
hosts, RRD values and graphs, and the history of colour changes. It changes
nothing in Xymon. The other API plugins, and your own scripts, read Xymon
through it.

## Install

| part | where | command |
|---|---|---|
| server | the Xymon server: the API, a `xymonlaunch` task | `XYMONHOME=/usr/lib/xymon/server ./xymon-plugin install --server xymonapi` |
| tools | any machine that reads the API: `xymonapi-connect` and the client library | `./xymon-plugin install --tools xymonapi` |

- The server task is installed off: `XYMONHOME=/usr/lib/xymon/server ./xymon-plugin enable --server xymonapi`.
- Its users are those of Xymon's web password file: see [Users](#users).
- From another machine: see [Reaching it from another machine](#reaching-it-from-another-machine).

## Use

| to | type |
|---|---|
| check it runs, on the server | `curl http://127.0.0.1:1986/xymon/api/v1/health` (401: it runs and asks for a user) |
| give your machine a token | `xymonapi-connect https://xymon.example.ch` |
| read the board | `GET /xymon/api/v1/alarms`, with the token |
| list or revoke your machines' tokens | `/xymon/api/v1/tokens`, with your password |
| ask a question in words | `POST /xymon/api/v1/ask`, see [/ask](#asking-in-words-ask) |

Every operation: [`xymonapi.8`](xymonapi.8) and [`openapi.yaml`](openapi.yaml).

## Needs

- Server: Xymon 4.3.31 or later; Python 3.9 or later with
  [`requirements.txt`](requirements.txt); `rrdtool` for `/series`; Xymon's
  CGI programs on a web server for `/graphs`.
- Your machine: a POSIX shell, `curl` and Python 3.9 or later.
- No language model: see [A language model](#a-language-model).

## Reference

Every operation, setting, file and door of the API: [`xymonapi.8`](xymonapi.8);
of `xymonapi-connect`: [`xymonapi-connect.1`](xymonapi-connect.1).
[`openapi.yaml`](openapi.yaml) is the contract: each path's exact answers,
the closed list of errors, and the numbered rules every implementation keeps.

### The API and what builds on it

Three plugins build on the API:

| plugin | on the Xymon server | on your own machine | needs |
|---|---|---|---|
| [`xymonapi-mcp`](../xymonapi-mcp/README.md) | nothing runs: the plugin is staged for `/plugins` | an MCP server that gives an AI tool read-only tools over the API | xymonapi >= 0.1.0 beside it; the API's socket on the server, or the API over the network; python >= 3.9 |
| [`xymonapi-rag`](../xymonapi-rag/README.md) | the daily index of Xymon's manual pages and history, served at `/search` | `xymonapi-rag search` and `ask`: the same search, by meaning, from anywhere | xymonapi >= 0.1.0 beside it; python >= 3.9; a language model only for `ask` |
| [`xymonapi-agent`](../xymonapi-agent/README.md) | `/ask`: the API answers a question in words, off by default | `xymonapi-agent`: one command that asks an AI CLI -- Claude Code, Codex or opencode, headless -- with the MCP server as its only tool | xymonapi-mcp >= 0.1.0 beside it; one of the AI CLIs, installed and logged in; python >= 3.9 |

- The API is the line between the Xymon server and your own machine.
- On the server, the API, the daily index and `/ask` run as the Xymon user,
  read xymond's own files, and need no credential.
- On your own machine, everything goes through the API, with a token or, on
  the server itself, its socket.
- **No language model is needed for the monitoring data to reach your AI
  tool**: only `xymonapi-agent`, `/ask` and `xymonapi-rag ask` call one.

### A language model

Three things call one, each its own:

- **Your AI tool's**, with the MCP server: a subscription, an API key of
  yours, or a local model. The Xymon server knows nothing about it. What the
  tools return, status texts included, goes to that tool's provider; with a
  local model it stays on your machine.
- **The server's**, for `/ask`: the Xymon user's AI CLI needs a backend -- a
  hosted provider with an API key, a local model on the server (Ollama, LM
  Studio), or one on another machine of yours, by URL -- named by a profile
  under that user's `~/.config/xymonapi-agent/agents/`, as
  [`xymonapi-agent`'s README](../xymonapi-agent/README.md#agents-another-xymon-another-tool-set)
  shows. With none, `/ask` stays off and everything else works.
- **A model you run**, for `xymonapi-rag ask`: an OpenAI-compatible
  endpoint, Ollama by default, named by `XYMONAPI_RAG_LLM_URL`; no tools,
  no CLI.

### On the Xymon server

- How the install finds or makes its Python:
  [`xymon-plugin`'s README](../xymon-plugin/README.md#python).
- With `DESTDIR`, the staged `ext` and `etc` are plain directories, not links.
- On the server, the socket asks no password:
  `curl --unix-socket /run/xymon/xymonapi/local/api.sock http://localhost/xymon/api/v1/health`
  (the path the install printed).
- Update: `XYMONHOME=... ./xymon-plugin update --server xymonapi`; the API
  restarts on the new code by itself. One older than 9.1.0 does not: see
  [UPGRADING.md](../../UPGRADING.md).
- `./xymon-plugin remove --server xymonapi` keeps the tokens file,
  `$XYMONAPI_TOKENS`.

### Asking in words: /ask

- `./xymon-plugin install --server xymonapi-agent` brings `xymonapi-mcp` too.
- Phones, bots and web pages then need only the API's URL and a token.
- Settings, limits and sessions: [`xymonapi.8`](xymonapi.8), `POST /ask` and
  `XYMONAPI_ASK`.

### Users

- Add one with Xymon's `useradm.cgi`, or by hand:
  `htpasswd -B "$XYMONHOME/etc/xymonpasswd" alice`.
- The API reads the file at each request: nothing to restart.
- The file, `XYMONAPI_PASSWD` and tokens: [`xymonapi.8`](xymonapi.8).

### Reaching it from another machine

Use HTTPS, one of three ways: the API's own (`XYMONAPI_TLS_CERT`), the web
server's snippets, or an SSH tunnel; each, and the URL a client is then
given: [`xymonapi.8`](xymonapi.8), NOTES and `XYMONAPI_RELAY_SOCKET`.

- Own HTTPS: `XYMONAPI_LISTEN="0.0.0.0:1986"` opens the port to other machines.
- Web server: Apache 2.4.7, nginx, or lighttpd 1.4.36 or later; one
  hostname for the pages and the API. A plain include (not `IncludeOptional`
  or a wildcard) of a snippet that is gone stops Apache and lighttpd from
  starting.
- On Homebrew, trust `XYMONAPI_RELAY_TRUSTED_GROUPS=admin` only if every
  admin may see the API's passwords.
- Plain HTTP across a network carries the password, the tokens and the
  status texts readable, as port 1984 does: keep it to a network where the
  Xymon pages themselves are plain and trusted.
- Keep secrets out of the texts with `XYMONAPI_HIDE`.

### On your own machine

```sh
# Only when the certificate is the server's own, not one the machine trusts:
# copy it where xymonapi-connect looks, over a channel you already trust.
mkdir -p ~/.config/xymonapi
scp xymon.example.ch:/etc/xymon/tls/xymond.pem ~/.config/xymonapi/xymon-ca.pem
```

- `./xymon-plugin install --tools xymonapi` installs under `~/.local`;
  `PREFIX=...` for elsewhere.
- `./xymon-plugin remove --tools xymonapi` keeps the token: revoke it with
  `/tokens`, or delete `~/.config/xymonapi/xymon.token`.
- Everything else: [`xymonapi-connect.1`](xymonapi-connect.1).
