#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# build/release-archive.sh TAG [OUTDIR] -- the archive of one release, built
# from the commit TAG names, in OUTDIR (the current directory by default).
#
# TAG is NAME/vX.Y.Z: a plugin, plugins/NAME, whose PLUGIN file's version:
# is X.Y.Z at that commit -- the installer among them, plugins/xymon-plugin.
# The archive is NAME-X.Y.Z.tar.gz and holds, under xymon-plugins/, that
# plugin's directory, each link at the top that leads into it (the
# installer's ./xymon-plugin), and LICENSE: every archive unpacks into the
# same directory, so the installer and the plugins wanted, unpacked side by
# side, install as a checkout does.
#
# Reproducible: git archive writes the files in a fixed order with the
# commit's time, and gzip -n leaves out a name and a time of its own, so the
# same tag gives the same bytes. Prints the archive's path.

set -eu

die() { printf 'release-archive: %s\n' "$*" >&2; exit 1; }

[ $# -ge 1 ] || die "usage: build/release-archive.sh NAME/vX.Y.Z [OUTDIR]"
tag=$1
out=${2:-.}
name=${tag%/v*}
version=${tag##*/v}
case $tag in
	*/v*) ;;
	*) die "$tag is no release tag: NAME/vX.Y.Z" ;;
esac
# X.Y.Z, digits only: no pipe into grep -q, which a writer under pipefail
# can die of (SIGPIPE) when grep stops reading at the first match.
case $version in
	*[!0-9.]*|*..*|.*|*.|*.*.*.*) die "$tag: the version must be X.Y.Z" ;;
	*.*.*) ;;
	*) die "$tag: the version must be X.Y.Z" ;;
esac
case $name in
	''|*/*|.*) die "$tag: no plugin is named $name" ;;
esac
git rev-parse -q --verify "refs/tags/$tag^{commit}" >/dev/null \
	|| git rev-parse -q --verify "$tag^{commit}" >/dev/null \
	|| die "$tag: no such tag"

git cat-file -e "$tag:plugins/$name/PLUGIN" 2>/dev/null \
	|| die "$tag: no plugin is named $name at that commit"
have=$(git show "$tag:plugins/$name/PLUGIN" | sed -n 's/^version: *\([0-9.]*\)$/\1/p')
# The links at the top that lead into the plugin's directory (mode 120000,
# their target the blob's text). No case inside $(...): macOS's /bin/sh,
# bash 3.2, takes a pattern's ) for the substitution's end.
links=$(git ls-tree "$tag" | while read -r mode _ obj path; do
	[ "$mode" = 120000 ] || continue
	target=$(git cat-file -p "$obj")
	if [ "${target#"plugins/$name/"}" != "$target" ]; then printf ' %s' "$path"; fi
done)
paths="plugins/$name$links LICENSE"
[ "$have" = "$version" ] \
	|| die "$tag: $name is version ${have:-unknown} at that commit, not $version"

mkdir -p "$out"
archive=$out/$name-$version.tar.gz
# shellcheck disable=SC2086 # the paths are meant to split
git archive --format=tar --prefix=xymon-plugins/ "$tag" -- $paths | gzip -n -9 > "$archive"
printf '%s\n' "$archive"
