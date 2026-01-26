#!/usr/bin/env bash
set -euo pipefail

REPO="quay.io/jstuart/hacbs-docker-build"
KEY="cosign.key"
mkdir -p blobs predicates

if [[ ! -f cosign.key || ! -f cosign.pub ]]; then
  echo "Generating cosign key pair..."
  cosign generate-key-pair
fi

for i in {1..2}; do
  blob="blobs/file-$i.txt"
  echo "This is blob $i" > "$blob"

  digest=$(oras push "$REPO:blob-$i" "$blob:application/vnd.test.file" 2>&1 | grep "Digest:" | awk '{print $2}')
  echo "Got digest: $digest"

  pred="predicates/predicate-$i.json"
  cat > "$pred" <<EOF
{
  "_type": "https://in-toto.io/Statement/v0.1",
  "subject": [{
    "name": "$REPO:blob-$i",
    "digest": { "sha256": "${digest#sha256:}" }
  }],
  "predicateType": "https://slsa.dev/verification_summary/v0.1",
  "predicate": {
    "verifier": { "id": "conforma.dev" },
    "policy": {
      "uri": "github.com/enterprise-contract/policy",
      "digest": { "sha256": "d$(printf %03d "$i")deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdead" }
    },
    "verification_result": "PASSED",
    "policy_level": "redhat"
  }
}
EOF
REKOR_URL="https://rekor-server-trusted-artifact-signer.apps.rosa.rekor-stage.ic5w.p3.openshiftapps.com"
#REKOR_URL="https://rekor.sigstore.dev"
  cosign attest \
    --key "$KEY" \
    --predicate "$pred" \
    --type "https://slsa.dev/verification_summary/v0.1" \
    --rekor-url $REKOR_URL \
    --rekor-entry-type intoto \
    --new-bundle-format \
    "$REPO:blob-$i"
done
