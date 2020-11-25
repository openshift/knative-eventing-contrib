#!/usr/bin/env bash

source $(dirname $0)/resolve.sh

release=$1

if [ $release = "ci" ]; then
    image_prefix="registry.svc.ci.openshift.org/openshift/knative-nightly:knative-eventing-sources-"
    tag=""
else
    image_prefix="registry.svc.ci.openshift.org/openshift/knative-$release:knative-eventing-sources-"
    tag=""
fi

# Apache Kafka Source
output_file="openshift/release/knative-eventing-kafka-source-ci.yaml"
resolve_resources kafka/source/config/ $output_file $image_prefix $release $tag

# Apache Kafka Channel
output_file="openshift/release/knative-eventing-kafka-channel-ci.yaml"
resolve_resources kafka/channel/config/ $output_file $image_prefix $release $tag
