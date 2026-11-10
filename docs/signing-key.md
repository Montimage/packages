# Signing Key

## Key model

One **offline ed25519 primary key** (certify-only, 5-year expiry) is held by
the maintainer on an encrypted removable drive. Two signing-only subkeys (2-year
expiry) are generated and certified by it:

| Subkey | Purpose | Location |
|--------|---------|----------|
| A | APT repository signing (`InRelease`, `Release.gpg`) | This repo only (`apt-signing` environment) |
| B | mmt-dpi source tarball signing | [Montimage/mmt-dpi](https://github.com/Montimage/mmt-dpi) only |

CI never holds the primary key. Each repo holds only its own subkey.

## CI secrets and variables

| Name | Type | Environment | Description |
|------|------|-------------|-------------|
| `APT_SIGNING_KEY` | Secret | `apt-signing` | Base64-encoded secret for subkey A, exported with `gpg --armor --export-secret-subkeys <subkeyA-fpr>!` |
| `APT_SIGNING_PASSPHRASE` | Secret | `apt-signing` | Passphrase for the subkey A export (CI-only, different from the primary's) |
| `APT_SIGNING_FINGERPRINT` | Variable | `apt-signing` | Subkey A's fingerprint with a `!` suffix, used to force signing with subkey A |

## Rotation

Routine rotation (before a subkey expires, ~2 months ahead):

1. Extend expiry: `gpg --quick-set-expire "$FPR" 2y "$SUBA"` (or add a new
   subkey with `gpg --quick-add-key "$FPR" ed25519 sign 2y`).
2. Re-export the public key (step 3 below).
3. Send the new public files for a PR — the CI secrets do not change because
   the expiry lives in the public key.

## Revocation

### Subkey A compromised

1. Revoke: `gpg --edit-key "$FPR"` → `key N` → `revkey` → `save`.
2. Add a new subkey: `gpg --quick-add-key "$FPR" ed25519 sign 2y`.
3. Re-export the public keyring:
   `gpg --export --export-options export-minimal "$FPR" > montimage-archive-keyring.gpg`.
4. Commit the new keyring to the repo so it is published on Pages.
5. Users refresh automatically on the next `apt update`.

### Subkey B compromised

Same procedure as subkey A, but in [Montimage/mmt-dpi](https://github.com/Montimage/mmt-dpi).

### Primary key compromised or lost

1. Publish the revocation certificate (kept offline at
   `$GNUPGHOME/openpgp-revocs.d/<FPR>.rev`).
2. Create a new primary key and two subkeys (see the maintainer's procedure).
3. Announce the new fingerprint. Users must install the new keyring by hand.

## Fingerprint

TBD: published after the maintainer creates the key.
