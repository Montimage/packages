# packages

Signed APT package repository for Montimage MMT tools, served at
https://montimage.github.io/packages.

> **Status: dry run.** The signing key does not exist yet, so the workflow
> builds and tests the repository but does not sign or deploy it. It starts
> publishing on its own once the maintainer has stored the `apt-signing`
> secrets and committed `site/montimage-archive-keyring.gpg`
> (see [How the repository is built](#how-the-repository-is-built)).

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
(`jammy`, `noble`, `resolute`, `bookworm` or `trixie`).

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

## How the repository is built

[`.github/workflows/apt-repo.yml`](.github/workflows/apt-repo.yml) rebuilds the
whole repository on every run; nothing is kept between runs and no package is
committed. It runs on a `repository_dispatch` of type `mmt-dpi-release` (sent by
the mmt-dpi release job), on `workflow_dispatch`, on pushes to `main` that touch
`scripts/`, `site/` or the workflow, and, as a dry run only, on every pull
request (the build runs when the pull request touches those paths).

1. **Fetch and verify** ([`scripts/fetch-releases.sh`](scripts/fetch-releases.sh)).
   It takes the last 2 published, non-draft, non-prerelease Releases of
   Montimage/mmt-dpi, and from each only `mmt-dpi_<distro>-<ver>_<arch>.deb` and
   `mmt-dpi-security_<distro>-<ver>_<arch>.deb`. The run stops, before anything
   is signed, unless `SHA256SUMS` and every `.deb` have a build-provenance
   attestation from mmt-dpi's `release-packages.yml` at that tag
   (`gh attestation verify`), and every `.deb` matches `SHA256SUMS`.
   `Package`, `Version` and `Architecture` are read with `dpkg-deb`, not from
   the file name.
2. **Build** ([`scripts/build-repo.sh`](scripts/build-repo.sh)), with
   `apt-ftparchive`. Every distribution's package has the same Debian version,
   so each suite has its own pool:

   | Release asset | Suite |
   |---|---|
   | `ubuntu-22.04` | `jammy` |
   | `ubuntu-24.04` | `noble` |
   | `ubuntu-26.04` | `resolute` |
   | `debian-12` | `bookworm` |
   | `debian-13` | `trixie` |

   ```text
   pool/<suite>/main/m/mmt-dpi/<package>_<version>_<arch>.deb
   dists/<suite>/main/binary-{amd64,arm64}/Packages{,.gz}
   dists/<suite>/{Release,InRelease,Release.gpg}
   ```

   `Release` has Origin and Label `Montimage`, Suite and Codename the suite,
   Architectures `amd64 arm64`, Components `main`, and no `Valid-Until`. Its
   `Date` and every file time are the publication time of the newest release,
   so the same releases always give the same unsigned tree. Because of this, a
   published mmt-dpi release must never be deleted or demoted: `Date` would move
   backwards, and apt silently keeps its older indexes, so existing clients get
   a 404 for the removed version. Publish a newer release instead (see
   [AGENTS.md](AGENTS.md#never-delete-or-demote-a-published-mmt-dpi-release)). The files in
   `site/` (`index.html`, the public keyring) are copied to the root.
3. **Test, in every run.** The tree is signed with a throwaway key made in the
   job and checked with `gpgv` ([`scripts/test-signing.sh`](scripts/test-signing.sh)),
   then `mmt-dpi` is installed from it in `ubuntu:24.04` and `debian:13`
   containers, unsigned and with the throwaway key
   ([`scripts/smoke-install.sh`](scripts/smoke-install.sh)). The unsigned tree
   is uploaded as the `apt-repo-unsigned` workflow artifact.
4. **Sign** ([`scripts/sign-repo.sh`](scripts/sign-repo.sh)), on `main` only, in
   the `apt-signing` environment. The secret subkey is read from stdin into a
   throwaway `GNUPGHOME` under `$RUNNER_TEMP`, after the committed public
   keyring (so a renewed expiry is honoured), and removed on exit. It writes
   `InRelease` and `Release.gpg` with `--local-user "$APT_SIGNING_FINGERPRINT"`.
5. **Verify and deploy.** Every signature is checked with `gpgv` against
   `site/montimage-archive-keyring.gpg` alone, with every index and pool hash
   ([`scripts/verify-repo.sh`](scripts/verify-repo.sh)), and the tree is deployed
   to Pages. `mmt-dpi` is then installed from the live URL in `ubuntu:24.04` and
   `debian:13` containers, once the site serves the `InRelease` and `Packages`
   just signed (Pages caches for up to 10 minutes; the smoke waits at most 15),
   and it must be the newest version.

**Dry run.** While the `apt-signing` secrets and the committed keyring are
missing, steps 1–3 run and steps 4–5 do not: nothing is deployed, and the
published site stays as it is. A partial setup (for example the secret without
the committed keyring) fails the run instead of falling back to a dry run.

This workflow is the only one that deploys Pages: a deploy replaces the whole
site, so a second deployer would erase the repository.

## CI

Pull requests run [shellcheck](https://www.shellcheck.net/) and [actionlint](https://github.com/rhysd/actionlint) on every workflow file,
and the APT repository dry run when they touch `scripts/`, `site/` or its workflow.
The `apt-repo-gate` job reports on every pull request (it passes when the dry run
passed, or was skipped because none of those paths changed), so it is the check
to require, together with `lint`.
See [AGENTS.md](AGENTS.md) for repository conventions.

## License

All packages are distributed under their respective upstream licenses.
