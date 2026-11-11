#!/usr/bin/env bash
# smoke-in-container.sh: install mmt-dpi from the Montimage APT repository.
#
# Runs as root inside a Debian or Ubuntu container; scripts/smoke-install.sh
# starts it. The suite is the container's VERSION_CODENAME. Environment:
#   SMOKE_URI      repository URI (https://... or file:/repo)
#   SMOKE_KEYRING  path of the Signed-By keyring in the container; empty means
#                  an UNSIGNED dry-run tree, added with "Trusted: yes" (the
#                  deb822 form of [trusted=yes])
#   SMOKE_EXPECT   optional: the mmt-dpi version that must be installed
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
uri=${SMOKE_URI:?SMOKE_URI is required}
keyring=${SMOKE_KEYRING:-}
expect=${SMOKE_EXPECT:-}

# shellcheck disable=SC1091  # the container's os-release
. /etc/os-release
suite=${VERSION_CODENAME:?no VERSION_CODENAME in /etc/os-release}
echo "==> $PRETTY_NAME: suite $suite from $uri"

apt_update() {
  local i
  for i in 1 2 3 4 5; do
    if apt-get update; then return 0; fi
    echo "apt-get update failed (attempt $i), retrying in 20 s" >&2
    sleep 20
  done
  return 1
}

sources=/etc/apt/sources.list.d/montimage-packages.sources
if [ -n "$keyring" ]; then
  case "$uri" in
    https:*)
      apt_update
      apt-get install -y --no-install-recommends ca-certificates
      ;;
  esac
  install -d -m 0755 /etc/apt/keyrings
  install -m 0644 "$keyring" /etc/apt/keyrings/montimage-archive-keyring.gpg
  trust="Signed-By: /etc/apt/keyrings/montimage-archive-keyring.gpg"
else
  echo "############################################################"
  echo "# WARNING: UNSIGNED dry-run repository. apt is told to     #"
  echo "# trust it (Trusted: yes). Signatures are NOT checked here. #"
  echo "############################################################"
  trust="Trusted: yes"
fi

printf 'Types: deb\nURIs: %s\nSuites: %s\nComponents: main\n%s\n' \
  "$uri" "$suite" "$trust" >"$sources"
echo "==> $sources"
cat "$sources"

apt_update
apt-cache policy mmt-dpi
apt-get install -y mmt-dpi
dpkg -s mmt-dpi

status=$(dpkg-query -W -f '${Status}' mmt-dpi)
[ "$status" = "install ok installed" ] || { echo "ERROR: mmt-dpi status is '$status'" >&2; exit 1; }
installed=$(dpkg-query -W -f '${Version}' mmt-dpi)
if [ -n "$expect" ] && [ "$installed" != "$expect" ]; then
  echo "ERROR: installed mmt-dpi $installed, expected $expect" >&2
  exit 1
fi
echo "==> OK: mmt-dpi $installed installed on $PRETTY_NAME ($suite)"
