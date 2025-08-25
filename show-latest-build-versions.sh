#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# Set this to skip the podman pull
FAST="${FAST:-""}"

# Set this for verbose output
VERBOSE="${VERBOSE:-""}"

# Update as required when we cut a new release or stop maintaining an old release
RH_TAGS="${1:-"0.6 0.7 latest"}"

_show_details() {
	local title="$1"
	local ref="$2"
	local ver="${3:-""}"

	# Make sure we have the latest
	if [ "$FAST" != "1" ]; then
		podman pull --quiet $ref >/dev/null
	fi

	# Get the digest
	local digest="$(skopeo inspect "docker://$ref" | jq -r .Digest)"

	# The likely original Konflux built image
	local konflux_image="quay.io/redhat-user-workloads/rhtap-contract-tenant/ec-$ver/cli-$ver@$digest"

	if [ "$VERBOSE" = "1" ]; then
		# Verbose output
		echo ""
		echo "$title"
		echo "$title" | tr '[:print:]' '-'

		echo "Ref:"
		echo "   $ref"

		echo "Pinned ref:"
		echo "   $ref@$digest"

		if [[ -n "$ver" ]]; then
			echo "Likely Konflux build ref:"
			echo "   $konflux_image"
		fi

		# Might not work for GitHub builds
		echo "View attestations maybe:"
		echo "   cosign download attestation $ref@$digest | jq '.payload|@base64d|fromjson'"

		echo "Version:"
		podman run --rm "$ref@$digest" version | sed 's/^/   /'

		echo "Files in /usr/local/bin:"
		podman run --rm --entrypoint /bin/bash "$ref@$digest" -c 'ls -l /usr/local/bin' | sed 's/^/   /'

		echo "Command for poking around:"
		echo "   podman run --rm -it --entrypoint /bin/bash $ref"

		echo ""

	else
		# Brief output
		echo "🛠️ $title"
		echo "$ref@$digest"
		[[ -n "$ver" ]] && echo "$konflux_image"
		podman run --rm "$ref@$digest" version | sed 's/^/   /' | head -3
		echo ""

	fi
}

# Built and pushed by Konflux from a release branch
# (This is shipped to customers with RHTAS)
for t in ${RH_TAGS}; do
	[[ $t == "latest" ]] && ver="v07" || ver="v${t/./}"
	_show_details "Red Hat Build ($t)" "registry.redhat.io/rhtas/ec-rhel9:${t}" "$ver"
done

# Built/pushed by Konflux from main branch
# (Used by Red Hat Konflux)
_show_details "Main branch Konflux build" "quay.io/conforma/cli:latest" "main"

# Built/pushed by GitHub from main branch. Not deprecated, but :latest is preferred.
_show_details "Main branch GitHub build" "quay.io/conforma/cli:snapshot"

# Built/pushed by Konflux from main branch (old repo). Deprecated.
_show_details "Main branch Konflux build (old location)" "quay.io/enterprise-contract/cli:latest" "main"

# Built/pushed by GitHub from main branch (old repo). Deprecated
_show_details "Main branch GitHub build (old location)" "quay.io/enterprise-contract/ec-cli:snapshot"
