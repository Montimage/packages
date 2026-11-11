#!/usr/bin/env bash
# smoke-install.sh: apt-get install mmt-dpi in a container from the repository.
#
# Usage:
#   scripts/smoke-install.sh <image> --tree <dir> [--dists <dir>] [--keyring <file>]
#   scripts/smoke-install.sh <image> --url <url> --keyring <file> --dists <dir>
#
# --tree mounts a locally built tree as file:/repo. Without --keyring it is an
# UNSIGNED dry run and apt is told to trust it; with --keyring (and usually
# --dists, a signed copy of dists/) apt checks the signatures. --url uses the
# live site with Signed-By <file>, and first checks that the keyring served by
# the site is the committed one. There --dists is the signed dists/ just
# deployed: Pages caches for up to 10 minutes, so the smoke first waits (at most
# SMOKE_FRESH_TIMEOUT seconds, default 900) until the site serves that
# InRelease and its Packages, byte for byte, so it never tests the previous
# deploy. Both modes require the newest mmt-dpi in the suite's Packages. The
# container runs scripts/smoke-in-container.sh.
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
if [ -n "$url" ] && [ -z "$dists" ]; then die "--url needs --dists (the dists/ just deployed)"; fi
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

  # The suite and architecture apt will use in this image.
  read -r suite arch < <(docker run --rm "$image" sh -c \
    '. /etc/os-release && echo "$VERSION_CODENAME $(dpkg --print-architecture)"') ||
    die "cannot read VERSION_CODENAME and the architecture of $image"
  [ -n "$suite" ] && [ -n "$arch" ] || die "cannot read VERSION_CODENAME and the architecture of $image"
  fresh=(InRelease "main/binary-$arch/Packages" "main/binary-$arch/Packages.gz")
  for f in "${fresh[@]}"; do
    [ -s "$dists/$suite/$f" ] || die "$dists/$suite/$f is missing: not the dists/ just deployed"
  done
  timeout=${SMOKE_FRESH_TIMEOUT:-900}
  [[ "$timeout" =~ ^[0-9]+$ ]] || die "SMOKE_FRESH_TIMEOUT must be a number of seconds"
  log "==> Waiting up to ${timeout} s for $url to serve the $suite files just deployed"
  start=$SECONDS
  while :; do
    stale=
    for f in "${fresh[@]}"; do
      if ! curl -fsSL -o "$served" "$url/dists/$suite/$f" || ! cmp -s "$served" "$dists/$suite/$f"; then
        stale=$f
        break
      fi
    done
    [ -n "$stale" ] || break
    if [ $((SECONDS - start)) -ge "$timeout" ]; then
      die "after ${timeout} s, $url/dists/$suite/$stale is still not the one just deployed (stale Pages cache, or a newer deploy)"
    fi
    log "    $url/dists/$suite/$stale is not the new one yet; retrying in 15 s"
    sleep 15
  done
  log "    $url serves the $suite InRelease and Packages just deployed ($((SECONDS - start)) s)"
  args+=(-e "SMOKE_URI=$url" -v "$dists:/expect/dists:ro" -e SMOKE_DISTS=/expect/dists -e SMOKE_EXPECT_NEWEST=1)
  log "==> Installing from $url; apt checks signatures with $(basename "$keyring")"
fi

docker run "${args[@]}" "$image" bash /smoke.sh
