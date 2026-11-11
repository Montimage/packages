#!/usr/bin/env bash
# build-repo.sh: build the unsigned APT repository tree from verified inputs.
#
# Usage: scripts/build-repo.sh <work-dir> <tree> [<site-dir>]
#
# <work-dir> is the output of scripts/fetch-releases.sh. <tree> must not exist
# or be empty. <site-dir> (default: site/ next to this script's parent) is
# copied to the tree root, so the Pages site keeps index.html and the public
# keyring.
#
# Layout, one pool per suite because every distribution's package has the same
# Debian version:
#   pool/<codename>/main/m/mmt-dpi/<package>_<version>_<arch>.deb
#   dists/<codename>/main/binary-{amd64,arm64}/Packages{,.gz}
#   dists/<codename>/Release   (unsigned; scripts/sign-repo.sh adds the signatures)
#
# The same inputs give a byte-identical tree: entries are sorted, gzip stores
# no name or time, and the Release Date and every mtime are SOURCE_DATE_EPOCH,
# which defaults to the publication time of the newest selected release.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/common.sh
. "$here/common.sh"

[ $# -ge 2 ] && [ $# -le 3 ] || die "usage: $0 <work-dir> <tree> [<site-dir>]"
work=$(cd "$1" && pwd) || die "work dir $1 not found"
tree=$2
site=${3:-$here/../site}
max_bytes=${MAX_TREE_BYTES:-1000000000} # GitHub Pages publishes at most 1 GB

require_cmd apt-ftparchive dpkg-deb gzip sha256sum
[ -s "$work/inputs.tsv" ] || die "$work/inputs.tsv is missing or empty; run scripts/fetch-releases.sh first"
[ -s "$work/releases.tsv" ] || die "$work/releases.tsv is missing or empty"
[ -d "$site" ] || die "site dir $site not found"
[ ! -e "$site/dists" ] && [ ! -e "$site/pool" ] || die "$site must not contain dists/ or pool/"

if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
  SOURCE_DATE_EPOCH=$(cut -f3 "$work/releases.tsv" | LC_ALL=C sort -n | tail -n 1)
fi
[[ "$SOURCE_DATE_EPOCH" =~ ^[0-9]+$ ]] || die "SOURCE_DATE_EPOCH must be an integer, got '$SOURCE_DATE_EPOCH'"
export SOURCE_DATE_EPOCH
release_date=$(LC_ALL=C date -u -d "@$SOURCE_DATE_EPOCH" '+%a, %d %b %Y %H:%M:%S UTC')

mkdir -p "$tree"
tree=$(cd "$tree" && pwd)
[ -z "$(ls -A "$tree")" ] || die "tree dir $tree is not empty"

log "==> Building $tree (Date: $release_date)"
first=${APT_POOL_SOURCE:0:1}
built_suites=()
for suite in "${APT_SUITES[@]}"; do
  pool_rel="pool/$suite/$APT_COMPONENT/$first/$APT_POOL_SOURCE"
  n=0
  while IFS=$'\t' read -r _tag path pkg version arch _distro codename sha; do
    [ "$codename" = "$suite" ] || continue
    dest="$tree/$pool_rel/${pkg}_${version#*:}_${arch}.deb"
    [ ! -e "$dest" ] || die "two inputs map to $pool_rel/$(basename "$dest")"
    mkdir -p "$tree/$pool_rel"
    cp "$work/$path" "$dest"
    [ "$(sha256sum "$dest" | awk '{ print $1 }')" = "$sha" ] || die "$dest changed after verification"
    n=$((n + 1))
  done <"$work/inputs.tsv"

  # Users of a suite would get "no Release file" errors if it disappeared, so
  # a suite without packages fails the build instead.
  [ "$n" -gt 0 ] || die "suite $suite has no packages in the selected releases"
  built_suites+=("$suite")

  for arch in "${APT_ARCHES[@]}"; do
    bin="dists/$suite/$APT_COMPONENT/binary-$arch"
    mkdir -p "$tree/$bin"
    : >"$tree/$bin/Packages"
    # One apt-ftparchive call per file, in sorted order, so the index does not
    # depend on directory order. Filename: is relative to the tree root.
    list="$work/.pool-$suite-$arch"
    (cd "$tree" && find "$pool_rel" -type f -name "*_${arch}.deb") >"$list.unsorted" ||
      die "cannot list $pool_rel"
    LC_ALL=C sort "$list.unsorted" >"$list"
    while IFS= read -r deb; do
      (cd "$tree" && apt-ftparchive packages "$deb") >>"$tree/$bin/Packages" ||
        die "apt-ftparchive failed on $deb"
    done <"$list"
    rm -f "$list" "$list.unsorted"
    gzip -9 -n -c "$tree/$bin/Packages" >"$tree/$bin/Packages.gz"
  done

  apt-ftparchive \
    -o APT::FTPArchive::Release::Origin=Montimage \
    -o APT::FTPArchive::Release::Label=Montimage \
    -o APT::FTPArchive::Release::Suite="$suite" \
    -o APT::FTPArchive::Release::Codename="$suite" \
    -o APT::FTPArchive::Release::Date="$release_date" \
    -o APT::FTPArchive::Release::Architectures="${APT_ARCHES[*]}" \
    -o APT::FTPArchive::Release::Components="$APT_COMPONENT" \
    release "$tree/dists/$suite" >"$tree/dists/$suite/Release.new"
  mv "$tree/dists/$suite/Release.new" "$tree/dists/$suite/Release"
  log "    $suite: $n packages"
done

cp -R "$site/." "$tree/"
find "$tree" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +

bytes=$(du -sb "$tree" | cut -f1)
[ "$bytes" -le "$max_bytes" ] || die "tree is $bytes bytes, over the $max_bytes byte limit"
log "==> Built suites: ${built_suites[*]} ($bytes bytes)"
