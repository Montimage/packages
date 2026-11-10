# Signing Key

## Key model

One **offline primary key** (GPG/PGP) is held by the maintainer. Two signing
subkeys are derived from it:

| Subkey | Purpose | Location |
|--------|---------|----------|
| A | APT repository signing | This repo only (`APT_SIGNING_KEY`, `APT_SIGNING_PASSPHRASE` secrets in the `apt-signing` environment) |
| B | mmt-dpi source tarball signing | [Montimage/mmt-dpi](https://github.com/Montimage/mmt-dpi) only |

## CI secrets

| Secret | Environment | Description |
|--------|-------------|-------------|
| `APT_SIGNING_KEY` | `apt-signing` | Base64-encoded private key for subkey A |
| `APT_SIGNING_PASSPHRASE` | `apt-signing` | Passphrase for the private key |
| `APT_SIGNING_FINGERPRINT` | `apt-signing` | Fingerprint of the primary key (read-only reference) |

## Rotation and revocation

1. Generate a new primary key pair offline.
2. Derive a new subkey A and publish it to the APT repository.
3. Update `APT_SIGNING_KEY` and `APT_SIGNING_PASSPHRASE` secrets in the
   `apt-signing` environment.
4. Publish the new public subkey via the Pages site.
5. Archive the old key; do not delete it until the next 2 release cycle has
   passed.
6. Document the new fingerprint in [README.md](../README.md) and update the
   `Signed-By` reference if needed.

## Fingerprint

TBD: published after the maintainer creates the key.
