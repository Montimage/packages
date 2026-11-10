# packages

Signed APT package repository for Montimage MMT tools, served at
https://montimage.github.io/packages.

## What this repository serves

- `.deb` packages for MMT tools, built from [Montimage/mmt-dpi](https://github.com/Montimage/mmt-dpi).
- An APT repository index (`Packages`, `Packages.gz`, `Release`, `Release.gpg`, `InRelease`) signed by **subkey A** (the primary key stays offline).
- The last **2 mmt-dpi releases** are retained at any given time.

## Adding the repository

### Install the signing key

```sh
sudo apt-get install -y curl gnupg
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL -o /tmp/montimage-archive-keyring.gpg https://montimage.github.io/packages/montimage-archive-keyring.gpg
gpg --show-keys /tmp/montimage-archive-keyring.gpg
```

Compare the fingerprint with the one published in
[docs/signing-key.md#fingerprint](docs/signing-key.md#fingerprint) (TBD until
the maintainer creates the key). Then install:

```sh
sudo install -m 0644 /tmp/montimage-archive-keyring.gpg /etc/apt/keyrings/montimage-archive-keyring.gpg
```

### Add the source

Use a deb822-format `.sources` file — **never** `apt-key`:

```text
# /etc/apt/sources.list.d/montimage-packages.sources
Types: deb
URIs: https://montimage.github.io/packages
Suites: <your codename>
Components: main
Signed-By: /etc/apt/keyrings/montimage-archive-keyring.gpg
```

Replace `<your codename>` with the value from `/etc/os-release` `VERSION_CODENAME`
(e.g. `jammy`, `noble`, `bookworm`, `trixie`).

```sh
sudo apt-get update && sudo apt-get install mmt-dpi
```

> **Note:** after any key change (a new expiry, a new subkey, a revocation),
> download the keyring again. apt does not update it by itself.

## Key model

- One **offline ed25519 primary key** (certify-only, 5-year expiry) held by the
  maintainer.
- Two signing-only subkeys (2-year expiry):
  - **Subkey A** — signs the APT repository; lives only in this repo's CI
    (`apt-signing` environment).
  - **Subkey B** — signs the mmt-dpi source tarball; lives only in
    [Montimage/mmt-dpi](https://github.com/Montimage/mmt-dpi).

See [docs/signing-key.md](docs/signing-key.md) for rotation and revocation.

## CI

Pull requests run [shellcheck](https://www.shellcheck.net/) and [actionlint](https://github.com/rhysd/actionlint) on every workflow file.
See [AGENTS.md](AGENTS.md) for repository conventions.

## License

All packages are distributed under their respective upstream licenses.
