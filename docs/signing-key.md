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

## Variable definitions

- `FPR` — primary key fingerprint
- `SUBA` — subkey A fingerprint
- `SUBB` — subkey B fingerprint
- `N` — subkey position in the `gpg --edit-key` listing (1-based)

## CI secrets and variables

| Name | Type | Environment | Description |
|------|------|-------------|-------------|
| `APT_SIGNING_KEY` | Secret | `apt-signing` | ASCII-armoured export of subkey A, produced with `gpg --armor --export-secret-subkeys <SUBA>!` and re-protected (see below) |
| `APT_SIGNING_PASSPHRASE` | Secret | `apt-signing` | CI-only passphrase set on the re-protected export |
| `APT_SIGNING_FINGERPRINT` | Variable | `apt-signing` | Subkey A's fingerprint with a `!` suffix, used to force signing with subkey A |

### Re-protecting the export

`gpg --armor --export-secret-subkeys <SUBA>!` produces a file protected by the
**primary key's** passphrase. To give it a CI-only passphrase:

```sh
T=$(mktemp -d); chmod 700 "$T"
gpg --homedir "$T" --batch --import apt-signing-subkey.asc
gpg --homedir "$T" --passwd "$FPR"   # asks the old passphrase, then a NEW CI passphrase
gpg --homedir "$T" --armor --export-secret-subkeys "$SUBA!" > apt-signing-subkey-reprotected.asc
gpgconf --homedir "$T" --kill gpg-agent; rm -rf "$T"
```

The re-protected file is what gets stored in `APT_SIGNING_KEY`.

## Rotation

### Expiry extension (keeps CI secrets)

Before a subkey expires (~2 months ahead):

1. Extend both subkeys:
   `gpg --quick-set-expire "$FPR" 2y "$SUBA" "$SUBB"`.
2. Re-export the public keyring:
   `gpg --export --export-options export-minimal "$FPR" > montimage-archive-keyring.gpg`.
3. Commit the keyring to `site/montimage-archive-keyring.gpg` in this repo and
   `debian/upstream/signing-key.asc` in mmt-dpi.

The CI **secrets** do not change: the expiry lives in the public key. However,
CI must import the refreshed `site/montimage-archive-keyring.gpg` before it
signs, otherwise it reports the subkey as unusable once the old expiry has
passed.

### Adding a new subkey (replaces CI secrets)

When rotating to a new subkey or a subkey is leaked:

1. If compromised, revoke it first:
   `gpg --edit-key "$FPR"` → `key N` → `revkey` → `save`.
2. Add a new subkey:
   `gpg --quick-add-key "$FPR" ed25519 sign 2y`.
3. Export the new subkey and re-protect it (see Re-protecting above).
4. **Replace the CI secrets:**
   - Subkey A: `APT_SIGNING_KEY`, `APT_SIGNING_PASSPHRASE` and
     `APT_SIGNING_FINGERPRINT` (new fingerprint with `!`).
   - Subkey B: `MMT_RELEASE_SIGNING_KEY` and `MMT_RELEASE_SIGNING_PASSPHRASE`.
5. Republish the public keyring in **both** repos:
   `site/montimage-archive-keyring.gpg` in this repo and
   `debian/upstream/signing-key.asc` in mmt-dpi.

## Revocation

### Subkey A compromised

1. Revoke: `gpg --edit-key "$FPR"` → `key N` → `revkey` → `save`.
2. Add a new subkey: `gpg --quick-add-key "$FPR" ed25519 sign 2y`.
3. Export the new subkey and re-protect it (see Re-protecting above).
4. Replace the three CI values (`APT_SIGNING_KEY`, `APT_SIGNING_PASSPHRASE`,
   `APT_SIGNING_FINGERPRINT`).
5. Republish the refreshed public keyring as
   `site/montimage-archive-keyring.gpg`.

After every key change, CI must import the refreshed keyring before signing,
and users must download the keyring again (apt does not update it by itself).

### Subkey B compromised

Same procedure as subkey A, but in [Montimage/mmt-dpi](https://github.com/Montimage/mmt-dpi).
The keyring published here also contains subkey B, so a subkey B change
republishes the keyring here AND updates mmt-dpi `debian/upstream/signing-key.asc`.

### Primary key compromised or lost

1. Publish the revocation certificate. The file at
   `$GNUPGHOME/openpgp-revocs.d/<FPR>.rev` is guarded: remove the leading `:`
   on its `-----BEGIN` line, then `gpg --import <FPR>.rev`.
2. Re-export the keyring into `site/montimage-archive-keyring.gpg` in this repo
   and `debian/upstream/signing-key.asc` in mmt-dpi.
3. Create a new key (see the maintainer's procedure, steps 1–5).
4. Announce the new fingerprint. Users must install the new keyring by hand.

## Fingerprint

TBD: published after the maintainer creates the key.
