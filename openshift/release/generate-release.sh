#!/usr/bin/env bash

source $(dirname $0)/resolve.sh

release=$1

image_prefix="quay.io/openshift-knative/knative-eventing-sources-"
output_file="openshift/release/knative-eventing-sources-${release}.yaml"

if [ $release = "ci" ]; then
    image_prefix="image-registry.openshift-image-registry.svc:5000/knative-eventing/knative-eventing-sources-"
    tag=""
else
    image_prefix="quay.io/openshift-knative/knative-eventing-sources-"
    tag=$release
fi

resolve_resources config/ $output_file $image_prefix $release

# Apache Camel-K Source
resolve_resources contrib/camel/config/ kamel-resolved.yaml $image_prefix $release
cat kamel-resolved.yaml >> $output_file

# Apache Kafka Source
resolve_resources contrib/kafka/config/ kafka-resolved.yaml $image_prefix $release
cat kafka-resolved.yaml >> $output_file
