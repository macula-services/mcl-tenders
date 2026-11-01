#!/bin/sh
# Prints the registry tags this run publishes, as tags=<space-separated list>
# for $GITHUB_OUTPUT, from GITHUB_REF and GITHUB_SHA.
#
#   v* tag : :<semver> ONLY. :latest moves in promote-latest, after attest
#            signed the digest, so :latest always names a signed release.
#   main   : :main and :<sha>, the tip for trying. Nothing follows them.
#   other  : refused, naming the ref. The workflow can be run by hand from any
#            branch, and a branch build must publish nothing.
#
# The complete list comes from here, so this one case governs all of it;
# apps/mcl_tenders_sensor/test/mcl_tenders_sensor_image_channels_tests.erl runs it for each ref.
set -eu

IMAGE=ghcr.io/macula-services/mcl-tenders-sensor
REF="${GITHUB_REF:?GITHUB_REF is not set}"
SHA="${GITHUB_SHA:?GITHUB_SHA is not set}"

case "$REF" in
    refs/tags/v*)    echo "tags=$IMAGE:${REF#refs/tags/v}" ;;
    refs/heads/main) echo "tags=$IMAGE:main $IMAGE:$SHA" ;;
    *) echo "::error::only a v* tag publishes a version, and only main :main and :<sha>; refusing $REF"
       exit 1 ;;
esac
