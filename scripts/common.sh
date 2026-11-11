# shellcheck shell=bash
# common.sh: helpers shared by the APT repository scripts. Source it; do not run it.

# Distribution token in the mmt-dpi asset name -> APT suite (codename).
# Ubuntu 26.04 is "resolute" (Resolute Raccoon): VERSION_CODENAME in the
# official ubuntu:26.04 image, and https://changelogs.ubuntu.com/meta-release.
codename_for() {
  case "$1" in
    ubuntu-22.04) echo jammy ;;
    ubuntu-24.04) echo noble ;;
    ubuntu-26.04) echo resolute ;;
    debian-12) echo bookworm ;;
    debian-13) echo trixie ;;
    *) return 1 ;;
  esac
}

# Suites and architectures the repository serves, in a fixed order.
# shellcheck disable=SC2034  # used by the scripts that source this file
APT_SUITES=(jammy noble resolute bookworm trixie)
# shellcheck disable=SC2034
APT_ARCHES=(amd64 arm64)
# shellcheck disable=SC2034
APT_COMPONENT=main
# Binary packages accepted from a Release.
# shellcheck disable=SC2034
APT_PACKAGES=(mmt-dpi mmt-dpi-security)
# Pool directory: every package is built from the mmt-dpi source tree.
# shellcheck disable=SC2034
APT_POOL_SOURCE=mmt-dpi

log() { printf '%s\n' "$*" >&2; }
die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "required command not found: $c"
  done
}

# Print a control field of a .deb with surrounding whitespace removed.
deb_field() {
  local value
  value=$(dpkg-deb -f "$1" "$2") || die "dpkg-deb cannot read field $2 of $1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}
