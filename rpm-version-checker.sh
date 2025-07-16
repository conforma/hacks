#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

#
# Often we need to confirm what versions of a particular rpm exist in each build
# so we can confirm that a particular security vulnerability update has occurred.
# This script should make it a little easier.
#
# Example usage:
#   ./rpm-version-checker.sh libarchive-3.5.3-5.el9_6 krb5-libs-1.21.1-8.el9_6 pam-1.5.1-25.el9_6
#

IMAGES_TO_CHECK=(
  quay.io/conforma/cli:latest
  registry.redhat.io/rhtas/ec-rhel9:0.6
  registry.redhat.io/rhtas/ec-rhel9:0.5
  registry.access.redhat.com/ubi9/ubi-minimal:latest
)

RED="\e[31m✘\e[0m"
GREEN="\e[32m✔\e[0m"
YELLOW="\e[33m✔\e[0m"

for ref in ${IMAGES_TO_CHECK[@]}; do
  printf "🛠️ $ref\n"

  # Set FAST=1 if you're hacking on the script because the podman
  # pull takes a while and there's no point doing it over and over
  if [[ "${FAST:-""}" != "1" ]]; then
    podman pull -q "$ref" > /dev/null
  fi

  printf "Digest: $(skopeo inspect --raw "docker://$ref" | sha256sum | awk '{print $1}')\n"
  printf "Created: $(skopeo inspect --no-tags "docker://$ref" | jq -r .Created)\n"

  # The args should be a list of rpm versions that have the particular vulernability
  # fix you're interested in. You can find the rpm nvr in the advisory under Builds
  for want in "$@"; do
    # The format is name-version-release but name could possibly have a "-" char
    # in it so we do a little extra work here to get the name right
    package_name=$(echo "$want" | rev | cut -d- -f3- | rev)

    # Use rpm -qa to show what version is installed in the image
    have=$(podman run --rm --entrypoint /bin/bash "$ref" -c "rpm -qa $package_name")

    # Output the details
    printf "$package_name\n"
    printf "* Want $want or better\n"

    if [ -z $have ]; then
      # If it's not installed we're safe
      printf "  Not installed or wrong package name $YELLOW\n"

    else
      # Use rpmdev-vercmp to correctly compare the rpm versions
      # It sets exit code to either 11, 22, or 0
      set +o errexit
      rpmdev-vercmp $want $have >/dev/null 2>/dev/null
      exit_code="$?"
      set -o errexit

      printf "  Have $have "
      if [[ $exit_code == 11 ]]; then
        # $have is older than $want
        printf "$RED upgrade needed\n"

      elif [[ $exit_code == 22 ]]; then
        # $have is newer than $want
        printf "$GREEN\n"

      else
        # $have is the same as $want
        printf "$GREEN\n"
      fi
    fi

    printf "\n"
  done
done
