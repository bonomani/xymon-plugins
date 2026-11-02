# xymonapi-rag

A search of Xymon's manual pages and its history by meaning: it finds the
passages a question is about, by what they mean rather than the words they
share. The index lives on the Xymon server, where the pages and the history
are; the [API](../xymonapi/README.md) serves it at `/search`, and the
[MCP server](../xymonapi-mcp/README.md)'s `search_docs` and `search_history`
ask it there. Every command and setting is in
[`xymonapi-rag.1`](xymonapi-rag.1).

## On the server

`make install` puts it in `$XYMONHOME/ext/xymonapi-rag/`, with the
`xymonapi-mcp` it reads the API with, its manual page in
`$MANDIR/man1/`, and a daily `xymonlaunch` task, `tasks.d/xymonapi-rag`,
written `DISABLED`. To enable it:

1. install the modules in [`requirements.txt`](requirements.txt) for the
   Xymon user;
2. put `XYMONAPI_RAG_DOCS` -- a directory with Xymon's manual pages;
   `/usr/share/man` will do -- in a file under `xymonserver.d/`;
3. remove `DISABLED` from the task.

The task reads the history from xymond's own files, as the API does: it needs
no user, password or token. The first run downloads a 65 MB embedding model,
which `XYMONAPI_RAG_OFFLINE` can forbid once the cache is seeded, and takes
about a minute; the next ones embed only what is new and take seconds. The
index holds the last 30 days of history, the newest 5000 changes at most, and
the API serves it as soon as it is written.

## Anywhere with access to the API

```sh
xymonapi-rag search "what does purple mean"
xymonapi-rag ask "has /boot filled up before, and where?"
```

`make install-client` installs it on a laptop, as the setup script does.
`search` uses the server's index when there is none here. `ask` hands the
passages to a language model speaking the OpenAI-compatible API -- a local
Ollama by default, LM Studio with two settings. Pick the model with care: a
small one such as `llama3.2` answers in a second but makes things up, where a
larger one says when the passages do not hold the answer. With an MCP
client, its tools are the simpler way.

`eval` scores the search against a file of questions;
[`tests/eval/docs.json`](../../tests/eval/docs.json) is the one CI runs.
