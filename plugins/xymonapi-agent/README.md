# xymonapi-agent

One command that asks an AI agent a question about Xymon and prints the
answer, with no one at the keyboard:

```sh
xymonapi-agent ask "which hosts are red, and since when?"
```

The agent is one of the coding agents you may already have on the machine
-- Claude Code, Codex or opencode -- run in its non-interactive mode with
[`xymonapi-mcp`](../xymonapi-mcp/README.md) as its only tool: the read-only
tools over the Xymon API, nothing else. Where `xymonapi-mcp` serves a person
typing into one of those agents, this serves a script: a cron job that mails
a morning summary, an alert script that attaches an explanation, a chat bot
that relays questions from a phone.
Every command, backend and setting is in
[`xymonapi-agent.1`](xymonapi-agent.1).

## Needs

- **[`xymonapi-mcp`](../xymonapi-mcp/README.md)** beside it, which
  `make install-client` installs first, with `xymonapi`'s client -- and so a
  running [`xymonapi`](../xymonapi/README.md) on the Xymon server, reached as
  that README says. For the two search tools, `search_docs` and
  `search_history`, the server also runs
  [`xymonapi-rag`](../xymonapi-rag/README.md)'s index task; without it those
  two tools answer that there is no index, and the agent says so.
- **One agent CLI, installed and logged in by its own means**: Claude Code
  (`claude`), Codex (`codex`) or opencode (`opencode`). This plugin only
  runs it; it has no model of its own and no API key.
- Python 3.9 or later, and nothing else.

## Installing

```sh
cd xymon-plugins/plugins/xymonapi-agent   # the code: top README, Getting the code
make install-client                       # under ~/.local; PREFIX=... for elsewhere
xymonapi-mcp register https://xymon.example.ch   # once: connects this machine to the API
xymonapi-agent backends                   # which CLI is here, and which answers
xymonapi-agent doctor                     # one question through the tools
```

`register` is `xymonapi-mcp`'s: it connects this machine to the API with
your password once, for a token of its own, and keeps the settings this
command hands to the MCP server. What it also registers with Claude Code and
Codex is for your own use of those agents; this command gives them the MCP
server itself, on each call, and tells Claude Code to use no other.

With one agent CLI on PATH, it is the one that answers. With several, name
it once:

```sh
export XYMONAPI_AGENT_BACKEND=claude     # or codex, opencode; --backend for one call
```

## Using it

```sh
xymonapi-agent ask "why is disk red on db02?"
xymonapi-agent ask --session nightly "what changed since yesterday evening?"
xymonapi-agent ask --session nightly "and which of those are still not green?"
xymonapi-agent ask --json "is anything red?" | jq -r .answer
```

`--session NAME` continues a conversation: the second question follows on
from the first. Claude Code continues a named session; with Codex and
opencode a named session starts fresh each time, and stderr says so --
their session ids are not stable enough in their documentation to keep.

## How far each backend is held to the tools

The point of the plugin is that the agent reads Xymon through the MCP
server and does nothing else: no shell, no files, no web. A status text
comes from the monitored host, and a compromised host could write an
instruction into it; the system prompt says such text is data, and the
backend's flags are what make sure an instruction, if followed, has
nothing to reach. The three differ:

| backend | how it is held | how complete |
|---|---|---|
| `claude` | `--strict-mcp-config` (this MCP server, no other), `--tools ""` (no built-in tool), `--allowedTools mcp__xymon__*`, `--permission-mode dontAsk` | complete, as its documentation states each flag |
| `opencode` | a configuration file of its own for the call, project configuration disabled: the MCP server, every tool denied but `xymon_*`, an agent with the system prompt | by configuration; your global `opencode` config still merges with it |
| `codex` | `--sandbox read-only`, overrides that give it the MCP server and turn its shell tool and web search off, `--ephemeral` | partial: the documentation does not promise the shell is gone, so the token file may be readable to the model |

`xymonapi-agent backends` prints the same for the machine it runs on;
`doctor` asks one question that only the health tool can answer. Prefer
`claude` where the API's token must not be readable to the model, and
`opencode` with a local model where the status texts must not leave the
machine. With Claude Code and Codex they go to the vendor's API, as they
do when you type the question yourself.

## In a script

The answer is text on stdout, and the exit status says whether there was
one: 0 for an answer, 1 when the backend failed or none is chosen, 77 when
no Python 3.9 is here. With `--json`, one object with `backend`, `session`
and `answer`. A morning summary, in cron:

```sh
7 7 * * 1-5  xymonapi-agent ask "Summarise what went red or yellow in the last 24 hours, by host, and what is still not green." | mail -s "Xymon overnight" ops@example.ch
```

## Relation to `xymonapi-rag ask`

[`xymonapi-rag ask`](../xymonapi-rag/README.md) also answers a question,
from the passages its search finds, through an OpenAI-compatible endpoint
and a model you run; it has no tools, and needs no agent CLI. This command
answers with the tools -- it can read the board, the history and the
searches, and decide which -- and needs one of the three agents. Use
`xymonapi-rag ask` for "has this been seen before, and where?" with a local
model and nothing else installed; use this for anything that needs the
board's state now.
