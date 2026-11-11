#!/usr/bin/env bash
# fetch-releases.sh: download and verify the .deb inputs of the APT repository.
#
# Usage: scripts/fetch-releases.sh <work-dir>
#
# Selects the last RELEASE_COUNT (default 2) published, non-draft,
# non-prerelease Releases of SOURCE_REPO (default Montimage/mmt-dpi), newest
# first by publication date. For each one it downloads SHA256SUMS and the
# canonical packages, mmt-dpi_<distro>-<ver>_<arch>.deb and
# mmt-dpi-security_<distro>-<ver>_<arch>.deb, and fails unless:
#   - SHA256SUMS has a build-provenance attestation from the release workflow
#     at that tag;
#   - every .deb matches its SHA256SUMS line and has that attestation too;
#   - Package and Architecture read with dpkg-deb match the file name.
# Nothing is skipped: a missing or failing check stops the run.
#
# Writes into <work-dir>:
#   <tag>/SHA256SUMS, <tag>/<asset>.deb
#   releases.tsv  tag, published_at, epoch (newest first)
#   inputs.tsv    tag, asset path, package, version, arch, distro, codename, sha256
#
# Needs gh (authenticated: GH_TOKEN in CI), jq, dpkg-deb, sha256sum.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/common.sh
. "$here/common.sh"

[ $# -eq 1 ] || die "usage: $0 <work-dir>"
work=$1
repo=${SOURCE_REPO:-Montimage/mmt-dpi}
count=${RELEASE_COUNT:-2}
signer_workflow="$repo/.github/workflows/release-packages.yml"

require_cmd gh jq dpkg-deb sha256sum awk
[[ "$count" =~ ^[1-9][0-9]*$ ]] || die "RELEASE_COUNT must be a positive integer, got '$count'"

mkdir -p "$work"
work=$(cd "$work" && pwd)
[ -z "$(ls -A "$work")" ] || die "work dir $work is not empty"

attest() { # <file> <tag>
  # The attestation must come from the release workflow, on GitHub-hosted
  # runners, for this exact tag.
  if ! gh attestation verify "$1" --repo "$repo" \
    --signer-workflow "$signer_workflow" \
    --source-ref "refs/tags/$2" \
    --deny-self-hosted-runners >/dev/null; then
    die "build-provenance attestation check failed for $(basename "$1") from $repo $2"
  fi
}

log "==> Selecting the last $count published releases of $repo"
gh api --paginate "repos/$repo/releases?per_page=100" \
  --jq '.[] | select(.draft == false and .prerelease == false) | [.published_at, .tag_name] | @tsv' \
  >"$work/all-releases.tsv" || die "cannot list the releases of $repo"
LC_ALL=C sort -r "$work/all-releases.tsv" | sed -n "1,${count}p" >"$work/selected.tsv"
rm -f "$work/all-releases.tsv"
[ "$(wc -l <"$work/selected.tsv")" -eq "$count" ] ||
  die "need $count published releases of $repo, found $(wc -l <"$work/selected.tsv")"

: >"$work/releases.tsv"
: >"$work/inputs.unsorted"
name_re='^(mmt-dpi|mmt-dpi-security)_([a-z]+-[0-9][0-9.]*)_([a-z0-9]+)\.deb$'

while IFS=$'\t' read -r published tag; do
  [[ "$tag" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "unexpected tag name '$tag'"
  epoch=$(date -u -d "$published" +%s) || die "bad published_at '$published' for $tag"
  printf '%s\t%s\t%s\n' "$tag" "$published" "$epoch" >>"$work/releases.tsv"
  log "==> $tag (published $published)"

  assets=()
  while IFS= read -r name; do
    [[ "$name" =~ $name_re ]] && assets+=("$name")
  done < <(gh release view "$tag" --repo "$repo" --json assets --jq '.assets[].name' | LC_ALL=C sort)
  [ "${#assets[@]}" -gt 0 ] ||
    die "$tag has no mmt-dpi_<distro>-<ver>_<arch>.deb assets: it predates the canonical package names and cannot be published"

  dir="$work/$tag"
  mkdir -p "$dir"
  patterns=(-p SHA256SUMS)
  for name in "${assets[@]}"; do patterns+=(-p "$name"); done
  gh release download "$tag" --repo "$repo" --dir "$dir" "${patterns[@]}" ||
    die "download of $tag assets failed"

  [ -s "$dir/SHA256SUMS" ] || die "$tag has no SHA256SUMS asset"
  attest "$dir/SHA256SUMS" "$tag"
  log "    SHA256SUMS: attestation verified"

  for name in "${assets[@]}"; do
    file="$dir/$name"
    [ -f "$file" ] || die "$name was not downloaded from $tag"
    [[ "$name" =~ $name_re ]]
    want_pkg=${BASH_REMATCH[1]}
    distro=${BASH_REMATCH[2]}
    want_arch=${BASH_REMATCH[3]}

    codename=$(codename_for "$distro") ||
      die "$tag/$name: unknown distribution '$distro'; add it to codename_for in scripts/common.sh"
    case " ${APT_ARCHES[*]} " in
      *" $want_arch "*) ;;
      *) die "$tag/$name: unsupported architecture '$want_arch'" ;;
    esac

    expected=$(awk -v n="$name" '$2 == n || $2 == "*" n { print $1 }' "$dir/SHA256SUMS")
    [ -n "$expected" ] || die "$tag/$name is not listed in SHA256SUMS"
    [ "$(printf '%s\n' "$expected" | wc -l)" -eq 1 ] || die "$tag/$name is listed more than once in SHA256SUMS"
    actual=$(sha256sum "$file" | awk '{ print $1 }')
    [ "$actual" = "$expected" ] ||
      die "$tag/$name: SHA256 mismatch (SHA256SUMS $expected, file $actual)"

    attest "$file" "$tag"

    pkg=$(deb_field "$file" Package)
    version=$(deb_field "$file" Version)
    arch=$(deb_field "$file" Architecture)
    [ "$pkg" = "$want_pkg" ] || die "$tag/$name: control Package is '$pkg', file name says '$want_pkg'"
    [ "$arch" = "$want_arch" ] || die "$tag/$name: control Architecture is '$arch', file name says '$want_arch'"
    [[ "$version" =~ ^([0-9]+:)?[0-9][A-Za-z0-9.+~-]*$ ]] || die "$tag/$name: invalid Version '$version'"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$tag" "$tag/$name" "$pkg" "$version" "$arch" "$distro" "$codename" "$actual" >>"$work/inputs.unsorted"
    log "    $name: sha256 + attestation OK -> $codename $pkg $version $arch"
  done
done <"$work/selected.tsv"
rm -f "$work/selected.tsv"

LC_ALL=C sort -t$'\t' -k7,7 -k3,3 -k5,5 -k4,4 "$work/inputs.unsorted" >"$work/inputs.tsv"
rm -f "$work/inputs.unsorted"

dups=$(cut -f3,4,5,7 "$work/inputs.tsv" | LC_ALL=C sort | uniq -d)
[ -z "$dups" ] || die "the same package, version, architecture and suite comes from two inputs: $dups"

log "==> $(wc -l <"$work/inputs.tsv") packages from $count releases verified"
