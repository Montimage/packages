#!/usr/bin/env bash
# test-signing.sh: TEST ONLY. Exercise the signing path with a throwaway key.
#
# Usage: scripts/test-signing.sh <tree> <out-dir>
#
# Never touches a real key. It generates, in a temporary GNUPGHOME, a key shaped
# like the real one (certify-only ed25519 primary, two ed25519 signing
# subkeys A and B), exports subkey A alone with its own passphrase, and runs
# scripts/sign-repo.sh on a copy of <tree>/dists exactly as CI does: the
# secret on stdin, APT_SIGNING_FINGERPRINT="<A>!", the public keyring first.
#
# Subkey A is created already expired and then extended, as after the
# maintainer's expiry renewal: the exported secret still carries the old
# expiry, so signing works only because the refreshed public keyring is
# imported first.
#
# Negative checks: a tampered Release, a wrong expected signer, a keyring in
# which the signing subkey has expired, and signing without the refreshed
# keyring must all fail.
#
# Leaves <out-dir>/dists (signed) and <out-dir>/test-keyring.gpg, for the smoke
# test. The throwaway secret is deleted on exit.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/common.sh
. "$here/common.sh"

[ $# -eq 2 ] || die "usage: $0 <tree> <out-dir>"
tree=$(cd "$1" && pwd) || die "tree $1 not found"
out=$2
[ -d "$tree/dists" ] || die "$tree has no dists/"
mkdir -p "$out"
out=$(cd "$out" && pwd)
[ -z "$(ls -A "$out")" ] || die "out dir $out is not empty"

require_cmd gpg gpgconf gpgv od

log "############################################################"
log "# TEST ONLY: throwaway signing key, generated in this run.  #"
log "# These signatures are NOT the Montimage archive key.       #"
log "############################################################"

keygen=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/apt-test-keygen.XXXXXX")
cleanup() {
  GNUPGHOME="$keygen" gpgconf --kill all >/dev/null 2>&1 || true
  [ -z "${solo:-}" ] || { GNUPGHOME="$solo" gpgconf --kill all >/dev/null 2>&1 || true; rm -rf "$solo"; }
  rm -rf "$keygen"
}
trap cleanup EXIT
chmod 700 "$keygen"
pass=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')

kg() { # gpg in the keygen home, passphrase on fd 3
  GNUPGHOME="$keygen" gpg --batch --no-tty --quiet --pinentry-mode loopback \
    --passphrase-fd 3 "$@" 3< <(printf '%s' "$pass")
}
fprs() { GNUPGHOME="$keygen" gpg --batch --with-colons --list-keys | awk -F: '/^fpr/ { print $10 }'; }

past=20200101T000000
kg --faked-system-time "$past" --quick-generate-key \
  "TEST ONLY throwaway APT key <apt-test@invalid>" ed25519 cert never
primary=$(fprs | sed -n 1p)
kg --faked-system-time "$past" --quick-add-key "$primary" ed25519 sign 1d
suba=$(fprs | sed -n 2p)
kg --quick-add-key "$primary" ed25519 sign 1d
subb=$(fprs | sed -n 3p)
[ -n "$suba" ] && [ -n "$subb" ] || die "throwaway key generation failed"

# The secret export is taken while subkey A is still expired (2020-01-02),
# and so is a stale public keyring, for a negative check.
kg --armor --export-secret-subkeys "$suba!" >"$keygen/apt-signing-subkey.asc"
kg --export --export-options export-minimal "$primary" >"$keygen/stale-keyring.gpg"
# Renewal, then the refreshed public keyring, as in docs/signing-key.md.
kg --quick-set-expire "$primary" 1d "$suba"
kg --export --export-options export-minimal "$primary" >"$out/test-keyring.gpg"
log "TEST ONLY: primary $primary"
log "TEST ONLY: subkey A $suba (signs), subkey B $subb (must not sign)"

cp -R "$tree/dists" "$out/dists"

log "==> TEST ONLY: signing with scripts/sign-repo.sh (secret on stdin)"
APT_SIGNING_FINGERPRINT="$suba!" APT_SIGNING_PASSPHRASE="$pass" \
  "$here/sign-repo.sh" "$out" "$out/test-keyring.gpg" <"$keygen/apt-signing-subkey.asc"

log "==> TEST ONLY: negative checks"
neg="$keygen/neg"
cp -R "$out/dists" "$neg"
mkdir -p "$keygen/negtree"
mv "$neg" "$keygen/negtree/dists"
if "$here/verify-repo.sh" --no-pool --expect-signer "$subb" "$keygen/negtree" "$out/test-keyring.gpg" 2>/dev/null; then
  die "verify-repo.sh accepted signatures from the wrong subkey"
fi
log "    wrong expected signer: rejected"
if "$here/verify-repo.sh" --no-pool "$keygen/negtree" "$keygen/stale-keyring.gpg" 2>/dev/null; then
  die "verify-repo.sh accepted a signature from a subkey that the keyring says has expired"
fi
log "    keyring where the signing subkey has expired: rejected (apt would refuse it)"
first_release=$(find "$keygen/negtree/dists" -name Release | LC_ALL=C sort | head -n 1)
printf 'Tampered: yes\n' >>"$first_release"
if "$here/verify-repo.sh" --no-pool "$keygen/negtree" "$out/test-keyring.gpg" 2>/dev/null; then
  die "verify-repo.sh accepted a tampered Release"
fi
log "    tampered Release: rejected"

solo=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/apt-test-solo.XXXXXX")
chmod 700 "$solo"
GNUPGHOME="$solo" gpg --batch --no-tty --quiet --pinentry-mode loopback --passphrase-fd 3 \
  --import <"$keygen/apt-signing-subkey.asc" 3< <(printf '%s' "$pass")
if GNUPGHOME="$solo" gpg --batch --no-tty --quiet --pinentry-mode loopback --passphrase-fd 3 \
  --local-user "$suba!" --clearsign --output "$solo/x" "$first_release" \
  3< <(printf '%s' "$pass") 2>"$solo/err"; then
  die "the stale secret export signed without the refreshed keyring; the expiry test proves nothing"
fi
grep -q 'Unusable secret key' "$solo/err" ||
  die "signing with the stale export failed for another reason: $(cat "$solo/err")"
log "    stale export without the refreshed keyring: cannot sign (so importing the keyring first matters)"

log "==> TEST ONLY: signing path verified with gpgv against the throwaway keyring"
