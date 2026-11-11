#!/usr/bin/env bash
# summarize-repo.sh: print what an APT repository tree contains.
#
# Usage: scripts/summarize-repo.sh <tree> [<work-dir>]
#
# Prints, as Markdown, the source releases (when <work-dir> from
# scripts/fetch-releases.sh is given), and per suite and architecture the
# packages, versions and sizes read from the Packages indexes, then the totals.
# When GITHUB_STEP_SUMMARY is set, the same text is appended to it.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/common.sh
. "$here/common.sh"

[ $# -ge 1 ] && [ $# -le 2 ] || die "usage: $0 <tree> [<work-dir>]"
tree=$(cd "$1" && pwd) || die "tree $1 not found"
work=${2:-}

human() { numfmt --to=iec-i --suffix=B "$1"; }

summary() {
  local suite arch idx signed n_suites=0 n_pkgs=0
  echo "## APT repository build"
  echo
  if [ -n "$work" ] && [ -s "$work/releases.tsv" ]; then
    echo "Source releases (newest first):"
    echo
    while IFS=$'\t' read -r tag published _epoch; do
      echo "- \`$tag\`, published $published"
    done <"$work/releases.tsv"
    echo
  fi
  echo "| Suite | Arch | Package | Version | Size |"
  echo "|---|---|---|---|---|"
  for suite in "${APT_SUITES[@]}"; do
    [ -f "$tree/dists/$suite/Release" ] || continue
    n_suites=$((n_suites + 1))
    for arch in "${APT_ARCHES[@]}"; do
      idx="$tree/dists/$suite/$APT_COMPONENT/binary-$arch/Packages"
      [ -f "$idx" ] || continue
      while IFS=$'\t' read -r pkg ver size; do
        echo "| $suite | $arch | $pkg | $ver | $(human "$size") |"
        n_pkgs=$((n_pkgs + 1))
      done < <(awk -F': ' '
        /^Package: / { p = $2 } /^Version: / { v = $2 } /^Size: / { s = $2 }
        /^$/ && p != "" { print p "\t" v "\t" s; p = "" }
        END { if (p != "") print p "\t" v "\t" s }' "$idx")
    done
  done
  echo
  signed=unsigned
  if compgen -G "$tree/dists/*/InRelease" >/dev/null; then signed=signed; fi
  echo "- Suites: $n_suites"
  echo "- Package files: $n_pkgs"
  echo "- Pool size: $(human "$(du -sb "$tree/pool" | cut -f1)")"
  echo "- Tree size: $(human "$(du -sb "$tree" | cut -f1)")"
  echo "- Files in tree: $(find "$tree" -type f | wc -l)"
  echo "- Metadata: $signed"
}

out=$(summary)
printf '%s\n' "$out"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  printf '%s\n' "$out" >>"$GITHUB_STEP_SUMMARY"
fi
