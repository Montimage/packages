#!/usr/bin/env bash
# smoke-install.sh: apt-get install mmt-dpi in a container from the repository.
#
# Usage:
#   scripts/smoke-install.sh <image> --tree <dir> [--dists <dir>] [--keyring <file>]
#   scripts/smoke-install.sh <image> --url <url> --keyring <file>
#
# --tree mounts a locally built tree as file:/repo. Without --keyring it is an
# UNSIGNED dry run and apt is told to trust it; with --keyring (and usually
# --dists, a signed copy of dists/) apt checks the signatures. --url uses the
# live site with Signed-By <file>, and first checks that the keyring served by
# the site is the committed one. The container runs scripts/smoke-in-container.sh.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/common.sh
. "$here/common.sh"

[ $# -ge 1 ] || die "usage: $0 <image> (--tree <dir> [--dists <dir>] | --url <url>) [--keyring <file>]"
image=$1
shift
tree='' dists='' url='' keyring=''
while [ $# -gt 0 ]; do
  case "$1" in
    --tree) tree=$(cd "$2" && pwd); shift 2 ;;
    --dists) dists=$(cd "$2" && pwd); shift 2 ;;
    --url) url=${2%/}; shift 2 ;;
    --keyring) keyring=$(cd "$(dirname "$2")" && pwd)/$(basename "$2"); shift 2 ;;
    *) die "unknown argument $1" ;;
  esac
done
if [ -n "$tree" ] && [ -n "$url" ]; then die "give --tree or --url, not both"; fi
if [ -z "$tree" ] && [ -z "$url" ]; then die "give --tree or --url"; fi
if [ -n "$url" ] && [ -z "$keyring" ]; then die "--url needs --keyring"; fi
if [ -n "$keyring" ] && [ ! -s "$keyring" ]; then die "keyring $keyring is missing or empty"; fi
require_cmd docker

args=(--rm -v "$here/smoke-in-container.sh:/smoke.sh:ro")
if [ -n "$keyring" ]; then
  args+=(-v "$keyring:/keyring.gpg:ro" -e SMOKE_KEYRING=/keyring.gpg)
fi

if [ -n "$tree" ]; then
  args+=(-v "$tree:/repo:ro" -e SMOKE_URI=file:/repo)
  [ -z "$dists" ] || args+=(-v "$dists:/repo/dists:ro")
  # The container reads its own suite's Packages and requires the newest one.
  args+=(-e SMOKE_EXPECT_NEWEST=1)
  if [ -z "$keyring" ]; then
    log "==> UNSIGNED dry run: installing from the local tree with Trusted: yes"
  else
    log "==> Installing from the local tree; apt checks signatures with $(basename "$keyring")"
  fi
else
  require_cmd curl cmp
  served=$(mktemp)
  trap 'rm -f "$served"' EXIT
  curl -fsSL -o "$served" "$url/montimage-archive-keyring.gpg" ||
    die "cannot download $url/montimage-archive-keyring.gpg"
  cmp -s "$served" "$keyring" || die "the keyring served at $url differs from $keyring"
  args+=(-e "SMOKE_URI=$url")
  log "==> Installing from $url; apt checks signatures with $(basename "$keyring")"
fi

docker run "${args[@]}" "$image" bash /smoke.sh
