#!/usr/bin/env bash

IMAGE=quay.io/jstuart/hacbs-docker-build:blob-1
ATTDIGEST=$(oras discover \
  --artifact-type application/vnd.dev.sigstore.bundle.v0.3+json \
  --output json \
  $IMAGE \
| jq -r '.manifests[0].digest')

LAYERDIGEST=$(curl -sL \
  -H "Accept: application/vnd.oci.image.manifest.v1+json" \
  "https://quay.io/v2/jstuart/hacbs-docker-build/manifests/$ATTDIGEST" \
| jq -r '.layers[] 
    | select(.mediaType=="application/vnd.dev.sigstore.bundle.v0.3+json")
    | .digest')

curl -sL \
  -H "Accept: application/octet-stream" \
  "https://quay.io/v2/jstuart/hacbs-docker-build/blobs/$LAYERDIGEST" | jq .dsseEnvelope.payload |tr -d '"' |base64 -d |jq
