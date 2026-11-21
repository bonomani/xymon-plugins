# xymonapi-agent

One command that asks an AI agent a question about Xymon and prints the
answer, with no one at the keyboard. It serves a script: a cron job, an
alert script, a chat bot. The agent is Claude Code, Codex or opencode, with
[`xymonapi-mcp`](../xymonapi-mcp/README.md) as its only tool.

## Installing

| part | where | command |
|---|---|---|
| tools | your own machine, as yourself | `./xymon-plugin install --tools xymonapi-agent` |
| server | the Xymon server, for the API's `/ask` | `XYMONHOME=... ./xymon-plugin install --server xymonapi-agent` |

Then, once on your machine: `xymonapi-mcp register https://xymon.example.ch`.

## Using it

| to | run |
|---|---|
| ask a question | `xymonapi-agent ask "which hosts are red, and since when?"` |
| continue a conversation | `xymonapi-agent ask --session nightly "..."` |
| get JSON | `xymonapi-agent ask --json "is anything red?" \| jq -r .answer` |
| see which CLI is here, and which answers | `xymonapi-agent backends` |
| check one question through the tools | `xymonapi-agent doctor` |
| list the agents defined | `xymonapi-agent agents` |
| ask another agent | `xymonapi-agent --agent lab ask "anything red?"` |
| choose the CLI | `export XYMONAPI_AGENT_BACKEND=claude` (or `--backend`) |

Every command, backend and setting: [`xymonapi-agent.1`](xymonapi-agent.1).

## Needs

- [`xymonapi-mcp`](../xymonapi-mcp/README.md), installed with it, and so a
  running [`xymonapi`](../xymonapi/README.md) on the Xymon server.
- One agent CLI, installed and logged in by its own means: `claude`,
  `codex` or `opencode`. This plugin has no model and no API key.
- Python 3.9 or later, and nothing else.

## Reference

Every command, profile key, backend flag, setting, file and exit status:
[`xymonapi-agent.1`](xymonapi-agent.1). What it lacks:

### Safety

- A status text comes from the monitored host; a compromised host could
  write an instruction into it. The backend's flags make sure that, if
  followed, it has nothing to reach.
- `codex` is held only partly: the token file may be readable to the model.
  Prefer `claude` where the token must not be.
- `opencode`: your global `opencode` config still merges with the plugin's.
- With Claude Code and Codex, status texts go to the vendor's API. Prefer
  `opencode` with a local model where they must not leave the machine.

### Setup details

- `install --tools` installs [`xymonapi-mcp`](../xymonapi-mcp/README.md)
  first, with `xymonapi`'s client library.
- `register` (`xymonapi-mcp`'s) uses your password once, for a token of its
  own, and keeps the API's URL beside it in `~/.config/xymonapi/`; this
  command and `xymonapi-rag` read it there when `XYMONAPI_URL` is unset.
  What it registers with Claude Code and Codex is for your own use: this
  command hands them the MCP server itself on each call.
- A second server: set `XYMONAPI_URL`, `XYMONAPI_TOKEN_FILE` and
  `XYMONAPI_CA` as `xymonapi-connect URL NAME` prints them, or write a
  profile.
- `search_docs` and `search_history` need the server to run
  [`xymonapi-rag`](../xymonapi-rag/README.md)'s index task; without it they
  answer that there is no index.

### On the Xymon server: `/ask`

- Off by default: set `XYMONAPI_ASK=1` in the API's settings
  ([`xymonapi`](../xymonapi/README.md#asking-in-words-ask)). A caller then
  needs only the API's URL and a token, no agent CLI.
- The API runs this command as the Xymon user, who needs an agent CLI
  installed and logged in, and a backend of its own: a hosted provider with
  a key, or a local model
  ([A language model](../xymonapi/README.md#a-language-model)).
- Profiles are then that user's, under its `~/.config/xymonapi-agent/agents/`.

### Agents: another Xymon, another tool set

A profile chooses backends, MCP servers, prompt words and the Xymon server;
it cannot loosen the sandbox. A coordinator routes to other agents. Keys and
guards: [`xymonapi-agent.1`](xymonapi-agent.1) (PROFILES, COORDINATORS).

```toml
# ~/.config/xymonapi-agent/agents/lab.toml -- the lab's Xymon
description = "the lab Xymon"
backend = ["claude", "opencode"]        # tried in order
site = "lab"
[env]
XYMONAPI_URL = "https://xymon-lab.example.ch"
XYMONAPI_TOKEN_FILE = "~/.config/xymonapi/xymon-lab.token"
```

### Relation to `xymonapi-rag ask`

[`xymonapi-rag ask`](../xymonapi-rag/README.md) answers from the passages
its search finds, through an OpenAI-compatible endpoint and a model you run,
with no tools and no agent CLI: use it for "has this been seen before?".
Use this command for anything that needs the board's state now.

### In cron

A morning summary:

```sh
7 7 * * 1-5  xymonapi-agent ask "Summarise what went red or yellow in the last 24 hours, by host, and what is still not green." | mail -s "Xymon overnight" ops@example.ch
```
