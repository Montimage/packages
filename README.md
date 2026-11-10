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
curl -fsSL https://montimage.github.io/packages/mmt-archive-keyring.gpg \
  | sudo tee /etc/apt/keyrings/mmt.gpg >/dev/null
```

Verify the fingerprint (compare with the published value):

```sh
gpg --show-keys /etc/apt/keyrings/mmt.gpg
```

### Add the source

Use a deb822-format `.sources` file — **never** `apt-key`:

```text
# /etc/apt/sources.list.d/montimage-packages.sources
Types: deb
URIs: https://montimage.github.io/packages
Suites: <your codename>
Components: main
Signed-By: /etc/apt/keyrings/mmt.gpg
```

Replace `<your codename>` with the value from `/etc/os-release` `VERSION_CODENAME`
(e.g. `jammy`, `noble`, `bookworm`, `trixie`).

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
