# AGENTS.md

Repository conventions for Montimage/packages.

## General rules

- **No `.deb` files are ever committed to git.** Packages are served from the
  Pages site and signed in CI.
- **No secrets, keys, or private material** are committed. The signing key
  lives only in CI secrets (`APT_SIGNING_KEY`, `APT_SIGNING_PASSPHRASE`) in
  the `apt-signing` environment.
- **Never print signing secrets** in logs or workflow output.
- **Actions must be pinned by full SHA** and only GitHub-owned actions are
  allowed (`actions/*`). No third-party actions.
- **No AI co-author trailers** or "Generated with" footers in commits or PR
  bodies.
- Use **squash merges only**, with the PR title and body.

## CI workflows

- **shellcheck** runs on tracked `*.sh` files and, through actionlint, on
  `run:` blocks inside workflows.
- **actionlint** lints every workflow file (`.yml` and `.yaml`), including
  shellcheck on `run:` blocks.
- Tools are downloaded from upstream releases and verified by SHA256.
- No `curl | sh` or `curl | bash`.

## Pages deployment

- `.github/workflows/apt-repo.yml` is the **only** workflow that deploys Pages.
  A deploy replaces the whole site, so do not add another deployer: put new
  site files in `site/`, which that workflow copies to the root.
- The `github-pages` environment is limited to `main`.
- The `apt-signing` environment is limited to `main`.
- The deploy job uses `pages: write` and `id-token: write` permissions.
- Until the signing key exists, the workflow runs as an unsigned dry run and
  never deploys.

## APT repository scripts

The workflow logic lives in `scripts/` (bash, `set -euo pipefail`,
shellcheck-clean; shared helpers and the distribution → suite map are in
`scripts/common.sh`). Run them locally from the repository root, with work
directories outside the repository:

```sh
W=$(mktemp -d)
scripts/fetch-releases.sh "$W/work"            # needs gh auth; downloads ~390 MB and verifies it
scripts/build-repo.sh "$W/work" "$W/tree" site # unsigned tree
scripts/summarize-repo.sh "$W/tree" "$W/work"
scripts/test-signing.sh "$W/tree" "$W/signed"  # TEST ONLY: throwaway key, gpgv checks
scripts/smoke-install.sh ubuntu:24.04 --tree "$W/tree"   # UNSIGNED, needs docker
scripts/smoke-install.sh debian:13 --tree "$W/tree" \
  --dists "$W/signed/dists" --keyring "$W/signed/test-keyring.gpg"
```

`scripts/sign-repo.sh` and `scripts/detect-signing.sh` run in CI only. Never
run the signing script with the real key outside the `apt-signing` environment.

To lint like CI: `shellcheck scripts/*.sh` and `actionlint` (1.7.12, checksum
verified).

## Signing key

- See [docs/signing-key.md](docs/signing-key.md) for the key model.
- The signing key fingerprint is TBD: published after the maintainer creates the key.
