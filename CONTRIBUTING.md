# Contributing to xymon-plugins

Patches are welcome. This file covers what is easy to get wrong because it is
not visible from the source tree. Most of how a change is written, titled,
described and reviewed is the same as for Xymon itself, and is not repeated
here: the next section says which of Xymon's rules apply as they are. The
rest of this file is what differs, and what only this repository has.

## What applies as Xymon writes it

These sections of Xymon's
[`CONTRIBUTING.md`](https://github.com/xymon-monitoring/xymon/blob/main/CONTRIBUTING.md)
apply here as written, with "the tree" meaning this repository:

- [Where a change gets written down](https://github.com/xymon-monitoring/xymon/blob/main/CONTRIBUTING.md#where-a-change-gets-written-down),
  for its principle -- a fact belongs where its reader is, and every other
  place points at it -- not for `Changes` and `RELEASENOTES`, which this
  repository does not have;
- [Shortening](https://github.com/xymon-monitoring/xymon/blob/main/CONTRIBUTING.md#shortening);
- [Titles](https://github.com/xymon-monitoring/xymon/blob/main/CONTRIBUTING.md#titles),
  with this repository's components (below);
- [Descriptions](https://github.com/xymon-monitoring/xymon/blob/main/CONTRIBUTING.md#descriptions),
  [Pre-review](https://github.com/xymon-monitoring/xymon/blob/main/CONTRIBUTING.md#pre-review)
  and [Reviews](https://github.com/xymon-monitoring/xymon/blob/main/CONTRIBUTING.md#reviews),
  for a change that goes through a pull request;
- [The last pass](https://github.com/xymon-monitoring/xymon/blob/main/CONTRIBUTING.md#the-last-pass),
  for every change;
- [Style](https://github.com/xymon-monitoring/xymon/blob/main/CONTRIBUTING.md#style).

From its Pull requests section, these hold here too: one change per commit,
each commit standing alone and saying what it does and why; say what you
verified and how; and each observable behaviour gets a test that fails
without it, checked by reverting what makes it true.

## What differs here

- **No `Changes`, no `RELEASENOTES`.** What an admin upgrading needs to know
  goes in the commit message, and in the manual page when it changes how the
  plugin behaves.
- **Manual pages have no HTML copy.** Each plugin's page -- `xymonapi.8`,
  `xymonapi-mcp.1`, `xymonapi-rag.1` -- is the only copy: edit it, nothing
  is generated. Do not bump the version or date in its `.TH` line; that
  happens at a release.
- **No branch protection.** Changes may be pushed to `main` directly; a pull
  request is welcome, and is the way when you want a second reader.
- **Python, not C.** See [Python](#python) below; Xymon's C section does not
  apply.
- **Components, for titles and commit subjects:** a plugin's name
  (`xymonapi:`, `xymonapi-mcp:`, `xymonapi-rag:`), or one of `tests:`,
  `build:`, `README:`, `ci:`.
- **Surfaces**, in the sense of Xymon's table of who reads what:

  | surface | who reads it | what it carries |
  |---|---|---|
  | `README.md` | whoever installs or builds, with the repository open | what each plugin is, how to install it, settings, tests |
  | a plugin's manual page | an admin, or a laptop user, with the plugin installed | its behaviour and every setting |
  | `plugins/xymonapi/openapi.yaml` | whoever writes a client or another implementation of the API | the contract: each path's answers, the closed list of errors, the numbered rules |
  | a plugin's `PLUGIN` file | the build, and whoever packages it | its name, side, version, and what it needs |

## What only this repository has

### Plugins

Each plugin is a directory under `plugins/` with a `Makefile` that installs
it alone and a `PLUGIN` file. A plugin that needs another names it there and
installs it first. Code shared by two plugins lives in one of them, the one
it belongs to, and the other installs that one: `xymonapi-rag` uses
`xymonapi-mcp`'s `client.py`.

### Versions

A plugin's version is the `version:` line of its `PLUGIN` file, `X.Y.Z`. A
release is a tag of that plugin, `NAME/vX.Y.Z`, matching it. `make install`
writes the version beside the installed files, in `VERSION`, and `/health`
gives the API's. A plugin that reads the API names in its `PLUGIN` file the
lowest `xymonapi` version it needs; `xymonapi-mcp`'s `client.py` repeats it,
and a test checks the two agree, so change both together.

### The contract

`plugins/xymonapi/openapi.yaml` is the API's contract. A change to what a
client can observe -- a path, a parameter, a field, a status, an error --
changes it in the same commit. Its errors are a closed list: a new one is
added there first.

A behaviour the paths alone do not say is a numbered rule in its
description, `C1.`, `C2.`, and so on. A test that checks a rule cites it in
its message, as `[C3]`; `tests/api/xymonapi-clauses.sh` fails when a rule is
cited by no test, or a test cites a rule that does not exist. A new rule
therefore comes with its test, and a rule removed takes its citations with
it. Numbers are not reused.

The spec's `info.version` stays `1.0.0` until the API is first published.

### Python

- `plugins/xymonapi-mcp/client.py` uses the standard library alone: the MCP
  server and `xymonapi-rag` both load it, on laptops where little else may
  be installed.
- A new module dependency goes in that plugin's `requirements.txt`, and only
  when a few lines of the standard library will not do.
- Python 3.10 is the floor; nothing newer is assumed.
- Keep `ruff check` quiet on the lines you change. Older warnings in a file
  you touch are a note for another change, not this one.

## Tests

The tests run against a server build of Xymon's current `main`, named by
`XYMON_SRC`, and use its test helpers:

```sh
XYMON_SRC=/path/to/built/xymon tests/run.sh
```

What each test checks, and what they need, is in the README's Tests section.
Unlike Xymon's, a test here may use Python: a helper written in Python goes
under `tests/lib/`, as `fake-llm.py` and `ctrl-c.py` do. A test that cannot
run where something it needs is missing skips, with exit 77, and says what.

## Copyright and licensing

Everything here is under the GNU General Public License version 2 or, at
your option, any later version (`GPL-2.0-or-later`); the text of version 2 is
in [`LICENSE`](LICENSE). Copyright in a contribution stays with its author.
Do not copy third-party code in without checking that its licence is
compatible and keeping its notices.

Coding agents: read [`AGENTS.md`](AGENTS.md) as well.
