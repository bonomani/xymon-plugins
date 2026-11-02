# xymonapi-mcp

An MCP server: it gives an AI client that speaks the Model Context Protocol
-- Claude Code, Claude Desktop, Codex, opencode and others -- read-only tools
over the [Xymon API](../xymonapi/README.md): `health`, `states`, `alarms`,
`entities`, `status`, `series`, and two searches, `search_docs` and
`search_history`, which ask the API's `/search`
([`xymonapi-rag`](../xymonapi-rag/README.md)). It runs where the client runs,
and needs Python 3.10 with the module in [`requirements.txt`](requirements.txt).
Every tool and setting is in [`xymonapi-mcp.1`](xymonapi-mcp.1).

## Needs

- **A running [`xymonapi`](../xymonapi/README.md)**, on the Xymon server,
  reached over the network: install and enable it there first. This plugin
  does not install it, since it usually runs on another machine.
- Python 3.10 with the module `mcp`; the setup script makes a virtualenv
  with it.

Its install brings no other plugin. On the server, `xymonapi-rag` installs
it beside itself, for the `client.py` it reads the API with.

## Installing

The simplest way is the setup script the API gives (see
[On a laptop](../xymonapi/README.md#on-a-laptop)): it installs this plugin,
gets a token, and registers it with Claude Code and Codex; then ask your AI
client "which hosts are red?". By hand:

```sh
make install-client                # under ~/.local; PREFIX=... for elsewhere
```

puts the command `xymonapi-mcp` in `$PREFIX/bin` and the code under
`$PREFIX/libexec/xymon-plugins/xymonapi-mcp`.

Claude Code can also install it as a plugin, from this repository's
marketplace:

```
/plugin install xymonapi-mcp --marketplace bonomani/xymon-plugins
```

or, on an older Claude Code,
`/plugin marketplace add bonomani/xymon-plugins` then
`/plugin install xymonapi-mcp@xymon-plugins`. It then takes `XYMONAPI_URL`,
`XYMONAPI_TOKEN_FILE`, `XYMONAPI_CA` and `XYMONAPI_PYTHON` from your
environment, defaults in [`.mcp.json`](.mcp.json), and still needs Python
with `mcp`, and a token: use the setup script or the marketplace, not both.

`make uninstall-client` removes it, and is refused while `xymonapi-rag`,
which reads the API through it, is installed; it then says what the setup
script did besides, to undo by hand: the registrations in Claude Code and
Codex, and this machine's token, to revoke on the server and delete here.

## Registering it by hand

For Claude Code, once, at user scope so every project has it:

```sh
claude mcp add --scope user xymon \
  -e XYMONAPI_URL=https://xymon.example.ch \
  -e XYMONAPI_TOKEN_FILE=$HOME/.config/xymon-api/xymon.token \
  -e XYMONAPI_PYTHON=$HOME/.local/libexec/xymon-plugins/venv/bin/python3 \
  -- ~/.local/bin/xymonapi-mcp
```

For Codex, the same with `--env` for `-e` and no scope:
`codex mcp add xymon --env ... -- ~/.local/bin/xymonapi-mcp`.

Most other clients read this JSON: Claude Desktop in
`claude_desktop_config.json`, Gemini CLI in `~/.gemini/settings.json`,
Cursor in `~/.cursor/mcp.json`; VS Code reads `.vscode/mcp.json`, with
`servers` for `mcpServers`. JSON expands nothing, so write the paths in full:

```json
{
  "mcpServers": {
    "xymon": {
      "command": "/home/me/.local/bin/xymonapi-mcp",
      "env": {
        "XYMONAPI_URL": "https://xymon.example.ch",
        "XYMONAPI_TOKEN_FILE": "/home/me/.config/xymon-api/xymon.token",
        "XYMONAPI_PYTHON": "/home/me/.local/libexec/xymon-plugins/venv/bin/python3"
      }
    }
  }
}
```

opencode reads its own form, in `~/.config/opencode/opencode.json` or a
project's `opencode.json`: under `mcp`, with `"type": "local"`, the command
as a list, and `environment` for `env`.

- The token file holds what `POST /tokens` with your password answers, alone,
  mode 600; it is the only credential sent. Leave it out when the API asks
  for no password, and `XYMONAPI_PYTHON` when the system `python3` has `mcp`.
- Add `XYMONAPI_CA` when the server's certificate is its own.
- For two Xymon servers, register twice, as `xymon-prod` and `xymon-lab`,
  each with its own URL and token file.

## What it cannot do

- A client in a web browser -- claude.ai, ChatGPT -- cannot use it: it
  reaches an MCP server from its provider's cloud, so the server would have
  to be open to the internet. Claude Desktop runs on your machine instead.
- An online client sends what the tools return to its provider. With a
  local model -- opencode with LM Studio or Ollama, for instance -- nothing
  leaves your network; a model too small reads the answers wrong.
- The two searches answer an error until the server has an index.
