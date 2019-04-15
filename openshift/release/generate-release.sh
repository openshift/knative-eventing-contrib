#!/usr/bin/env bash

source $(dirname $0)/resolve.sh

release=$1

quay_image_prefix="quay.io/openshift-knative/knative-eventing-sources-"
output_file="openshift/release/knative-eventing-sources-${release}.yaml"

resolve_resources config/ $output_file $quay_image_prefix $release

# Apache Camel-K Source
resolve_resources contrib/camel/config/ kamel-resolved.yaml $quay_image_prefix $release
cat kamel-resolved.yaml >> $output_file

# Apache Kafka Source
resolve_resources contrib/kafka/config/ kafka-resolved.yaml $quay_image_prefix $release
cat kafka-resolved.yaml >> $output_file
