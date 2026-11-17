# Signing Key

## Key model

One **ed25519 primary key** (certify-only, 5-year expiry) is held by the
maintainer on a designated signing machine with an encrypted disk, in a
dedicated `GNUPGHOME`, and never in CI. It needs a backup kept off that machine
(see [First-time setup](#first-time-setup)). Two signing-only subkeys (2-year
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

| Name | Type | Repository / environment | Description |
|------|------|--------------------------|-------------|
| `APT_SIGNING_KEY` | Secret | this repo, `apt-signing` | ASCII-armoured export of subkey A (`apt-signing-subkey.asc`), re-protected with a CI-only passphrase (see below) |
| `APT_SIGNING_PASSPHRASE` | Secret | this repo, `apt-signing` | CI-only passphrase set on the re-protected export |
| `APT_SIGNING_FINGERPRINT` | Variable | this repo, `apt-signing` | Subkey A's fingerprint with a `!` suffix, used to force signing with subkey A |
| `MMT_RELEASE_SIGNING_KEY` | Secret | Montimage/mmt-dpi | ASCII-armoured export of subkey B (`tarball-signing-subkey.asc`), re-protected the same way |
| `MMT_RELEASE_SIGNING_PASSPHRASE` | Secret | Montimage/mmt-dpi | CI-only passphrase set on that export |

`scripts/detect-signing.sh` signs only when the three `apt-signing` values
**and** the committed `site/montimage-archive-keyring.gpg` all exist; a run that
finds only some of them fails instead of falling back to a dry run.

### Exporting and re-protecting a subkey

Run with the signing machine's `GNUPGHOME`. Set `SUB` and `OUT` for the subkey:

| Subkey | `SUB` | `OUT` |
|--------|-------|-------|
| A | `"$SUBA"` | `apt-signing-subkey` |
| B | `"$SUBB"` | `tarball-signing-subkey` |

```sh
gpg --armor --export-secret-subkeys "$SUB"'!' > "$OUT.asc"
```

That file is still protected by the **primary key's** passphrase. To give it a
CI-only passphrase:

```sh
T=$(mktemp -d); chmod 700 "$T"
gpg --homedir "$T" --batch --import "$OUT.asc"
gpg --homedir "$T" --passwd "$FPR"   # asks the old passphrase, then a NEW CI passphrase
gpg --homedir "$T" --armor --export-secret-subkeys "$SUB"'!' > "$OUT-reprotected.asc"
gpgconf --homedir "$T" --kill gpg-agent; rm -rf "$T"
```

`--passwd` then prints `error changing passphrase: No secret key` and exits 2.
This is expected: the export holds only a stub of the primary key, so gpg cannot
change a passphrase on it. The subkey itself is re-protected; the export
step asks for the new CI passphrase, not the primary one.

`$OUT-reprotected.asc` is what goes into `APT_SIGNING_KEY` (subkey A) or
`MMT_RELEASE_SIGNING_KEY` (subkey B). Delete `$OUT.asc` once the secret is set.

### Exporting the public key

```sh
# This repo: binary keyring, read by gpgv and by apt's Signed-By.
gpg --export --export-options export-minimal "$FPR" > montimage-archive-keyring.gpg
# Montimage/mmt-dpi: ASCII-armoured, as uscan expects for debian/upstream/signing-key.asc.
gpg --armor --export --export-options export-minimal "$FPR" > signing-key.asc
```

## First-time setup

Do this once, on the signing machine, with a dedicated `GNUPGHOME` (mode 700).

1. **Create the key.**

   ```sh
   gpg --quick-generate-key "Montimage Release Signing <developer@montimage.eu>" ed25519 cert 5y
   FPR=<the fingerprint printed above>
   gpg --quick-add-key "$FPR" ed25519 sign 2y   # subkey A
   gpg --quick-add-key "$FPR" ed25519 sign 2y   # subkey B
   gpg --list-keys --with-subkey-fingerprints "$FPR"
   SUBA=<first subkey fingerprint>; SUBB=<second subkey fingerprint>
   ```

   Record the three fingerprints with the key backup.

2. **Keep the revocation certificate.** gpg wrote it to
   `$GNUPGHOME/openpgp-revocs.d/$FPR.rev`. Back up `GNUPGHOME` (and the
   primary passphrase, in a password manager) off the signing machine, and keep
   a copy of the `.rev` **apart from that backup** (another medium or a
   printout in another place), so losing the machine and the backup together
   does not also lose the means to revoke the key.

3. **Export** the two subkeys and re-protect them, then export the public key
   (see the two sections above). Only the two `*-reprotected.asc` files (each
   with its CI passphrase) and the two public-key files leave `GNUPGHOME`.

4. **Set the secrets and commit the public key back to back.** In each repo,
   either half alone fails by design: here, a run on `main` with only the
   secrets or only the keyring stops (`scripts/detect-signing.sh`); in
   mmt-dpi, a release with only the secret or only `signing-key.asc` fails
   (`tools/ci/sign-source-tarball.sh`).

   **This repo.** Pull-request runs never reach the signing job, so:
   1. Open a pull request that adds `montimage-archive-keyring.gpg` as
      `site/montimage-archive-keyring.gpg` and puts `$FPR` under
      [Fingerprint](#fingerprint).
   2. Set the three `apt-signing` values:

      ```sh
      gh secret set APT_SIGNING_KEY -R Montimage/packages --env apt-signing < apt-signing-subkey-reprotected.asc
      gh secret set APT_SIGNING_PASSPHRASE -R Montimage/packages --env apt-signing   # prompts
      gh variable set APT_SIGNING_FINGERPRINT -R Montimage/packages --env apt-signing --body "$SUBA"'!'
      ```

   3. Merge the pull request. The run on `main` signs and deploys the repository.

   **Montimage/mmt-dpi** (issue #77). When the pull request that adds
   `signing-key.asc` as `debian/upstream/signing-key.asc` is ready to merge,
   and no release is in progress:

   ```sh
   gh secret set MMT_RELEASE_SIGNING_KEY -R Montimage/mmt-dpi < tarball-signing-subkey-reprotected.asc
   gh secret set MMT_RELEASE_SIGNING_PASSPHRASE -R Montimage/mmt-dpi                # prompts
   ```

   then merge it.

5. **Clean up.** Delete the `*-reprotected.asc` files and their CI passphrases
   once the secrets are set.

## Rotation

After **every** key change below (an expiry extension, a new subkey, a
revocation), CI must import the refreshed keyring before signing, and users
must download the keyring again: apt does not update it by itself.

### Expiry extension (keeps CI secrets)

Before a subkey expires (~2 months ahead):

1. Extend both subkeys:
   `gpg --quick-set-expire "$FPR" 2y "$SUBA" "$SUBB"`.
2. Re-export the public key in both forms (see
   [Exporting the public key](#exporting-the-public-key)).
3. Commit `montimage-archive-keyring.gpg` to `site/montimage-archive-keyring.gpg`
   in this repo and `signing-key.asc` to `debian/upstream/signing-key.asc` in
   mmt-dpi.

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
3. Set `SUBA` (or `SUBB`) to the **new** subkey's fingerprint
   (`gpg --list-keys --with-subkey-fingerprints "$FPR"`), then export and
   re-protect it (see
   [Exporting and re-protecting a subkey](#exporting-and-re-protecting-a-subkey)).
4. **Replace the CI secrets:**
   - Subkey A: `APT_SIGNING_KEY`, `APT_SIGNING_PASSPHRASE` and
     `APT_SIGNING_FINGERPRINT` (new fingerprint with `!`), in this repo.
   - Subkey B: `MMT_RELEASE_SIGNING_KEY` and `MMT_RELEASE_SIGNING_PASSPHRASE`,
     in Montimage/mmt-dpi.
5. Republish the public key in **both** repos:
   `site/montimage-archive-keyring.gpg` in this repo and
   `debian/upstream/signing-key.asc` in mmt-dpi.

## Revocation

### Subkey A compromised

1. Revoke: `gpg --edit-key "$FPR"` → `key N` → `revkey` → `save`.
2. Add a new subkey: `gpg --quick-add-key "$FPR" ed25519 sign 2y`.
3. Set `SUBA` to the new subkey's fingerprint, then export it to
   `apt-signing-subkey.asc` and re-protect it (see
   [Exporting and re-protecting a subkey](#exporting-and-re-protecting-a-subkey)).
4. Replace the three CI values (`APT_SIGNING_KEY`, `APT_SIGNING_PASSPHRASE`,
   `APT_SIGNING_FINGERPRINT`).
5. Republish the refreshed public key as `site/montimage-archive-keyring.gpg`
   here and `debian/upstream/signing-key.asc` in mmt-dpi (the keyring holds
   both subkeys).

### Subkey B compromised

Same procedure with `SUBB`, `tarball-signing-subkey.asc` and the two
`MMT_RELEASE_SIGNING_*` secrets of
[Montimage/mmt-dpi](https://github.com/Montimage/mmt-dpi). The keyring published
here also contains subkey B, so a subkey B change republishes the keyring here
AND updates mmt-dpi `debian/upstream/signing-key.asc`.

### Primary key compromised or lost

1. Publish the revocation certificate. Take the copy of
   `openpgp-revocs.d/<FPR>.rev` (from `GNUPGHOME`, its backup, or the copy kept apart). It is
   guarded: remove the leading `:` on its `-----BEGIN` line. On a machine that
   does not hold the key (the signing machine and its backup are lost), first import the published
   keyring, `gpg --import site/montimage-archive-keyring.gpg`, because gpg
   cannot apply a revocation to a key it does not have. Then
   `gpg --import <FPR>.rev`.
2. Re-export the public key into `site/montimage-archive-keyring.gpg` in this
   repo and `debian/upstream/signing-key.asc` in mmt-dpi.
3. Create a new key ([First-time setup](#first-time-setup), steps 1–5).
4. Announce the new fingerprint. Users must install the new keyring by hand.

## Fingerprint

TBD: published after the maintainer creates the key.
