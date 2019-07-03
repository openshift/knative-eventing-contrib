#!/usr/bin/env bash

source $(dirname $0)/resolve.sh

## there are no sources, outside of Camel / Kafka, that we care about, atm.

# release=$1

# image_prefix="quay.io/openshift-knative/knative-eventing-sources-"
# output_file="openshift/release/knative-eventing-sources-${release}.yaml"

# if [ $release = "ci" ]; then
#     image_prefix="image-registry.openshift-image-registry.svc:5000/knative-eventing/knative-eventing-sources-"
#     tag=""
# else
#     image_prefix="quay.io/openshift-knative/knative-eventing-sources-"
#     tag=$release
# fi

# resolve_resources config/ $output_file $image_prefix $release

