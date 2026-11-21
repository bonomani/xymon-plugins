# xymonapi-rag

It finds the passages of Xymon's manual pages and history that a question is
about, by what they mean rather than the words they share.

## Install

| part | command |
|---|---|
| server | `XYMONHOME=/usr/lib/xymon/server ./xymon-plugin install --server xymonapi-rag` |
| tools | `./xymon-plugin install --tools xymonapi-rag` |

The server task is installed off; turning it on is in
[On the Xymon server](#on-the-xymon-server).

## Use

| to | run |
|---|---|
| search, from a shell on the server | `xymoncmd /usr/lib/xymon/server/ext/xymonapi-rag/xymonapi-rag.sh search "what does purple mean"` |
| search, from your machine | `xymonapi-rag search "what does purple mean"` |
| ask a language model about the passages found | `xymonapi-rag ask "has /boot filled up before, and where?"` |
| search through the API | its `/search` |

Every command and setting is in [`xymonapi-rag.1`](xymonapi-rag.1).

## Needs

- **[`xymonapi`](../xymonapi/README.md)**: on the server, the API; elsewhere,
  its client library. Either install here brings the one it needs.
- Python 3.9 or later; the modules in [`requirements.txt`](requirements.txt)
  on the server and on a machine that keeps an index of its own.

## Reference

Every command, setting and file: [`xymonapi-rag.1`](xymonapi-rag.1).

- On the server, the index task reads the history with `xymonapi`'s code.

### On the Xymon server

- Turn the task on as [`xymonapi-rag.1`](xymonapi-rag.1) says (`index`);
  the API's own task must run too, for the search to be served.
- The first index run takes about a minute; later runs take seconds.
- `./xymon-plugin remove --server xymonapi-rag` keeps the index.
- As the Xymon user, `search` reads the task's index; otherwise it asks the
  API through `$XYMONRUNDIR/xymonapi/local/api.sock`. Without `xymoncmd`,
  set `XYMONAPI_URL=unix:` followed by that path.

### On your own machine

```sh
set -a; eval "$(xymonapi-connect https://xymon.example.ch)"; set +a
```

- `xymonapi-connect`, installed with the API's client library, prints the
  settings `xymonapi-rag` reads; the `eval` puts them in the shell.
- The URL is the API's as this machine reaches it, port included when not
  443 ([`xymonapi`'s README](../xymonapi/README.md#reaching-it-from-another-machine)).
- It gets this machine its token with your password once
  ([`xymonapi`'s README](../xymonapi/README.md#on-your-own-machine)).
- `./xymon-plugin remove --tools xymonapi-rag` keeps any index here.

### `ask` and `eval`

- LM Studio works with two settings.
- Pick the model with care: a small one such as `llama3.2` answers in a
  second but makes things up; a larger one says when the passages do not
  hold the answer.
- [`tests/eval/docs.json`](../../tests/eval/docs.json) is the question file
  CI runs.
