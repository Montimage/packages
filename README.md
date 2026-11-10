# packages

Signed APT package repository for Montimage MMT tools, served at
https://montimage.github.io/packages.

## What this repository serves

- `.deb` packages for MMT tools, built from [Montimage/mmt-dpi](https://github.com/Montimage/mmt-dpi).
- An APT repository index (`Packages`, `Packages.gz`, `Release`, `Release.gpg`, `InRelease`) signed with an offline primary key.
- The last **2 mmt-dpi releases** are retained at any given time.

## Adding the repository

Use a deb822-format `.sources` file — **never** `apt-key`:

```text
# /etc/apt/sources.list.d/montimage-packages.sources
Types: deb
URIs: https://montimage.github.io/packages
Suites: stable
Components: main
Signed-By: /usr/share/keyrings/montimage-packages-archive-keyring.gpg
```

The signing key fingerprint will be published once the maintainer creates it
(see [docs/signing-key.md](docs/signing-key.md)).

## Key model

- One **offline primary key** held by the maintainer.
- Two signing subkeys:
  - **Subkey A** — signs the APT repository; lives only in this repo's CI
    (`APT_SIGNING_KEY`, `APT_SIGNING_PASSPHRASE` secrets in the `apt-signing`
    environment).
  - **Subkey B** — signs the mmt-dpi source tarball; lives only in
    [Montimage/mmt-dpi](https://github.com/Montimage/mmt-dpi).

See [docs/signing-key.md](docs/signing-key.md) for details on rotation and
revocation.

## CI

Pull requests run [shellcheck](https://www.shellcheck.net/) and [actionlint](https://github.com/rhysd/actionlint) on every workflow file.
See [AGENTS.md](AGENTS.md) for repository conventions.

## License

All packages are distributed under their respective upstream licenses.
