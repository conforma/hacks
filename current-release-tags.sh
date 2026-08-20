#!/usr/bin/env bash
set -euo pipefail

# Print the list of content stream tags, e.g. 0.7 0.8.
# Should correspond to the active release branches, e.g. release-v0.7 release-v0.8.

# Method 1: Use data from Pyxis
function content-stream-tags-from-pyxis() {
  # Pyxis uses kerberos for auth, so run kinit if user does not have a current valid kerberos ticket.
  klist -s || kinit
  curl -s --negotiate -u: \
    "https://pyxis.engineering.redhat.com/v1/repositories/registry/registry.access.redhat.com/repository/rhtas/ec-rhel9" \
    | jq -r '.content_stream_tags[]'
}

# Method 2: Use data from the Cicada repo
function content-stream-tags-from-cicada() {
  curl -s \
    "https://gitlab.cee.redhat.com/releng/pyxis-repo-configs/-/raw/main/products/rhtas/rhtas.yaml" \
    | yq -r --yaml-fix-merge-anchor-to-spec '.repositories[].repository|select(.repository=="rhtas/ec-rhel9").content_stream_tags[]'
}

# Two ways to do it:
case "${1-:""}" in
  "--pyxis")
    content-stream-tags-from-pyxis
    ;;
  *)
    content-stream-tags-from-cicada
    ;;
esac
