#!/usr/bin/env bash
set -euo pipefail

#
# Often we need to confirm what versions of a particular rpm exist in each build
# so we can confirm that a particular security vulnerability update has occurred.
# This script should make that easier.
#
# Example usage:
#   ./rpm-version-checker.sh libarchive-3.5.3-5.el9_6 krb5-libs-1.21.1-8.el9_6 pam-1.5.1-25.el9_6
#

# The ubi base image, the (usually 2) release branch builds, and the main branch build
IMAGES_TO_CHECK=(
  registry.access.redhat.com/ubi9/ubi-minimal:latest
  $(./current-release-tags.sh | xargs -I{} echo registry.redhat.io/rhtas/ec-rhel9:{})
  quay.io/conforma/cli:latest
)

RED="\e[31m✘\e[0m"
GREEN="\e[32m✔\e[0m"
YELLOW="\e[33m✔\e[0m"

if ! command -v rpmdev-vercmp &>/dev/null; then
  printf "Error: rpmdev-vercmp not found. Install it with: sudo dnf install rpmdevtools\n"
  exit 1
fi

# Extract the name from a full name-version-release string, e.g.
# libcurl-minimal-7.76.1-40.el9_8.5 -> libcurl-minimal. This is everything
# except the last two hyphen-separated fields, since the name itself may
# contain hyphens.
n_from_nvr() {
  echo "$1" | rev | cut -d- -f3- | rev
}

# Extract the version-release from a full name-version-release string, e.g.
# libcurl-minimal-7.76.1-40.el9_8.5 -> 7.76.1-40.el9_8.5. This is the last two
# hyphen-separated fields, which lets us compare packages whose names differ
# (e.g. curl vs curl-minimal) but that share the same version-release.
vr_from_nvr() {
  echo "$1" | rev | cut -d- -f1-2 | rev
}

# Compare a wanted version-release ($1) against an installed one ($2) and print
# a coloured verdict. rpmdev-vercmp exits 0 when equal, 11 when the first arg is
# newer (i.e. the installed version is older and an upgrade is needed), and 12
# when the installed version is newer. Any other exit code means the comparison
# itself failed (e.g. an unparseable version), so we surface it rather than
# silently reporting success.
report_status() {
  set +o errexit
  rpmdev-vercmp "$1" "$2" >/dev/null 2>&1
  local exit_code="$?"
  set -o errexit
  case "$exit_code" in
    0 | 12) printf "$GREEN\n" ;;
    11)     printf "$RED upgrade needed\n" ;;
    *)      printf "$RED rpmdev-vercmp failed comparing '$1' and '$2' (exit $exit_code)\n"
            return "$exit_code" ;;
  esac
}

for ref in ${IMAGES_TO_CHECK[@]}; do
  printf "🛠️ $ref\n"

  # Set FAST=1 if you're hacking on the script because the podman
  # pull takes a while and there's no point doing it over and over
  if [[ "${FAST:-""}" != "1" ]]; then
    podman pull -q "$ref" > /dev/null
  fi

  # Output some useful info about the image we're investigating
  printf "Digest: $(skopeo inspect --raw "docker://$ref" | sha256sum | awk '{print $1}')\n"
  printf "Created: $(skopeo inspect --no-tags "docker://$ref" | jq -r .Created)\n"

  # List every installed rpm as "name NVR sourcerpm", e.g.
  #   krb5-libs krb5-libs-1.21.1-10.el9_8 krb5-1.21.1-10.el9_8.src.rpm
  all_rpms=$(podman run --rm --entrypoint /bin/bash "$ref" -c "rpm -qa --qf '%{NAME} %{NVR} %{SOURCERPM}\n'")

  # The args should be a list of rpm versions that have the particular vulnerability
  # fix you're interested in. You can find the rpm nvr in the advisory under "Builds".
  for want in "$@"; do
    package_name=$(n_from_nvr "$want")
    want_vr=$(vr_from_nvr "$want")

    # Keep the ones that either ARE this package (so an arg naming a subpackage
    # directly, e.g. krb5-libs, still works) or share its source rpm name (so
    # e.g. curl also matches curl-minimal and libcurl-minimal).
    have=$(
      while read -r name nvr srpm; do
        src_name=$(n_from_nvr "${srpm%.src.rpm}")
        if [[ "$name" == "$package_name" || "$src_name" == "$package_name" ]]; then
          echo "$nvr"
        fi
      done <<< "$all_rpms"
    )

    # Output the details
    printf "$package_name\n"
    printf "* Want $want or better\n"

    if [ -z "$have" ]; then
      printf "  Not installed (no matching package or subpackages found)\n"
    else
      while read -r nvr; do
        printf "  Have $nvr "
        report_status "$want_vr" "$(vr_from_nvr "$nvr")"
      done <<< "$have"
    fi

    printf "\n"
  done
done
