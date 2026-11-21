# xymonapi-mcp

An MCP server: read-only tools over the [Xymon API](../xymonapi/README.md)
for an AI tool that speaks the Model Context Protocol -- Claude Code,
Claude Desktop, Codex, opencode and others. The model is the AI tool's own;
this plugin has none.

## Installing it

| part | where, as whom | command |
|---|---|---|
| tools | where the AI tool runs, as yourself | `./xymon-plugin install --tools xymonapi-mcp` |
| server | the Xymon server, as its owner | `XYMONHOME=... ./xymon-plugin install --server xymonapi-mcp` |

Then, once, on the machine where the AI tool runs:

```sh
xymonapi-mcp register https://xymon.example.ch
```

## Using it

- Ask your AI tool, for instance "which hosts are red?".
- Tools: `health`, `alarms`, `alarm`, `hosts`, `series`, and two searches,
  `search_docs` and `search_history`.
- On the Xymon server, `register` takes the API's socket instead of a URL:
  `unix:/run/xymon/xymonapi/local/api.sock`.
- An AI tool other than Claude Code and Codex: [register it by
  hand](#registering-it-by-hand).
- Every tool and setting: [`xymonapi-mcp.1`](xymonapi-mcp.1).

## Needs

- A running [`xymonapi`](../xymonapi/README.md) on the Xymon server.
- Python 3.9 or later, and nothing else.

## Reference

Every tool, setting, message and exit status, and how `register` works:
[`xymonapi-mcp.1`](xymonapi-mcp.1).

### Installing and removing

- `install --tools` puts it under `~/.local` (`PREFIX=...` for elsewhere),
  with `xymonapi`'s client library beside it.
- [`xymonapi`'s README](../xymonapi/README.md#reaching-it-from-another-machine)
  gives the URL for each way of reaching the API.
- `install --server` installs the API first when it is not there, then
  stages this plugin, at the server's version, in what the API serves at
  `/plugins`; it installs no command on the server.
- On the server, the socket is the one `install --server xymonapi` printed;
  the path above holds where `XYMONRUNDIR` is `/run/xymon`. Its permissions
  decide who may read the API.
- `./xymon-plugin remove --tools xymonapi-mcp` removes it, and says what
  `register` did besides, to undo by hand: the registrations in Claude Code
  and Codex, and this machine's token.

### Registering it by hand

For Claude Code, once, at user scope so every project has it:

```sh
claude mcp add --scope user xymon \
  -e XYMONAPI_URL=https://xymon.example.ch \
  -e XYMONAPI_TOKEN_FILE=$HOME/.config/xymonapi/xymon.token \
  -- ~/.local/bin/xymonapi-mcp
```

For Codex, the same with `--env` for `-e` and no scope:
`codex mcp add xymon --env ... -- ~/.local/bin/xymonapi-mcp`.

Most other AI tools read the JSON below. JSON expands nothing, so write the
paths in full.

| AI tool | file |
|---|---|
| Claude Desktop | `claude_desktop_config.json` |
| Gemini CLI | `~/.gemini/settings.json` |
| Cursor | `~/.cursor/mcp.json` |
| VS Code | `.vscode/mcp.json`, with `servers` for `mcpServers` |

```json
{
  "mcpServers": {
    "xymon": {
      "command": "/home/me/.local/bin/xymonapi-mcp",
      "env": {
        "XYMONAPI_URL": "https://xymon.example.ch",
        "XYMONAPI_TOKEN_FILE": "/home/me/.config/xymonapi/xymon.token"
      }
    }
  }
}
```

- opencode reads its own form, in `~/.config/opencode/opencode.json` or a
  project's `opencode.json`: under `mcp`, with `"type": "local"`, the command
  as a list, and `environment` for `env`.
- The token file holds what `POST /tokens` answers to one of the API's
  [users](../xymonapi/README.md#users), alone, mode 600.
- Leave the token file out when the API asks for no password.
- For two Xymon servers, register twice, as `xymon-prod` and `xymon-lab`,
  each with its own URL and token file.

### What it cannot do

- An AI tool in a web browser -- claude.ai, ChatGPT -- cannot use it: it
  reaches an MCP server from its provider's cloud, so the server would have
  to be open to the internet. Claude Desktop runs on your machine instead.
- An online AI tool sends what the tools return to its provider; with a
  local model -- opencode with LM Studio or Ollama, for instance -- nothing
  leaves your network.
- A model too small reads the answers wrong.
