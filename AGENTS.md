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

- Pull requests run **shellcheck** and **actionlint** on all `.github/workflows/*.yml` files.
- Tools are downloaded from upstream releases and verified by SHA256.
- No `curl | sh` or `curl | bash`.

## Pages deployment

- The `github-pages` environment is limited to `main`.
- The `apt-signing` environment is limited to `main`.
- The deploy job uses `pages: write` and `id-token: write` permissions.

## Signing key

- See [docs/signing-key.md](docs/signing-key.md) for the key model.
- The signing key fingerprint is TBD: published after the maintainer creates the key.
