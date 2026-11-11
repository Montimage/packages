#!/usr/bin/env bash
# sign-repo.sh: sign every dists/<suite>/Release of an APT repository tree.
#
# Usage: scripts/sign-repo.sh <tree> <public-keyring> < secret-subkey.asc
#
# Reads the ASCII-armoured secret subkey from stdin. Environment:
#   APT_SIGNING_FINGERPRINT  the signing subkey fingerprint with a trailing "!"
#   APT_SIGNING_PASSPHRASE   the CI passphrase of that export
#
# The key goes into a throwaway GNUPGHOME under $RUNNER_TEMP (or $TMPDIR),
# which is removed on exit. The committed public keyring is imported first, so
# a renewed expiry or a new self-signature in it is honoured. For each suite it
# writes InRelease (clearsigned) and Release.gpg (detached, armoured), then
# checks every signature with gpgv against <public-keyring> alone
# (scripts/verify-repo.sh). Neither the key nor the passphrase is printed.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/common.sh
. "$here/common.sh"

[ $# -eq 2 ] || die "usage: $0 <tree> <public-keyring> < secret-subkey.asc"
tree=$(cd "$1" && pwd) || die "tree $1 not found"
keyring=$2
[ -s "$keyring" ] || die "public keyring $keyring is missing or empty"
keyring=$(cd "$(dirname "$keyring")" && pwd)/$(basename "$keyring")
[ ! -t 0 ] || die "the secret subkey must be given on stdin"

fpr=${APT_SIGNING_FINGERPRINT:-}
pass=${APT_SIGNING_PASSPHRASE:-}
unset APT_SIGNING_PASSPHRASE APT_SIGNING_KEY
[[ "$fpr" =~ ^([0-9A-Fa-f]{40}|[0-9A-Fa-f]{64})!$ ]] ||
  die "APT_SIGNING_FINGERPRINT must be the signing subkey fingerprint followed by '!'"
[ -n "$pass" ] || die "APT_SIGNING_PASSPHRASE is empty"

require_cmd gpg gpgconf gpgv

GNUPGHOME=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/apt-signing-gnupg.XXXXXX")
export GNUPGHOME
cleanup() {
  gpgconf --kill all >/dev/null 2>&1 || true
  rm -rf "$GNUPGHOME"
}
trap cleanup EXIT
chmod 700 "$GNUPGHOME"

gpg_pass() { # gpg with the passphrase on fd 3; never on the command line
  gpg --batch --no-tty --pinentry-mode loopback --passphrase-fd 3 "$@" 3< <(printf '%s' "$pass")
}

log "==> Importing the public keyring $(basename "$keyring")"
gpg --batch --no-tty --quiet --import "$keyring" || die "cannot import $keyring"
log "==> Importing the signing subkey from stdin"
gpg_pass --quiet --import || die "cannot import the signing subkey"

suites=()
for release in "$tree"/dists/*/Release; do
  [ -f "$release" ] || continue
  dir=$(dirname "$release")
  suite=$(basename "$dir")
  rm -f "$dir/InRelease" "$dir/Release.gpg"
  gpg_pass --yes --local-user "$fpr" --digest-algo SHA512 \
    --clearsign --output "$dir/InRelease" "$release" ||
    die "signing InRelease for $suite failed"
  gpg_pass --yes --local-user "$fpr" --digest-algo SHA512 \
    --armor --detach-sign --output "$dir/Release.gpg" "$release" ||
    die "signing Release.gpg for $suite failed"
  suites+=("$suite")
done
[ "${#suites[@]}" -gt 0 ] || die "no dists/<suite>/Release in $tree"
log "==> Signed: ${suites[*]}"

"$here/verify-repo.sh" --no-pool --expect-signer "${fpr%!}" "$tree" "$keyring"
