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
resolve_resources kafka/source/config/ kafka-resolved.yaml $image_prefix $tag
cat kafka-resolved.yaml > $output_file
rm kafka-resolved.yaml

# Apache Kafka Channel
output_file="openshift/release/knative-eventing-kafka-channel-ci.yaml"
resolve_resources kafka/channel/config/ kafka-resolved.yaml $image_prefix $tag
cat kafka-resolved.yaml >> $output_file
rm kafka-resolved.yaml
