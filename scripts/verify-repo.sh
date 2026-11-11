#!/usr/bin/env bash
# verify-repo.sh: check a signed APT repository tree before it is deployed.
#
# Usage: scripts/verify-repo.sh [--no-pool] [--expect-signer <fpr>] <tree> <keyring>
#
# For every dists/<suite>/Release:
#   - InRelease and Release.gpg verify with gpgv against <keyring> alone (an
#     empty GNUPGHOME, so no other key can count), and InRelease carries the
#     same text as Release;
#   - with --expect-signer, both signatures were made by that (sub)key;
#   - the Release fields are the expected ones, with no Valid-Until;
#   - every Packages{,.gz} has the size and SHA256 that Release lists;
#   - unless --no-pool, every pool file has the size and SHA256 that Packages
#     lists.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/common.sh
. "$here/common.sh"

check_pool=1
signer=
while [ $# -gt 0 ]; do
  case "$1" in
    --no-pool) check_pool=0; shift ;;
    --expect-signer) signer=${2:-}; shift 2 ;;
    --) shift; break ;;
    -*) die "unknown option $1" ;;
    *) break ;;
  esac
done
[ $# -eq 2 ] || die "usage: $0 [--no-pool] [--expect-signer <fpr>] <tree> <keyring>"
tree=$(cd "$1" && pwd) || die "tree $1 not found"
[ -s "$2" ] || die "keyring $2 is missing or empty"
keyring=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
signer=$(printf '%s' "$signer" | tr '[:lower:]' '[:upper:]')

require_cmd gpgv sha256sum awk cmp

scratch=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/apt-verify.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
mkdir -m 700 "$scratch/gnupg"

gpgv_check() { # <label> <gpgv args...>; prints the signing key fingerprint
  local label=$1 status
  shift
  status="$scratch/status"
  if ! GNUPGHOME="$scratch/gnupg" gpgv --status-fd 3 --keyring "$keyring" "$@" \
    3>"$status" 2>"$scratch/gpgv.err"; then
    cat "$scratch/gpgv.err" >&2
    die "gpgv rejected $label"
  fi
  awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print $3 }' "$status"
}

field() { awk -v k="$1:" '$1 == k { sub(/^[^:]*: */, ""); print; exit }' "$2"; }

file_ok() { # <path> <size> <sha256> <label>
  [ -f "$1" ] || die "$4: $1 is missing"
  [ "$(stat -c %s "$1")" = "$2" ] || die "$4: size of $1 is not $2"
  [ "$(sha256sum "$1" | awk '{ print $1 }')" = "$3" ] || die "$4: SHA256 of $1 does not match"
}

n=0
for release in "$tree"/dists/*/Release; do
  [ -f "$release" ] || continue
  dir=$(dirname "$release")
  suite=$(basename "$dir")
  for f in InRelease Release.gpg; do
    [ -s "$dir/$f" ] || die "$suite: $f is missing"
  done

  fp_in=$(gpgv_check "$suite/InRelease" --output "$scratch/inrelease.txt" "$dir/InRelease")
  cmp -s "$scratch/inrelease.txt" "$release" || die "$suite: InRelease does not carry the text of Release"
  fp_det=$(gpgv_check "$suite/Release.gpg" "$dir/Release.gpg" "$release")
  if [ -n "$signer" ]; then
    [ "$fp_in" = "$signer" ] || die "$suite: InRelease signed by '$fp_in', expected $signer"
    [ "$fp_det" = "$signer" ] || die "$suite: Release.gpg signed by '$fp_det', expected $signer"
  fi

  [ "$(field Origin "$release")" = Montimage ] || die "$suite: Origin is not Montimage"
  [ "$(field Label "$release")" = Montimage ] || die "$suite: Label is not Montimage"
  [ "$(field Suite "$release")" = "$suite" ] || die "$suite: Suite is not $suite"
  [ "$(field Codename "$release")" = "$suite" ] || die "$suite: Codename is not $suite"
  [ "$(field Architectures "$release")" = "${APT_ARCHES[*]}" ] || die "$suite: Architectures is not '${APT_ARCHES[*]}'"
  [ "$(field Components "$release")" = "$APT_COMPONENT" ] || die "$suite: Components is not $APT_COMPONENT"
  [ -z "$(field Valid-Until "$release")" ] || die "$suite: Release must not set Valid-Until"

  awk '/^SHA256:/ { on = 1; next } /^[^ ]/ { on = 0 } on { print $1, $2, $3 }' "$release" >"$scratch/sums"
  for arch in "${APT_ARCHES[@]}"; do
    for f in Packages Packages.gz; do
      rel="$APT_COMPONENT/binary-$arch/$f"
      read -r sha size < <(awk -v p="$rel" '$3 == p { print $1, $2 }' "$scratch/sums") ||
        die "$suite: Release does not list $rel"
      file_ok "$dir/$rel" "$size" "$sha" "$suite"
    done
    if [ "$check_pool" -eq 1 ]; then
      awk -F': ' '/^Filename: / { f = $2 } /^Size: / { s = $2 } /^SHA256: / { h = $2 }
        /^$/ && f != "" { print f, s, h; f = "" } END { if (f != "") print f, s, h }' \
        "$dir/$APT_COMPONENT/binary-$arch/Packages" |
        while read -r path size sha; do
          file_ok "$tree/$path" "$size" "$sha" "$suite/$arch"
        done
    fi
  done
  log "    $suite: InRelease and Release.gpg verified with gpgv (key ${fp_in}), indexes match"
  n=$((n + 1))
done
[ "$n" -gt 0 ] || die "no dists/<suite>/Release in $tree"
log "==> $n suites verified against $(basename "$keyring")"
