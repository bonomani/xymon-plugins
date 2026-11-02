#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# build/contract-check.sh [BASE] -- the API's contract does not change
# without its version saying so, compared with BASE, origin/stable by
# default: the last code every test passed.
#
# When plugins/xymonapi/openapi.yaml differs from BASE's, the version in
# plugins/xymonapi/PLUGIN must differ too; and when oasdiff finds a change
# that breaks existing clients, its major number must have moved and
# UPGRADING.md must say what to do. Run in CI
# before stable moves on; runs here too, with oasdiff on PATH or named in
# OASDIFF. Prints what changed, in oasdiff's changelog, for the upgrade
# notes. With no BASE yet -- before stable first exists -- there is nothing
# to compare, and it says so.

set -eu
cd "$(dirname "$0")/.."

base=${1:-origin/stable}
spec=plugins/xymonapi/openapi.yaml
plugin=plugins/xymonapi/PLUGIN
oasdiff=${OASDIFF:-oasdiff}

if ! git rev-parse -q --verify "$base^{commit}" >/dev/null; then
	echo "no $base yet: nothing to compare the contract with"
	exit 0
fi
if git diff --quiet "$base" -- "$spec"; then
	echo "the contract is unchanged since $base"
	exit 0
fi

version() { sed -n 's/^version: *//p'; }
old=$(git show "$base:$plugin" | version)
new=$(version < "$plugin")
if [ "$old" = "$new" ]; then
	echo "contract-check: $spec changed since $base, and xymonapi's version did not ($new):" >&2
	echo "  raise it in $plugin -- the last number for an addition, the first for a break" >&2
	exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git show "$base:$spec" > "$tmp/base.yaml"
echo "what changed in the contract since $base ($old to $new):"
"$oasdiff" changelog "$tmp/base.yaml" "$spec" || true
if ! "$oasdiff" breaking --fail-on ERR "$tmp/base.yaml" "$spec" > "$tmp/breaking" 2>&1; then
	if [ "${old%%.*}" = "${new%%.*}" ]; then
		echo "contract-check: the contract breaks existing clients, and xymonapi's major version did not move ($old to $new):" >&2
		cat "$tmp/breaking" >&2
		exit 1
	fi
	if git diff --quiet "$base" -- UPGRADING.md; then
		echo "contract-check: the contract breaks existing clients, and UPGRADING.md does not say so:" >&2
		echo "  add what changes and what to do; the changelog above is a draft" >&2
		exit 1
	fi
	echo "breaking, with the major version raised ($old to $new) and UPGRADING.md written"
fi
echo "contract-check: the version says what the contract did"
