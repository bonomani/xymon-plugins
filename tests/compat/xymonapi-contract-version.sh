#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/compat/xymonapi-contract-version.sh
#
# build/contract-check.sh lets the API's contract change only with its
# version: an unchanged contract passes; a changed one with the same version
# fails, saying to raise it; a change oasdiff calls breaking fails unless the
# major number moved and UPGRADING.md changed, and passes when both did. With
# no base to compare with, it passes and says so.
#
# Runs on a scratch copy of the repository, with a stand-in for oasdiff
# that calls a change breaking when the spec's text says so. Uses the test
# helpers of the Xymon tree in XYMON_SRC, and git.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../lib/xymonapi.sh"

ROOT=$(find_root)
command -v git >/dev/null 2>&1 || skip "git is not installed"
work=$(mktempdir)

# A repository with the two files the check reads, and the check itself.
repo=$work/repo
mkdir -p "$repo/build" "$repo/plugins/xymonapi"
cp "$ROOT/build/contract-check.sh" "$repo/build/"
printf 'openapi: 3.0.3\npaths: {}\n' > "$repo/plugins/xymonapi/openapi.yaml"
printf 'name: xymonapi\nversion: 1.0.0\n' > "$repo/plugins/xymonapi/PLUGIN"
git -C "$repo" init -q -b main
git -C "$repo" -c user.name=t -c user.email=t@example.com add -A
git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q -m base
commit() { git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q -am "$1"; }
spec() { printf 'openapi: 3.0.3\npaths: {}\n# %s\n' "$1" > "$repo/plugins/xymonapi/openapi.yaml"; }
version() { printf 'name: xymonapi\nversion: %s\n' "$1" > "$repo/plugins/xymonapi/PLUGIN"; }
# The stand-in: breaking when the new spec says "breaking".
printf '#!/bin/sh\ncase $1 in changelog) echo "a change" ;; breaking) eval "last=\\${$#}"; ! grep -q breaking "$last" ;; esac\n' > "$work/oasdiff"
chmod 755 "$work/oasdiff"
check() { OASDIFF="$work/oasdiff" "$repo/build/contract-check.sh" "$@" 2>&1; }

rc=0; out=$(check no-such-ref) || rc=$?
assert_equal "0" "$rc" "with no base, the check passes"
assert_contains "nothing to compare" "$out" "and says why"

git -C "$repo" branch stable
rc=0; out=$(check stable) || rc=$?
assert_equal "0" "$rc" "an unchanged contract passes"

spec "an added field"; commit "add"
rc=0; out=$(check stable) || rc=$?
assert_equal "1" "$rc" "a changed contract with the same version fails"
assert_contains "raise it in plugins/xymonapi/PLUGIN" "$out" "and says what to do"
version 1.1.0; commit "bump"
rc=0; out=$(check stable) || rc=$?
assert_equal "0" "$rc" "the same change with the version raised passes"

git -C "$repo" branch -f stable
spec "a breaking removal"; version 1.2.0; commit "break, minor"
rc=0; out=$(check stable) || rc=$?
assert_equal "1" "$rc" "a breaking change with only the minor number raised fails"
assert_contains "major version did not move" "$out" "and says so"
version 2.0.0; commit "break, major"
rc=0; out=$(check stable) || rc=$?
assert_equal "1" "$rc" "a breaking change with the major number raised but no upgrade note fails"
assert_contains "UPGRADING.md does not say so" "$out" "and says so"
echo "2.0.0: what to do" > "$repo/UPGRADING.md"; git -C "$repo" add UPGRADING.md; commit "note"
rc=0; out=$(check stable) || rc=$?
assert_equal "0" "$rc" "a breaking change with the major number raised and its note passes"
assert_contains "a change" "$out" "and the changelog is printed, for the upgrade notes"

pass "the contract changes only with xymonapi's version, and a break only with its major number"
