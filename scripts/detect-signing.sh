#!/usr/bin/env bash
# detect-signing.sh: decide between a signed publish and an unsigned dry run.
#
# Usage: scripts/detect-signing.sh <public-keyring>
#
# Environment (set from the apt-signing environment; the secrets themselves
# are not passed, only whether they are set):
#   APT_SIGNING_KEY_SET, APT_SIGNING_PASSPHRASE_SET  "true" when the secret is set
#   APT_SIGNING_FINGERPRINT                          variable
#
# Prints "signed" when the three values and the committed public keyring all
# exist, "dry-run" when none of them exists, and fails when only some do, so a
# half-configured key never silently turns into a dry run. Also writes
# mode=<value> to $GITHUB_OUTPUT when that is set, plus signer=<fingerprint>
# (APT_SIGNING_FINGERPRINT without its "!") in signed mode.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/common.sh
. "$here/common.sh"

[ $# -eq 1 ] || die "usage: $0 <public-keyring>"
keyring=$1

present=()
missing=()
check() { if [ "$2" = yes ]; then present+=("$1"); else missing+=("$1"); fi; }
check "secret APT_SIGNING_KEY" "$([ "${APT_SIGNING_KEY_SET:-}" = true ] && echo yes || echo no)"
check "secret APT_SIGNING_PASSPHRASE" "$([ "${APT_SIGNING_PASSPHRASE_SET:-}" = true ] && echo yes || echo no)"
check "variable APT_SIGNING_FINGERPRINT" "$([ -n "${APT_SIGNING_FINGERPRINT:-}" ] && echo yes || echo no)"
check "committed $keyring" "$([ -s "$keyring" ] && echo yes || echo no)"

if [ "${#missing[@]}" -eq 0 ]; then
  mode=signed
  log "Signing key configured: the repository is signed and deployed."
elif [ "${#present[@]}" -eq 0 ]; then
  mode=dry-run
  log "::notice title=APT repository dry run::No signing key is configured yet (no apt-signing secrets, no $keyring). The tree is built unsigned and uploaded as an artifact; nothing is deployed."
else
  log "Present: ${present[*]}"
  log "Missing: ${missing[*]}"
  die "the signing key is only partly configured; add the missing items (docs/signing-key.md) or remove the others"
fi

echo "$mode"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "mode=$mode" >>"$GITHUB_OUTPUT"
  if [ "$mode" = signed ]; then
    [[ "$APT_SIGNING_FINGERPRINT" =~ ^([0-9A-Fa-f]{40}|[0-9A-Fa-f]{64})!$ ]] ||
      die "APT_SIGNING_FINGERPRINT must be the signing subkey fingerprint followed by '!'"
    echo "signer=${APT_SIGNING_FINGERPRINT%!}" >>"$GITHUB_OUTPUT"
  fi
fi
