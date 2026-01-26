#!/usr/bin/env bash

REKOR_URL=https://rekor-server-trusted-artifact-signer.apps.rosa.rekor-stage.ic5w.p3.openshiftapps.com
IMAGE=quay.io/jstuart/hacbs-docker-build:blob-2

DIGEST=$(crane digest "$IMAGE")
UUID=$(rekor-cli search artifact --rekor_server "$REKOR_URL" --sha "$DIGEST")

rekor-cli get --rekor_server "$REKOR_URL" --uuid "$UUID"
