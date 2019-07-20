#!/usr/bin/env bash

source $(dirname $0)/resolve.sh

release=$1

#image_prefix="quay.io/openshift-knative/knative-eventing-sources-"
output_file="openshift/release/knative-eventing-kafka-sources-${release}.yaml"

if [ $release = "ci" ]; then
    image_prefix="image-registry.openshift-image-registry.svc:5000/knative-eventing/knative-eventing-sources-"
    tag=""
else
    image_prefix="quay.io/openshift-knative/knative-eventing-sources-"
    tag=$release
fi

# Apache Kafka Source
resolve_resources kafka/source/config/ kafka-resolved.yaml $image_prefix $release
cat kafka-resolved.yaml >> $output_file
rm kafka-resolved.yaml
