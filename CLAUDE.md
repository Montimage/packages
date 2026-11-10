# Project Configuration

## Repository conventions

Always read [AGENTS.md](AGENTS.md) before making changes. Key rules:

- No `.deb` files in git.
- No secrets or keys committed.
- The signing secret is used only in the `apt-signing` environment and is never printed.
- Actions pinned by full SHA, GitHub-owned only.
- No AI co-author trailers or "Generated with" footers.
- Squash merges only.
